// Public exports for the Draw module (specs/DRAW-1.md).
//
// Shapes compose as markup inside <Draw> — one component per shape, each
// rendering bare SVG elements in canvas coordinates, so a shape's tag on the
// slide diffs line-by-line and Phase 3's per-shape Copy has a tag to copy.
// Raw SVG elements pass through <Draw>'s slot as an escape hatch.
export { default as Arc } from './Arc.svelte';
export { default as Canvas } from './Canvas.svelte';
export { default as Cursor } from './Cursor.svelte';
export { default as Curve } from './Curve.svelte';
export { default as Draw } from './Draw.svelte';
export { default as Line } from './Line.svelte';
export { default as Path } from './Path.svelte';
export { default as Polyline } from './Polyline.svelte';
export { default as Rect } from './Rect.svelte';
export { default as Ellipse } from './Ellipse.svelte';
export { default as Sprite } from './Sprite.svelte';
// canvasCore shares a `finite` helper name with drawCore, so re-export its
// public surface explicitly to avoid an ambiguous star-export.
export { clamp, easeFn, interpAt, trackKeys } from './canvasCore';
export type { CanvasFrame, CanvasPointerEvent, CanvasStop, Ease } from './canvasCore';
export * from './drawCore';
export * from './types';
