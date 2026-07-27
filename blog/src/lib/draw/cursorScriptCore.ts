// Pure compiler for <Cursor>'s CHAINED command scripts — warpTo/moveTo/
// around/attention, composed into one flight. No component imports, no DOM,
// no stores: the same discipline cursorCore.ts follows. Cursor.svelte
// resolves every command's `at` (and `around`'s centre) against blockAnchors
// first (Connector's job); this module only ever sees already-resolved
// points.
//
// WHY THIS ISN'T JUST CSS animation-iteration-count/direction: those apply
// to a WHOLE @keyframes block, not one leg of a chain — there's no way to
// loop just the `moveTo` in the middle and then continue to the `around`.
// So every repeat/bounce/lap is baked directly into the generated stop
// list, which is also why `around` needs no new Draw PathShape: the
// ellipse is sampled into literal points here, same as any other command.
// The same trick handles a size CHANGE mid-flight: SpriteStop already
// carries w/h per stop, so `size` just varies what those fields hold —
// no new Sprite machinery, and `attention`'s pulse is nothing more than a
// couple of stops with a bigger w/h at the SAME x/y.
//
// SEMANTICS (pin these — see cursorScriptCore.test.ts):
//   - The FIRST command only establishes the starting pose (no motion cost).
//     A script of length 1 is a static cursor, exactly like a one-entry
//     `path`.
//   - warpTo(at): an instant cut — two stops ~WARP_SECONDS apart, so the
//     browser has no time to interpolate. Becomes the new "current" point.
//   - moveTo(at, {times, period}): `times` ONE-WAY LEGS, alternating
//     direction, starting toward `at` — leg 1 arrives at `at`, leg 2
//     returns to wherever the command started, leg 3 arrives again, and so
//     on. times=1 (the default) is therefore a single direct arrival, NOT
//     a round trip — "current" becomes `at`. times=2 is exactly one
//     there-and-back "shake", ending back where the command started, so
//     "current" is unchanged. Odd `times` ends at `at`; even `times` ends
//     at the start — pick accordingly when chaining what comes next.
//   - around(at, rx, ry, {times, period}): `at` is the ORBIT CENTRE.
//     Entry angle is computed from the CURRENT point relative to the
//     centre (so entering the loop is a natural swoop onto the ring, not
//     an arbitrary snap to angle 0), then `times` full laps of `period`
//     seconds each. Ends back at that same entry angle — "current" becomes
//     the ring point at the entry angle (which may differ slightly from
//     the pre-orbit point if it wasn't already sitting on the ellipse).
//   - attention({times, period, scale}): the cursor calling attention to
//     ITSELF — pulses the glyph up to `scale`× its ambient size and back,
//     `times` times, `period` seconds per pulse, IN PLACE. Never moves
//     "current". Has no `at`: as the very first command (nothing to point
//     at yet) it degenerates to pulsing at the canvas origin — put a
//     warpTo/moveTo first.
//   - `size` on ANY command overrides the glyph's box size starting with
//     that command, staying in effect (ambient) until the next command
//     that sets its own — so a size set on command 2 is still in force for
//     commands 4, 5, … unless one of them overrides it again.
//   - `click` on any command flashes a ripple where it lands: once for
//     warpTo's arrival, once per moveTo repetition's outward arrival, once
//     per completed orbit lap, once per attention pulse's peak.
import { finite } from './drawCore';
import { cursorRippleRadius } from './cursorCore';
import type { CursorAt, CursorRipple } from './cursorCore';
import type { Point, SpriteStop } from './types';

interface CommandCommon {
	/** Flash a click ripple where this command's motion lands. */
	click?: boolean;
	/** Override the glyph's box size (canvas px) starting with this
	 *  command — ambient until the next command that sets its own. */
	size?: number;
}

export interface CursorWarpCommand extends CommandCommon {
	kind: 'warpTo';
	at: CursorAt;
}

export interface CursorMoveCommand extends CommandCommon {
	kind: 'moveTo';
	at: CursorAt;
	/** One-way legs, alternating toward/away from `at`. Default 1 — a
	 *  single direct arrival, no return. */
	times?: number;
	/** Seconds per leg. Default 3. */
	period?: number;
}

export interface CursorAroundCommand extends CommandCommon {
	kind: 'around';
	/** The orbit's CENTRE. */
	at: CursorAt;
	rx: number;
	ry: number;
	/** Full laps to make. Default 1. */
	times?: number;
	/** Seconds per lap. Default 3. */
	period?: number;
}

/** The cursor calling attention to ITSELF — a size pulse in place, not a
 *  move. No `at`: it always happens wherever the flight currently is. */
export interface CursorAttentionCommand extends CommandCommon {
	kind: 'attention';
	/** Pulses to make. Default 1. */
	times?: number;
	/** Seconds per pulse (grow + settle). Default 0.5. */
	period?: number;
	/** Peak size as a multiple of the ambient size. Default 1.4. */
	scale?: number;
}

/** One step of a chained Cursor flight, author-facing (`at`/`around`'s centre
 *  may still be a Block name — Cursor.svelte resolves it before compiling). */
export type CursorCommand =
	| CursorWarpCommand
	| CursorMoveCommand
	| CursorAroundCommand
	| CursorAttentionCommand;

/** A CursorCommand with every point already resolved to canvas px. What
 *  `compileScript` actually consumes. */
export type ResolvedCursorCommand =
	| { kind: 'warpTo'; at: Point; click: boolean; size?: number }
	| { kind: 'moveTo'; at: Point; times: number; period: number; click: boolean; size?: number }
	| {
			kind: 'around';
			at: Point;
			rx: number;
			ry: number;
			times: number;
			period: number;
			click: boolean;
			size?: number;
	  }
	| { kind: 'attention'; times: number; period: number; scale: number; click: boolean; size?: number };

export interface CursorScriptResult {
	stops: SpriteStop[];
	ripples: CursorRipple[];
	/** The whole flight's duration in seconds — feed straight to Cursor's
	 *  `animate`. 0 for a single-command (static) script. */
	totalSeconds: number;
}

const WARP_SECONDS = 0.05;
const SAMPLES_PER_LAP = 32;

const safePoint = (p: Point): Point => [finite(p[0]), finite(p[1])];
const posOf = (cmd: ResolvedCursorCommand): Point => {
	if (cmd.kind === 'around') return [finite(cmd.at[0]) + Math.max(0, finite(cmd.rx)), finite(cmd.at[1])];
	if (cmd.kind === 'attention') return [0, 0]; // no position of its own — see the doc above.
	return safePoint(cmd.at);
};

/**
 * Compile a chained command list into Sprite `stops` + ripple checkpoints,
 * exactly like `cursorSpriteStops`/`cursorRipples` do for the simpler
 * waypoint-list `path` prop, just over heterogeneous, possibly-repeating
 * segments. Degenerate-safe: empty input → nothing; a single command → a
 * static pose; every coordinate/timing/size value coerces finite.
 */
export function compileScript(commands: ResolvedCursorCommand[], size: number): CursorScriptResult {
	if (commands.length === 0) return { stops: [], ripples: [], totalSeconds: 0 };
	const box = Math.max(1, finite(size, 40));

	const frames: { t: number; x: number; y: number; size: number }[] = [];
	const ripples: CursorRipple[] = [];

	// Ambient glyph size: starts at `box`, and any command's own `size`
	// (positive, finite) becomes the new ambient from then on.
	let curSize = box;
	const applySize = (s: number | undefined) => {
		if (s == null) return;
		const v = finite(s);
		if (v > 0) curSize = v;
	};

	applySize(commands[0].size);
	let pos = posOf(commands[0]);
	frames.push({ t: 0, x: pos[0], y: pos[1], size: curSize });
	if (commands[0].click) ripples.push({ x: pos[0], y: pos[1], r: cursorRippleRadius(curSize), delaySec: 0 });

	let t = 0;
	for (let i = 1; i < commands.length; i++) {
		const cmd = commands[i];
		applySize(cmd.size);
		if (cmd.kind === 'warpTo') {
			const to = safePoint(cmd.at);
			t += WARP_SECONDS;
			frames.push({ t, x: to[0], y: to[1], size: curSize });
			if (cmd.click) ripples.push({ x: to[0], y: to[1], r: cursorRippleRadius(curSize), delaySec: t });
			pos = to;
		} else if (cmd.kind === 'moveTo') {
			const to = safePoint(cmd.at);
			const times = Math.max(1, Math.round(finite(cmd.times, 1)));
			const period = Math.max(0, finite(cmd.period, 3));
			const home = pos; // where this command departs FROM
			// `times` counts LEGS, alternating direction, starting toward the
			// target: leg 1 arrives at `at`, leg 2 returns to `home`, leg 3
			// arrives at `at` again, and so on. times=1 (the default) is
			// therefore a single one-way arrival — NOT a round trip; times=2
			// is exactly one there-and-back "shake", ending back at `home`.
			for (let leg = 1; leg <= times; leg++) {
				const toTarget = leg % 2 === 1;
				const dest = toTarget ? to : home;
				t += period;
				frames.push({ t, x: dest[0], y: dest[1], size: curSize });
				if (cmd.click && toTarget)
					ripples.push({ x: to[0], y: to[1], r: cursorRippleRadius(curSize), delaySec: t });
			}
			// Odd leg count ends AT the target (so a chain naturally continues
			// from there); even leg count ends back at `home` (a pure shake).
			pos = times % 2 === 1 ? to : home;
		} else if (cmd.kind === 'around') {
			// entry angle from the CURRENT point relative to the centre, so
			// the loop is entered smoothly rather than snapping to angle 0.
			const cx = finite(cmd.at[0]);
			const cy = finite(cmd.at[1]);
			const rx = Math.max(0, finite(cmd.rx));
			const ry = Math.max(0, finite(cmd.ry));
			const times = Math.max(1, Math.round(finite(cmd.times, 1)));
			const period = Math.max(0, finite(cmd.period, 3));
			const dx = pos[0] - cx;
			const dy = pos[1] - cy;
			const entryAngle = dx === 0 && dy === 0 ? 0 : Math.atan2(dy, dx);
			const totalSteps = SAMPLES_PER_LAP * times;
			const stepDt = totalSteps > 0 ? (period * times) / totalSteps : 0;
			for (let k = 1; k <= totalSteps; k++) {
				const angle = entryAngle + (2 * Math.PI * k) / SAMPLES_PER_LAP;
				const x = cx + rx * Math.cos(angle);
				const y = cy + ry * Math.sin(angle);
				t += stepDt;
				frames.push({ t, x, y, size: curSize });
				if (cmd.click && k % SAMPLES_PER_LAP === 0)
					ripples.push({ x, y, r: cursorRippleRadius(curSize), delaySec: t });
			}
			const last = frames[frames.length - 1];
			pos = [last.x, last.y];
		} else {
			// attention: a size pulse IN PLACE — never touches `pos`.
			const times = Math.max(1, Math.round(finite(cmd.times, 1)));
			const period = Math.max(0, finite(cmd.period, 0.5));
			const scale = Math.max(1, finite(cmd.scale, 1.4));
			const restSize = curSize;
			const peakSize = restSize * scale;
			for (let p = 0; p < times; p++) {
				t += period / 2;
				frames.push({ t, x: pos[0], y: pos[1], size: peakSize });
				if (cmd.click) ripples.push({ x: pos[0], y: pos[1], r: cursorRippleRadius(peakSize), delaySec: t });
				t += period / 2;
				frames.push({ t, x: pos[0], y: pos[1], size: restSize });
			}
		}
	}

	const totalSeconds = frames.length > 1 ? Math.max(frames[frames.length - 1].t, 0) : 0;
	const denom = totalSeconds > 0 ? totalSeconds : 1;
	const stops: SpriteStop[] = frames.map((f) => {
		const s = Math.max(1, finite(f.size, box));
		return {
			pct: frames.length > 1 ? Math.round((f.t / denom) * 10000) / 100 : 0,
			x: Math.round(f.x - s / 2),
			y: Math.round(f.y - s / 2),
			w: s,
			h: s,
			rot: 0
		};
	});

	return { stops, ripples, totalSeconds };
}

/** Authoring sugar over a plain, serializable `CursorCommand[]` — chaining
 *  reads naturally but nothing here executes anything; `.build()` just
 *  returns the array `compileScript`/`Cursor` consume. */
export interface CursorScriptBuilder {
	warpTo(at: CursorAt, opts?: { click?: boolean; size?: number }): CursorScriptBuilder;
	moveTo(
		at: CursorAt,
		opts?: { times?: number; period?: number; click?: boolean; size?: number }
	): CursorScriptBuilder;
	around(
		at: CursorAt,
		rx: number,
		ry: number,
		opts?: { times?: number; period?: number; click?: boolean; size?: number }
	): CursorScriptBuilder;
	attention(opts?: {
		times?: number;
		period?: number;
		scale?: number;
		click?: boolean;
		size?: number;
	}): CursorScriptBuilder;
	build(): CursorCommand[];
}

export function cursorScript(): CursorScriptBuilder {
	const commands: CursorCommand[] = [];
	const builder: CursorScriptBuilder = {
		warpTo(at, opts) {
			commands.push({ kind: 'warpTo', at, ...opts });
			return builder;
		},
		moveTo(at, opts) {
			commands.push({ kind: 'moveTo', at, ...opts });
			return builder;
		},
		around(at, rx, ry, opts) {
			commands.push({ kind: 'around', at, rx, ry, ...opts });
			return builder;
		},
		attention(opts) {
			commands.push({ kind: 'attention', ...opts });
			return builder;
		},
		build() {
			return commands;
		}
	};
	return builder;
}
