import { browser } from '$app/environment';
import { persisted } from './persisted';
import { numberCodec, type Codec } from '$lib/utils/stateCore';

// Display mode for a Presentation canvas:
//   - FITTED: scale the slide to fit the window, preserving aspect (present mode).
//   - SCALED: show the slide at an exact factor (1 = 100% = native canvas px),
//     centred and pannable when it overflows the window (inspect mode).
// `displayFactor` only matters in SCALED; both are persisted to localStorage.
export type DisplayMode = 'FITTED' | 'SCALED';

/** Zoom bounds for SCALED mode (1 = 100% = native canvas pixels). */
export const MIN_FACTOR = 0.1;
export const MAX_FACTOR = 4;
export const clampFactor = (f: number): number => Math.min(MAX_FACTOR, Math.max(MIN_FACTOR, f));

const MODE_KEY = 'displayMode';
const FACTOR_KEY = 'displayFactor';
// Old boolean store: `true` was fit-to-window (now FITTED), `false` was the native
// "FIXED" view (now SCALED @ 100%). Migrate it so existing visitors keep their choice.
const LEGACY_KEY = 'scaleMode';

/** Only the two strings we write are a mode. Anything else — a key from a future version,
    a half-written value — is `null`, which falls through to the initial value below, and
    that is where the legacy migration lives. */
const modeCodec: Codec<DisplayMode> = {
	read: (raw: string) => (raw === 'FITTED' || raw === 'SCALED' ? raw : null),
	write: (value: DisplayMode) => value
};

/** The legacy `scaleMode` boolean, read as a mode.

    This is the store's INITIAL value rather than part of its codec, and that is not a
    workaround — it is the honest shape of the thing. A `Codec` is a pure translation of
    ONE key's string; the migration reads a DIFFERENT key, and it answers a different
    question: "what should this deck believe when it has no opinion of its own stored?"
    Which is exactly what an initial value is.

    It also lands the precedence for free: `persisted()` only consults `initial` when the
    real key is absent or unreadable, so a live `displayMode` always outranks the legacy
    one, and a garbage `displayMode` still falls through to it. */
function legacyMode(): DisplayMode {
	if (!browser) return 'FITTED';
	try {
		return localStorage.getItem(LEGACY_KEY) === 'false' ? 'SCALED' : 'FITTED';
	} catch {
		return 'FITTED';
	}
}

/** A zoom factor: finite, positive, and inside the zoom bounds.

    The positive check is deliberately NOT left to `numberCodec`'s clamp. A stored `0` or
    `-3` is corruption, not a zoom level, and clamping it would seat the deck at the 10%
    floor — which looks broken. Falling back to 1 looks merely fresh, so a bad value resets
    rather than clamps, while a merely out-of-range one (a hand-edited `4000`) still clamps. */
const finite = numberCodec();
const factorCodec: Codec<number> = {
	read(raw: string): number | null {
		const n = finite.read(raw);
		return n !== null && n > 0 ? clampFactor(n) : null;
	},
	write: (value: number) => finite.write(value)
};

// `sync: false` on both: the presenter console is a second window onto the same deck, so
// cross-tab sync would mean the speaker zooming in to inspect a slide also zooms the
// AUDIENCE's screen. The two windows keep their own view of the same deck.
export const displayMode = persisted<DisplayMode>(MODE_KEY, legacyMode(), {
	codec: modeCodec,
	sync: false
});
export const displayFactor = persisted<number>(FACTOR_KEY, 1, {
	codec: factorCodec,
	sync: false
});
