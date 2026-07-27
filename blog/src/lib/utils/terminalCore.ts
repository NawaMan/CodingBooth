// The arithmetic behind <Terminal>: turning an author's list of commands and
// output into a schedule — when each line starts, how long it takes, and how many
// character steps a typed command needs.
//
// Kept pure and DOM-free (drawCore / connectorCore / videoCore discipline) so the
// component is left with nothing but markup and CSS, and so the interesting cases —
// a negative typing speed, an empty command, a line that is neither a command nor
// output — are testable without a browser.
//
// Every function is total: bad input yields a harmless value (a default, 0, an empty
// list), never a throw. A slide must not blow up because someone typed charMs="fast".
//
// The schedule is expressed in milliseconds and consumed as plain CSS
// animation-delay / animation-duration. That is the whole trick behind "the terminal
// rides the AnimationBar clock": a CSS @keyframes animation is also a Web Animations
// object, so AnimationBar scrubs the typing without this component knowing it exists.

/** How an output line reads. `plain` inherits the console's foreground. */
export type Tone = 'plain' | 'ok' | 'warn' | 'error' | 'muted';

const TONES: readonly Tone[] = ['plain', 'ok', 'warn', 'error', 'muted'];

/**
 * One line of the session, as an author writes it.
 *
 * `{ cmd }` is typed after the prompt; `{ out }` appears whole. A bare string is
 * shorthand for output — the common case, since commands are the minority of lines.
 */
export interface TerminalLine {
	/** A command: rendered after the prompt and typed out character by character. */
	cmd?: string;
	/** Program output: rendered without a prompt, revealed all at once. */
	out?: string;
	/** Colour role for an output line. Ignored on a command. */
	tone?: Tone;
}

/** What the author may pass in `lines`. */
export type TerminalInput = TerminalLine | string;

/** A line once its kind and tone are resolved. */
export interface NormalizedLine {
	kind: 'cmd' | 'out';
	text: string;
	tone: Tone;
}

/** A normalized line once it has a place on the timeline. */
export interface ScheduledLine extends NormalizedLine {
	/** Character steps for a typed command; 0 for output. */
	chars: number;
	/** When this line begins, in ms from the start of the animation. */
	delayMs: number;
	/** How long it takes to appear, in ms. */
	durationMs: number;
}

/** The knobs on the typewriter. All in milliseconds. */
export interface TerminalTiming {
	/** Per character of a typed command. */
	charMs?: number;
	/** Dead air before the first line. */
	startMs?: number;
	/** Beat after a command finishes typing, before its output lands. */
	pauseMs?: number;
	/** Fade-in of one output line. */
	outMs?: number;
}

/** The defaults: an unhurried but not sleepy console. */
export const DEFAULT_TIMING: Required<TerminalTiming> = {
	charMs: 55,
	startMs: 300,
	pauseMs: 350,
	outMs: 180
};

/** A schedule: the placed lines plus the length of the whole envelope. */
export interface Schedule {
	lines: ScheduledLine[];
	/** Total length in ms — where a resting caret belongs. */
	envelopeMs: number;
}

/**
 * A non-negative, finite duration, or the fallback. Zero is allowed and meaningful
 * (`charMs: 0` types instantly), which is why this is not a truthiness check.
 */
export function duration(value: unknown, fallback: number): number {
	return typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : fallback;
}

/**
 * Resolve the kind, text and tone of each entry, dropping anything unusable.
 *
 * A bare string is output. An object with a string `cmd` is a command (a `cmd` wins
 * over an `out` on the same object — writing both is a typo, and the prompt is the
 * more specific intent). An entry with neither is dropped rather than rendered as a
 * blank row the author never asked for. An unknown `tone` falls back to `plain`.
 */
export function normalizeLines(input: readonly TerminalInput[] | null | undefined): NormalizedLine[] {
	const lines: NormalizedLine[] = [];
	for (const entry of input ?? []) {
		if (typeof entry === 'string') {
			lines.push({ kind: 'out', text: entry, tone: 'plain' });
			continue;
		}
		if (!entry || typeof entry !== 'object') continue;

		const tone = TONES.includes(entry.tone as Tone) ? (entry.tone as Tone) : 'plain';
		if (typeof entry.cmd === 'string') lines.push({ kind: 'cmd', text: entry.cmd, tone: 'plain' });
		else if (typeof entry.out === 'string') lines.push({ kind: 'out', text: entry.out, tone });
	}
	return lines;
}

/**
 * How many `steps()` a typed command needs. Always at least 1: `steps(0)` is invalid
 * CSS and would drop the whole animation, so an empty command still gets one no-op
 * step (over a zero duration, so nothing is seen).
 */
export function stepsFor(chars: number): number {
	return Number.isFinite(chars) && chars > 1 ? Math.floor(chars) : 1;
}

/**
 * Lay the lines on one timeline.
 *
 * A command types for `charMs` per character, then the console pauses for `pauseMs`
 * before whatever follows — that beat is what makes it read as a machine thinking
 * rather than a text field being filled. Output lines then land one `outMs` after
 * another, so a block of output cascades instead of flashing in as a slab.
 *
 * The returned `envelopeMs` is where the session ends — the moment a resting caret
 * should appear, and the 100% of the transport track.
 */
export function scheduleLines(
	input: readonly TerminalInput[] | null | undefined,
	timing: TerminalTiming = {}
): Schedule {
	const charMs = duration(timing.charMs, DEFAULT_TIMING.charMs);
	const startMs = duration(timing.startMs, DEFAULT_TIMING.startMs);
	const pauseMs = duration(timing.pauseMs, DEFAULT_TIMING.pauseMs);
	const outMs = duration(timing.outMs, DEFAULT_TIMING.outMs);

	let clock = startMs;
	const lines = normalizeLines(input).map((line) => {
		const chars = line.kind === 'cmd' ? line.text.length : 0;
		const durationMs = line.kind === 'cmd' ? chars * charMs : outMs;
		const scheduled: ScheduledLine = { ...line, chars, delayMs: clock, durationMs };
		clock += durationMs + (line.kind === 'cmd' ? pauseMs : 0);
		return scheduled;
	});

	return { lines, envelopeMs: clock };
}

// --- Markers: the transport's chapters, and the beats Space steps through ---------
//
// A COMMAND is a marker. Its `start` is where it begins typing; its `end` is where its
// output has finished landing — i.e. the start of the next command, or the end of the
// session. `end` is the CHECKPOINT: the natural place for a session to stop so the
// presenter can talk. Anything before the first command (the `startMs` dead air) belongs
// to no marker.
//
// Two clocks meet here, so beware of one thing: `scheduleLines` is the authority on the
// envelope, not the browser's animations (whose end times drift by a rounding ms). Every
// query below is answered against these numbers, and only the SEEK is handed to the
// Web Animations API.

/** One command, and the span of the session it owns. */
export interface Marker {
	/** Index into the marker list (not into `schedule.lines`). */
	index: number;
	/** The command text, for the tick's tooltip. */
	label: string;
	/** When it starts typing. */
	start: number;
	/** When its output has finished — the checkpoint Space plays to. */
	end: number;
}

/**
 * Milliseconds of slack when comparing a playhead against a marker time.
 *
 * The playhead is sampled from real animation clocks, so it lands a fraction past the
 * checkpoint it was told to stop at. Without this, "is there a step after t?" answers
 * yes at the checkpoint it just reached, and Space would step onto the spot it is
 * already standing on.
 */
const EPS = 1;

/**
 * The commands, in order, each spanning up to the next one. A session with no commands
 * (pure output) has no markers — nothing to step to, and the transport shows no ticks.
 */
export function markersOf(schedule: Schedule): Marker[] {
	const cmds = schedule.lines
		.map((line, i) => ({ line, i }))
		.filter(({ line }) => line.kind === 'cmd');

	return cmds.map(({ line }, n) => {
		const next = cmds[n + 1];
		return {
			index: n,
			label: line.text,
			start: line.delayMs,
			// Up to the next command, or to the end of the session.
			end: next ? next.line.delayMs : schedule.envelopeMs
		};
	});
}

/**
 * The next checkpoint strictly after `t` — where a forward step should stop. `null` once
 * the session is spent, which is what tells Space to fall through and page the deck.
 */
export function nextCheckpoint(markers: readonly Marker[], t: number): number | null {
	if (!Number.isFinite(t)) return null;
	for (const m of markers) if (m.end > t + EPS) return m.end;
	return null;
}

/**
 * Where a backward step should land: the last STOP strictly before `t`.
 *
 * The stops are `0` (the beginning — a blank console) followed by every checkpoint, which
 * is precisely the set of positions stepping FORWARD produces. That symmetry is the whole
 * point: back and forward must walk the same states, or Shift+Space cannot undo Space.
 *
 * The obvious-looking alternative — step back to the previous command's *start* — is
 * wrong, and subtly so. A forward step ends on a command's END (its output on screen); a
 * command's start shows nothing typed at all. So the two directions would land on
 * different sets of positions, and from the first command's start there would be nothing
 * earlier at all: `hasPrev` would go false and Shift+Space would page the deck away
 * instead of rewinding to the beginning.
 *
 * `null` only at the very top, so Shift+Space pages back rather than trapping the
 * presenter on a console they have already rewound.
 */
export function prevCheckpoint(markers: readonly Marker[], t: number): number | null {
	if (!Number.isFinite(t) || t <= EPS) return null;
	let found = 0; // the beginning is always a stop
	for (const m of markers) {
		if (m.end < t - EPS) found = m.end;
		else break;
	}
	return found;
}

/**
 * The stops, in order: one per command, at the moment its output has finished landing.
 *
 * THE TICKS ARE DRAWN AT THESE, not at the commands' starts. A tick has to mean "Space
 * parks here" — draw them at the starts instead and the first Space appears to skip the
 * first tick entirely (it stops at the first command's END, which is where the *second*
 * command begins, i.e. under the second tick). The marks must be the stops.
 */
export function checkpointsOf(markers: readonly Marker[]): number[] {
	return markers.map((m) => m.end);
}

/**
 * How many stops the playhead has passed — the count of ticks that should read as
 * "reached". 0 before the first, `markers.length` at the end of the session.
 */
export function reachedCount(markers: readonly Marker[], t: number): number {
	if (!Number.isFinite(t)) return 0;
	let n = 0;
	for (const m of markers) {
		// Not `EPS` here: that slack absorbs a clock OVERSHOOT past a stop, and using it
		// in this direction would light a tick a millisecond before the playhead got there.
		// Only float dust needs forgiving — a step lands on its checkpoint exactly.
		if (m.end > t + 1e-6) break;
		n++;
	}
	return n;
}

/**
 * How far through the session, as a percentage — for the transport fill and the tick
 * positions. A zero or NaN envelope yields 0 rather than an Infinity that CSS would
 * silently drop.
 */
export function percentOf(t: number, envelopeMs: number): number {
	if (!Number.isFinite(t) || !Number.isFinite(envelopeMs) || envelopeMs <= 0) return 0;
	return Math.min(100, Math.max(0, (t / envelopeMs) * 100));
}

/**
 * Magnetic ticks: a seek landing within `toleranceMs` of one of `times` snaps to it.
 *
 * Pass the CHECKPOINTS — the same times the ticks are drawn at. A pointer aimed at a
 * tick is asking for that stop, but a few pixels of aim would otherwise drop the
 * playhead a hair before it, leaving the console one output line short of the state the
 * mark promises. Snapping makes the visible marks mean what they look like they mean,
 * without making them click targets that would block a drag.
 *
 * Ties go to the earlier time, and a non-finite `t` is returned untouched.
 */
export function snapTime(t: number, times: readonly number[], toleranceMs: number): number {
	if (!Number.isFinite(t) || !Number.isFinite(toleranceMs) || toleranceMs <= 0) return t;

	let best = t;
	let bestGap = toleranceMs;
	for (const time of times) {
		const gap = Math.abs(time - t);
		if (gap < bestGap) {
			best = time;
			bestGap = gap;
		}
	}
	return best;
}
