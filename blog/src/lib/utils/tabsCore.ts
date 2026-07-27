// tabsCore — the pure, total arithmetic behind <Tabs> / <Tab>.
//
// Same discipline as drawCore / videoCore / columnsCore: every function is total,
// so a junk index, an empty list, a NaN `start` or a strip of nothing but disabled
// tabs all yield a sane index (never a throw, never an out-of-range read). The
// component stays declarative and the logic is unit-tested without a DOM.

export const TABS_CONTEXT = 'tabs';

/** What a <Tab> registers with its <Tabs> so the strip can draw the button. */
export type TabMeta = { label: string; icon?: string; disabled?: boolean };

/** Clamp an index into [0, n-1]. Non-finite input, or an empty list, → 0. */
export function clampIndex(i: number, n: number): number {
	if (!Number.isFinite(i) || n <= 0) return 0;
	const k = Math.floor(i);
	if (k < 0) return 0;
	if (k > n - 1) return n - 1;
	return k;
}

/** The first enabled tab's index; 0 when the list is empty or all disabled. */
export function firstEnabled(tabs: TabMeta[]): number {
	for (let i = 0; i < tabs.length; i++) if (!tabs[i]?.disabled) return i;
	return 0;
}

/** The last enabled tab's index; falls back to firstEnabled (0) when all disabled. */
export function lastEnabled(tabs: TabMeta[]): number {
	for (let i = tabs.length - 1; i >= 0; i--) if (!tabs[i]?.disabled) return i;
	return firstEnabled(tabs);
}

/** The initial selection: `start` clamped into range, then nudged to the first
    enabled tab if it landed on a disabled one — an author's `start` can't strand
    the widget on a tab that can never be shown. */
export function initialIndex(tabs: TabMeta[], start: number): number {
	const i = clampIndex(start, tabs.length);
	if (tabs[i] && !tabs[i].disabled) return i;
	return firstEnabled(tabs);
}

/** Step from `from` by `dir` (+1 forward / -1 back), skipping disabled tabs and
    wrapping past the ends — the roving-tab keyboard move. Scans at most one full
    lap, so a list with a single enabled tab (or none) simply returns where it was
    rather than looping forever. */
export function stepEnabled(tabs: TabMeta[], from: number, dir: number): number {
	const n = tabs.length;
	if (n === 0) return 0;
	const step = dir >= 0 ? 1 : -1;
	let i = clampIndex(from, n);
	for (let count = 0; count < n; count++) {
		i = (((i + step) % n) + n) % n;
		if (!tabs[i]?.disabled) return i;
	}
	return clampIndex(from, n);
}

/** Map the `align` prop to a strip-justification class token; unknown → 'start'
    (the ContentPage / Timeline discipline: never emit a class that matches nothing). */
export function alignClass(align: string): 'start' | 'center' | 'end' | 'stretch' {
	return align === 'center' || align === 'end' || align === 'stretch' ? align : 'start';
}
