// Pure row-selection arithmetic for the presenter console's TOC jump menu — the
// twin of presenterKeyCore beside it, but for walking a filtered/unfiltered list
// of rows rather than deciding what a keystroke means.
//
// The menu is a list you can walk with ↑/↓ before committing with Enter. That is
// one piece of arithmetic (where does the cursor land?), kept here so it is
// unit-testable with plain numbers, independent of the DOM.

/** Move a selection cursor by `delta` over `count` rows, wrapping at both ends.
    `index` < 0 means "nothing selected yet": ↓ then lands on the first row and ↑
    on the last, which is what a freshly opened (or freshly searched) menu should
    do. An empty list has no selection, so the answer stays -1. Total: junk
    numbers in, a valid index (or -1) out. */
export function stepTocSelection(index: number, delta: number, count: number): number {
	const n = Number.isFinite(count) ? Math.floor(count) : 0;
	if (n <= 0) return -1;
	const d = Number.isFinite(delta) ? Math.floor(delta) : 0;
	const i = Number.isFinite(index) ? Math.floor(index) : -1;
	if (i < 0 || i >= n) return d < 0 ? n - 1 : 0;
	return (((i + d) % n) + n) % n;
}
