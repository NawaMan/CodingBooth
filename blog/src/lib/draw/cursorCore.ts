// Pure geometry/timing for <Cursor> — a fake pointer that glides between
// resolved canvas points and flashes a click ripple. No component imports,
// no DOM, no stores: everything here is independently unit-testable
// (tests/cursorCore.test.ts), the same discipline drawCore.ts/connectorCore.ts
// follow for the shapes. Cursor.svelte owns resolving `path` entries against
// blockAnchors (Connector's job); this module only ever sees already-resolved
// points, and stays NaN-safe even so — garbage in still yields a drawable
// (or empty) result, never `NaNpx`.

import { finite } from './drawCore';
import type { Point, SpriteStop } from './types';

/** A Block `name` (resolved live through blockAnchors, the same registry
 *  Connector/Spotlight read) or a literal canvas point. Shared by both
 *  Cursor's `path` waypoint list and its `script` command list. */
export type CursorAt = string | Point;

/** One already-resolved waypoint: a canvas-px centre point, plus whether the
 *  pointer should flash a ripple on arrival. `size`, when set, overrides the
 *  glyph's box just for this waypoint (falls back to Cursor's own `size`
 *  prop otherwise). */
export interface CursorTarget {
	x: number;
	y: number;
	click: boolean;
	size?: number;
}

/** A ripple's screen position, radius, and when (seconds into the whole
 *  timeline, hold included) its animation should start. */
export interface CursorRipple {
	x: number;
	y: number;
	r: number;
	delaySec: number;
}

/**
 * Build the Sprite `stops` for a cursor's flight: one per target, evenly
 * spaced across 0–100%, box top-left = centre − size/2 (Sprite's own
 * path-mode convention). A target's own `size` overrides the shared
 * `size` for that stop. Degenerate-safe: no targets → `[]` (Cursor renders
 * nothing); one target → a single static (non-animating) stop; garbage
 * coordinates/size coerce finite rather than propagating NaN into the
 * generated CSS.
 */
export function cursorSpriteStops(targets: CursorTarget[], size: number): SpriteStop[] {
	const n = targets.length;
	if (n === 0) return [];
	const box = Math.max(1, finite(size, 40));
	const last = n - 1;
	return targets.map((t, i) => {
		const s = Math.max(1, finite(t.size ?? NaN, box));
		return {
			pct: last === 0 ? 0 : Math.round((i / last) * 10000) / 100,
			x: Math.round(finite(t.x) - s / 2),
			y: Math.round(finite(t.y) - s / 2),
			w: s,
			h: s,
			rot: 0
		};
	});
}

/**
 * Ripple checkpoints for every target marked `click`. A target's flight
 * arrives at `delay + animate·(pct/100)` seconds — the same real-time offset
 * Sprite's own generated `animation: … <animate>s <ease> <delay>s both;`
 * places that stop at — so a ripple always flashes exactly when the glyph
 * gets there. With a single target (no flight) the pointer is already
 * there, so the ripple fires at `delay`. Its radius scales with whatever
 * size was active AT that waypoint (its own override, or the shared `size`).
 */
export function cursorRipples(
	targets: CursorTarget[],
	delay: number,
	animate: number,
	size: number
): CursorRipple[] {
	const n = targets.length;
	if (n === 0) return [];
	const d = Math.max(0, finite(delay, 0));
	const a = n >= 2 ? Math.max(0, finite(animate, 0)) : 0;
	const last = Math.max(1, n - 1);
	const out: CursorRipple[] = [];
	targets.forEach((t, i) => {
		if (!t.click) return;
		const pct = n === 1 ? 0 : i / last;
		out.push({
			x: finite(t.x),
			y: finite(t.y),
			r: cursorRippleRadius(finite(t.size ?? NaN, size)),
			delaySec: d + a * pct
		});
	});
	return out;
}

/** Ripple ring radius (canvas px) for a given glyph box size — scales with
 *  it so a bigger cursor gets a proportionally bigger click flash. */
export function cursorRippleRadius(size: number): number {
	return Math.max(4, finite(size, 40) * 0.55);
}
