// Pure timing/placement for <Toast> — the transient on-slide banner.
//
// No component imports, no DOM, no stores: independently unit-testable
// (tests/toastCore.test.ts), the same discipline drawCore.ts / spotlightCore.ts
// follow. Everything is total and NaN-safe: junk timing falls back to the default
// dwell rather than scheduling a `setTimeout(NaN)` (which fires immediately), and an
// unknown placement resolves to the default rather than emitting a class that matches
// no CSS. The DIM/geometry of a highlighting toast is spotlightCore's job — this file
// owns only the numbers the banner itself needs.

import { finite } from '$lib/draw/drawCore';

/** Where the banner sits over the canvas. */
export type ToastPlacement = 'top' | 'center' | 'bottom';

const PLACEMENTS = new Set<ToastPlacement>(['top', 'center', 'bottom']);

/**
 * Resolve an author's `placement` to a known value. An unknown/omitted value falls
 * back to `bottom` (the least intrusive spot — a toast overlays the live slide, and
 * the bottom edge is where a status line is expected), rather than stamping a class
 * the stylesheet never matches. Mirrors ContentPage's align rule.
 */
export function toastPlacement(p: unknown): ToastPlacement {
	return PLACEMENTS.has(p as ToastPlacement) ? (p as ToastPlacement) : 'bottom';
}

/**
 * How long the toast stays up before dismissing ITSELF, in ms.
 *
 *  - a finite, positive number is used as-is (it is the dwell);
 *  - `0` or a negative number means STICKY — return 0, the caller reads that as
 *    "never auto-dismiss, stay until closed";
 *  - anything non-finite (undefined, NaN, Infinity, a string) falls back to
 *    `fallback` — a garbage duration must never schedule `setTimeout(NaN)`, which
 *    browsers treat as 0 and would flash the toast away on the same frame it appeared.
 */
export function autoDismissMs(duration: unknown, fallback = 2600): number {
	const d = finite(duration as number, NaN);
	if (!Number.isFinite(d)) return Math.max(0, finite(fallback, 0));
	return d <= 0 ? 0 : d;
}

/** Clamp a 0–1 opacity, with a finite fallback for junk. Used for the dim scrim. */
export function clampDim(dim: unknown, fallback = 0.4): number {
	const d = finite(dim as number, NaN);
	if (!Number.isFinite(d)) return clampDim(fallback, 0);
	return Math.min(1, Math.max(0, d));
}
