// The EDIT window's file-tree width (pure).
//
// The divider between the tree and the editor drags. The width is remembered in
// localStorage (stores/treeWidth.ts), so every later EDIT window opens with it;
// the window it is shown in may be narrower than the one it was set in, so the
// stored width is clamped again against the window on every render.

/** Width of a fresh window's tree, and what a double-click on the divider resets to. */
export const TREE_DEFAULT_WIDTH = 240;
/** The tree never gets narrower than this. */
export const TREE_MIN_WIDTH = 140;
/** The editor keeps at least this much of the window. */
export const EDITOR_MIN_WIDTH = 300;

/** The tree width to show for a wanted `width` in a window `windowWidth` wide.
    The editor's minimum gives way before the tree's: a window too narrow for both
    still shows TREE_MIN_WIDTH of tree. Junk (NaN, Infinity) reads as the default. */
export function clampTreeWidth(width: number, windowWidth: number): number {
	const want = Number.isFinite(width) ? width : TREE_DEFAULT_WIDTH;
	const max = Number.isFinite(windowWidth) ? windowWidth - EDITOR_MIN_WIDTH : Infinity;
	return Math.round(Math.max(TREE_MIN_WIDTH, Math.min(want, max)));
}
