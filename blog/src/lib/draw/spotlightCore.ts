// Pure geometry for <Spotlight> — turning a named Block's box into the padded
// rectangle a spotlight rings and cuts out of its dim scrim.
//
// No component imports, no DOM, no stores: independently unit-testable
// (tests/spotlightCore.test.ts), the same discipline connectorCore.ts / drawCore.ts
// follow. Everything is NaN-safe (finite() from drawCore) and degenerate-safe: a
// garbage box, a zero/negative pad, or a box that spills past the canvas all yield
// a drawable rectangle rather than `NaNpx` or an inside-out rect — so a slide can
// never blow up over a typo'd name resolving to a half-registered box.

import { finite } from './drawCore';
import type { AnchorRect } from '$lib/stores/blockAnchors';

/** The rectangle the spotlight actually paints: the target box grown by `pad` on
    every side and a corner `radius`, clamped so it stays on the canvas. */
export interface SpotlightRect {
	x: number;
	y: number;
	width: number;
	height: number;
	/** Corner radius, never larger than half the shorter side (so it can't invert). */
	radius: number;
}

/**
 * Grow `box` by `pad` on every side, round its corners by `radius`, and clamp the
 * result to `[0, canvasW] × [0, canvasH]`. A negative/NaN pad is treated as 0; a
 * box with non-finite fields collapses to a zero-size rect at the origin rather
 * than producing NaN. The radius is capped at half the shorter side so a small box
 * with a large radius stays a rectangle, never an inside-out arc.
 */
export function spotlightRect(
	box: AnchorRect,
	pad: number,
	radius: number,
	canvasW: number,
	canvasH: number
): SpotlightRect {
	const p = Math.max(0, finite(pad));
	const cw = Math.max(0, finite(canvasW));
	const ch = Math.max(0, finite(canvasH));

	// The padded box, before clamping.
	const bx = finite(box.x);
	const by = finite(box.y);
	const bw = Math.max(0, finite(box.width));
	const bh = Math.max(0, finite(box.height));

	let left = bx - p;
	let top = by - p;
	let right = bx + bw + p;
	let bottom = by + bh + p;

	// Clamp each edge onto the canvas. Clamp left/top BEFORE right/bottom so a box
	// entirely off one side collapses to a zero-width sliver at the border rather
	// than a negative width.
	left = clamp(left, 0, cw);
	top = clamp(top, 0, ch);
	right = clamp(right, left, cw);
	bottom = clamp(bottom, top, ch);

	const width = right - left;
	const height = bottom - top;
	const r = Math.min(Math.max(0, finite(radius)), width / 2, height / 2);

	return { x: left, y: top, width, height, radius: r };
}

function clamp(v: number, lo: number, hi: number): number {
	if (hi < lo) return lo; // canvas smaller than the offset — degenerate, pin to lo
	return v < lo ? lo : v > hi ? hi : v;
}
