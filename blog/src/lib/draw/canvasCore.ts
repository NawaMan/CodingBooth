// Pure helpers for <Canvas> — the imperative JS/TS drawing surface that rides
// the same keyframe playhead as the rest of the Draw family. Everything here is
// DOM-free so it unit-tests without a browser (like drawCore/chartCore).
//
// The component owns a hidden CSS @keyframes "clock" so AnimationBar discovers
// it via getAnimations() and scrubs it (see Canvas.svelte). This file owns the
// OPTIONAL keyframes-object layer: an author who wants named value tracks passes
// `keyframes={[{ pct, ease?, ...numbers }]}` and, each frame, gets those numbers
// interpolated at the current playhead percent — same `pct` (0–100) + `ease`
// vocabulary as LineStop/SpriteStop, but interpolated in JS because a canvas has
// no CSS to tween.

/** A JS easing: one of the CSS-named curves, or a custom (0..1)->(0..1) fn.
 *  Named curves are polynomial approximations of the CSS timing functions —
 *  close enough for hand-drawn motion, and exact for `linear`. */
export type Ease = 'linear' | 'ease' | 'ease-in' | 'ease-out' | 'ease-in-out' | ((t: number) => number);

/** One keyframe for the optional value-track layer: a percent (0–100) along the
 *  clock, an optional `ease` for the segment STARTING here (mirrors LineStop),
 *  and any number of named numeric tracks that interpolate between stops. */
export interface CanvasStop {
	pct: number;
	ease?: Ease;
	[key: string]: number | Ease | undefined;
}

/** Coerce to a finite number, else `fallback` (mirrors drawCore.finite). */
export function finite(value: unknown, fallback = 0): number {
	return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
}

/** Clamp `v` into [lo, hi]. */
export function clamp(v: number, lo: number, hi: number): number {
	return v < lo ? lo : v > hi ? hi : v;
}

const easings: Record<string, (t: number) => number> = {
	linear: (t) => t,
	'ease-in': (t) => t * t,
	'ease-out': (t) => 1 - (1 - t) * (1 - t),
	'ease-in-out': (t) => (t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2),
	// CSS `ease` = cubic-bezier(.25,.1,.25,1); ease-in-out is a faithful stand-in.
	ease: (t) => (t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2)
};

/** Resolve an Ease (name or fn) to a clamped easing function. Unknown → linear. */
export function easeFn(ease: Ease | undefined): (t: number) => number {
	if (typeof ease === 'function') return (t) => ease(clamp(t, 0, 1));
	const f = easings[ease ?? 'linear'] ?? easings.linear;
	return (t) => f(clamp(t, 0, 1));
}

/** The numeric track names a stop set defines (every key except pct/ease),
 *  in first-seen order across all stops. */
export function trackKeys(stops: CanvasStop[]): string[] {
	const keys: string[] = [];
	for (const s of stops)
		for (const k of Object.keys(s))
			if (k !== 'pct' && k !== 'ease' && typeof s[k] === 'number' && !keys.includes(k)) keys.push(k);
	return keys;
}

/** Interpolate every numeric track at playhead percent `pct` (0–100).
 *  Stops are sorted by pct; before the first / after the last, the values hold
 *  at the nearest stop (matching how the CSS shapes clamp with fill:both). The
 *  segment's easing comes from the LEFT stop's `ease`. A track absent from a
 *  bounding stop falls back to that stop's nearest defined value, so partial
 *  stops still interpolate sensibly. Returns {} for <2 stops or no tracks. */
export function interpAt(stops: CanvasStop[], pct: number): Record<string, number> {
	if (!Array.isArray(stops) || stops.length === 0) return {};
	const sorted = [...stops].sort((a, b) => finite(a.pct) - finite(b.pct));
	const keys = trackKeys(sorted);
	if (keys.length === 0) return {};

	// valueAt: a stop's value for a track, else the nearest stop that defines it.
	const valueAt = (index: number, key: string): number => {
		if (typeof sorted[index][key] === 'number') return sorted[index][key] as number;
		for (let d = 1; d < sorted.length; d++) {
			const lo = index - d,
				hi = index + d;
			if (lo >= 0 && typeof sorted[lo][key] === 'number') return sorted[lo][key] as number;
			if (hi < sorted.length && typeof sorted[hi][key] === 'number') return sorted[hi][key] as number;
		}
		return 0;
	};

	const p = clamp(pct, 0, 100);
	// Find the segment [i, i+1] containing p; clamp at the ends.
	let i = 0;
	while (i < sorted.length - 1 && finite(sorted[i + 1].pct) <= p) i++;
	const a = sorted[i];
	const b = sorted[Math.min(i + 1, sorted.length - 1)];
	const pa = finite(a.pct);
	const pb = finite(b.pct);
	const span = pb - pa;
	const u = span > 0 ? easeFn(a.ease)((p - pa) / span) : 0;

	const out: Record<string, number> = {};
	for (const k of keys) {
		const va = valueAt(i, k);
		const vb = valueAt(Math.min(i + 1, sorted.length - 1), k);
		out[k] = va + (vb - va) * u;
	}
	return out;
}

/** What the author's draw(ctx, frame) callback receives each frame. A frame is
 *  a snapshot of the playhead — draw as a PURE function of it (not of `dt`) and
 *  scrubbing stays exact, the same discipline that makes the CSS shapes
 *  scrubbable. `dt` is provided for the ambient `loop` mode where determinism
 *  isn't required. */
export interface CanvasFrame {
	/** Logical drawing width in canvas px (ctx is pre-scaled for devicePixelRatio,
	 *  so draw in these units — same space as Block/Draw coordinates). */
	width: number;
	height: number;
	/** Elapsed clock time in SECONDS. Finite mode: 0..duration. Loop mode:
	 *  wall-clock seconds since start. Static mode: 0. */
	t: number;
	/** Normalised playhead 0..1. Finite: t/duration. Loop: (t/period) % 1.
	 *  Static: 0. */
	progress: number;
	/** Playhead as a PERCENT 0..100 (progress*100) — matches the stop `pct`
	 *  vocabulary, handy when hand-mapping ranges. */
	pct: number;
	/** Seconds since the previous frame (~0 while scrubbing/paused). For loop-mode
	 *  physics only; a scrub-safe draw ignores it. */
	dt: number;
	/** Interpolated keyframe tracks when `keyframes` is set, else an empty object. */
	values: Record<string, number>;
	/** Monotonic frame counter since mount. */
	frame: number;
}

/** What an interaction callback (onclick/ondblclick/onpointer*) receives. The
 *  pointer is mapped into the SAME canvas-px space your draw() uses — the map
 *  divides by the canvas's live on-screen size, so it's correct through the
 *  deck's scaling transform in every display mode. Hit-test `x`/`y` against what
 *  you drew, using `frame` for the playhead-dependent geometry, then mutate your
 *  own state and call `redraw()` to repaint (draw() is otherwise idle when the
 *  playhead isn't moving). */
export interface CanvasPointerEvent {
	/** Pointer position in canvas px — same coordinate space as draw() and the
	 *  Block/Draw geometry. */
	x: number;
	y: number;
	/** The playhead snapshot at the moment of the event (what's on screen now). */
	frame: CanvasFrame;
	/** The underlying DOM event (for modifiers, button, preventDefault, etc.). */
	originalEvent: MouseEvent;
	/** Force a repaint now — call after changing state your draw() reads. */
	redraw(): void;
}
