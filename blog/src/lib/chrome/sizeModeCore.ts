// Pure helpers for the DISPLAY / zoom menu (SizeMode): the list of choices a
// keyboard user walks with ↑/↓, and which row is "current" for a given mode.
//
// Total: empty lists, out-of-range indices, and garbage factors never throw.

/** One selectable row in the zoom menu (not a SCALE/RESOLUTION header, not CUSTOM). */
export type SizeMenuChoice =
	| { id: 'fitted'; kind: 'fitted' }
	| { id: string; kind: 'factor'; factor: number };

/** Scale presets (as factors of the canvas). Shared with SizeMode's visible list. */
export const SCALE_PRESETS = [2, 1.5, 1.25, 1, 0.75, 0.5, 0.25] as const;

/** Well-known 16:9 output resolutions as factors of 1920×1080. */
export const RES_PRESETS = [
	{ factor: 1600 / 1920, name: 'HD+' },
	{ factor: 1280 / 1920, name: '720p' },
	{ factor: 960 / 1920, name: 'qHD' },
	{ factor: 854 / 1920, name: '480p' },
	{ factor: 640 / 1920, name: 'nHD' }
] as const;

const NEAR = 0.005;

export function nearFactor(a: number, b: number): boolean {
	return Math.abs(a - b) < NEAR;
}

/**
 * Selectable zoom rows for a canvas. Resolution group is only meaningful on a
 * standard 1920×1080 landscape deck (same gate SizeMode uses).
 */
export function sizeMenuChoices(includeResolutions: boolean): SizeMenuChoice[] {
	const items: SizeMenuChoice[] = [{ id: 'fitted', kind: 'fitted' }];
	for (const f of SCALE_PRESETS) {
		items.push({ id: `s-${f}`, kind: 'factor', factor: f });
	}
	if (includeResolutions) {
		for (const r of RES_PRESETS) {
			items.push({ id: `r-${r.name}`, kind: 'factor', factor: r.factor });
		}
	}
	return items;
}

/**
 * Index of the row that matches the live display state, or 0 (FITTED) when none.
 */
export function currentChoiceIndex(
	choices: SizeMenuChoice[],
	isFitted: boolean,
	factor: number
): number {
	if (!choices.length) return 0;
	if (isFitted) {
		const i = choices.findIndex((c) => c.kind === 'fitted');
		return i >= 0 ? i : 0;
	}
	const i = choices.findIndex((c) => c.kind === 'factor' && nearFactor(c.factor, factor));
	return i >= 0 ? i : 0;
}

/** Wrap around the choice list (↑ from first → last, ↓ from last → first). */
export function stepChoiceIndex(index: number, delta: number, length: number): number {
	if (length <= 0) return 0;
	const i = Number.isFinite(index) ? Math.trunc(index) : 0;
	const d = Number.isFinite(delta) ? Math.trunc(delta) : 0;
	return ((i + d) % length + length) % length;
}
