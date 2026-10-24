// replayCore — the VOD replay scheduler, with the clock and the outside world injected.
//
// It is handed the parsed timeline and is ticked with the video clock (seconds since the
// recording started). Every event that has fallen due is performed in order: deck
// actions go to the slides window (`send`), ink is written to the ink book (`ink`), and
// a stroke with a duration is redrawn a little more on every tick until it is whole.
//
// The one rule that is not "fire at time t": after a `goto` the slides window reloads,
// and a command sent to a page that is still loading is lost. So a `goto` makes the
// runner WAIT until the slides window says `here` for that page (or `waitLimit` passes),
// and whatever fell due meanwhile fires at once when it does. Waiting does not shift the
// later lines — each still fires at its own time — so a slow load never accumulates.
//
// Pure: no timers, no DOM, no stores — tests drive it with a fake clock.

import { landingPath, partialPoints, type TimelineAction, type TimelineEvent } from './timelineCore';
import type { Stroke } from '$lib/annotate/annotateCore';

export type InkOp =
	| { op: 'put'; slide: string; stroke: Stroke }
	| { op: 'erase'; slide: string; ids: string[] }
	| { op: 'clear'; slide: string };

export interface ReplayIO {
	/** Perform a deck action in the slides window. */
	send(action: TimelineAction): void;
	/** Change the ink book. `slide` is the timeline's name ('*' = the whole deck). */
	ink(op: InkOp): void;
	/** Something the speaker should know (a page that never said `here`, …). */
	warn?(message: string): void;
}

interface Drawing {
	ev: TimelineEvent & { kind: 'ink'; op: 'draw' };
	start: number;
}

export class ReplayRunner {
	private i = 0;
	private waitingFor: string | null = null;
	private waitingSince = 0;
	private drawing: Drawing[] = [];
	private ended = false;

	constructor(
		private readonly events: TimelineEvent[],
		private readonly deckKey: string,
		private readonly io: ReplayIO,
		private readonly waitLimit = 8
	) {}

	/** The time of the last line — how long the take will be (an `end` line, or the last action). */
	get duration(): number {
		return this.events.length ? this.events[this.events.length - 1].t : 0;
	}

	/** Every line performed, every stroke finished? */
	get done(): boolean {
		return this.ended || (this.i >= this.events.length && this.drawing.length === 0);
	}

	/** Is the runner holding for a page to load? */
	get waiting(): boolean {
		return this.waitingFor !== null;
	}

	/** Perform the lines at the very start (t ≤ `upTo`) BEFORE the clock runs — the opening
	    `goto` — so the video does not open on a page mid-load. */
	prime(upTo = 0): void {
		this.run(upTo, true);
	}

	/** The slides window has loaded `path` (its pathname, no trailing slash). */
	here(path: string): void {
		if (this.waitingFor !== null && path === this.waitingFor) this.waitingFor = null;
	}

	/** Advance to clock time `t` (seconds). */
	tick(t: number): void {
		if (this.ended) return;
		this.run(t, false);
		for (const d of this.drawing) {
			const f = d.ev.dur > 0 ? (t - d.start) / d.ev.dur : 1;
			const stroke = { ...d.ev.stroke, points: partialPoints(d.ev.stroke.points, f) };
			this.io.ink({ op: 'put', slide: d.ev.slide, stroke });
		}
		this.drawing = this.drawing.filter((d) => d.ev.dur > 0 && t - d.start < d.ev.dur);
	}

	private run(t: number, priming: boolean): void {
		while (this.i < this.events.length && this.events[this.i].t <= t) {
			if (this.waitingFor !== null) {
				if (t - this.waitingSince < this.waitLimit && !priming) return;
				if (priming) return;
				this.io.warn?.(`The slides window did not finish loading ${this.waitingFor} — carrying on.`);
				this.waitingFor = null;
			}
			const ev = this.events[this.i++];
			this.perform(ev, t);
			if (this.ended) return;
		}
	}

	private perform(ev: TimelineEvent, t: number): void {
		switch (ev.kind) {
			case 'end':
				this.ended = true;
				return;
			case 'ink':
				if (ev.op === 'draw') {
					if (ev.dur > 0) {
						// Starts where it would have, even when it fires late after a load.
						this.drawing.push({ ev, start: Math.min(ev.t, t) });
						this.io.ink({ op: 'put', slide: ev.slide, stroke: { ...ev.stroke, points: partialPoints(ev.stroke.points, 0) } });
					} else this.io.ink({ op: 'put', slide: ev.slide, stroke: ev.stroke });
				} else if (ev.op === 'erase') this.io.ink({ op: 'erase', slide: ev.slide, ids: ev.ids });
				else this.io.ink({ op: 'clear', slide: ev.slide });
				return;
			case 'goto':
				this.io.send(ev);
				this.waitingFor = landingPath(ev.href, this.deckKey);
				this.waitingSince = t;
				return;
			default:
				this.io.send(ev);
		}
	}
}
