import { writable } from 'svelte/store';
import { browser } from '$app/environment';

// Display mode for a Presentation canvas:
//   - FITTED: scale the slide to fit the window, preserving aspect (present mode).
//   - SCALED: show the slide at an exact factor (1 = 100% = native canvas px),
//     centred and pannable when it overflows the window (inspect mode).
// `displayFactor` only matters in SCALED; both are persisted to localStorage.
export type DisplayMode = 'FITTED' | 'SCALED';

/** Zoom bounds for SCALED mode (1 = 100% = native canvas pixels). */
export const MIN_FACTOR = 0.1;
export const MAX_FACTOR = 4;
export const clampFactor = (f: number): number =>
    Math.min(MAX_FACTOR, Math.max(MIN_FACTOR, f));

const MODE_KEY   = 'displayMode';
const FACTOR_KEY = 'displayFactor';
// Old boolean store: `true` was fit-to-window (now FITTED), `false` was the native
// "FIXED" view (now SCALED @ 100%). Migrate it so existing visitors keep their choice.
const LEGACY_KEY = 'scaleMode';

function initialMode(): DisplayMode {
    if (!browser) return 'FITTED';
    const stored = localStorage.getItem(MODE_KEY);
    if (stored === 'FITTED' || stored === 'SCALED') return stored;
    return localStorage.getItem(LEGACY_KEY) === 'false' ? 'SCALED' : 'FITTED';
}

function initialFactor(): number {
    if (!browser) return 1;
    const f = parseFloat(localStorage.getItem(FACTOR_KEY) ?? '');
    return Number.isFinite(f) && f > 0 ? clampFactor(f) : 1;
}

export const displayMode   = writable<DisplayMode>(initialMode());
export const displayFactor = writable<number>(initialFactor());

if (browser) {
    displayMode.subscribe(v => localStorage.setItem(MODE_KEY, v));
    displayFactor.subscribe(v => localStorage.setItem(FACTOR_KEY, String(v)));
}
