// Pure maths for ADJUST copy/paste — where a pasted Block lands and what it is
// called. Browser-free so it unit-tests without a DOM (tests/pasteCore.test.ts).

/** How far each successive paste steps from the copied Block, in canvas px. */
export const PASTE_OFFSET = 20;

export interface Box {
	x: number;
	y: number;
	width: number;
	height: number;
}

/** The box for the `n`th paste (1-based) of `from`: stepped down-right by
    PASTE_OFFSET per paste, so repeated pastes cascade instead of stacking
    exactly on top of each other. With `clamp`, the box is kept inside the
    canvas (a Block with bounds="canvas" could not be dragged there anyway). */
export function pasteBox(from: Box, n: number, canvas: { width: number; height: number } | null): Box {
	let x = from.x + PASTE_OFFSET * n;
	let y = from.y + PASTE_OFFSET * n;
	if (canvas) {
		x = Math.max(0, Math.min(x, canvas.width - from.width));
		y = Math.max(0, Math.min(y, canvas.height - from.height));
	}
	return { x: Math.round(x), y: Math.round(y), width: from.width, height: from.height };
}

/** The first free `<base>-N` (N from 2) not in `taken`. An unnamed Block's copy
    stays unnamed — '' in, '' out. Names must be unique on a slide: SAVE and
    every Connector find a Block by name. */
export function nextCopyName(base: string, taken: Iterable<string>): string {
	if (!base) return '';
	const used = new Set(taken);
	for (let n = 2; ; n++) {
		const candidate = `${base}-${n}`;
		if (!used.has(candidate)) return candidate;
	}
}
