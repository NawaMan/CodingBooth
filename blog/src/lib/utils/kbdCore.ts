// The parsing behind <Kbd>: turning an author's shortcut string ("Mod+Shift+P",
// "Ctrl+K Ctrl+S") into the keycaps a slide should render, on the platform it is
// being shown to.
//
// Kept pure and DOM-free (drawCore / connectorCore / videoCore / columnsCore
// discipline) so the component is left with nothing but markup, and so the
// interesting cases — a lone `+`, a chord that is all separators, a key nobody
// has an alias for — are testable without a browser.
//
// Every function is total: bad input yields an empty list or the token as typed,
// never a throw. A slide must not collapse because someone wrote `keys="+++"`.

/** Which keyboard the audience is looking at. `mod` and the symbol set follow it. */
export type Platform = 'pc' | 'mac';

/** One chord (keys pressed together); a shortcut is a sequence of them. */
export type Chord = string[];

/** What a `Kbd` renders: `[['Ctrl','K'], ['Ctrl','S']]` for "Ctrl+K Ctrl+S". */
export type Chords = Chord[];

/**
 * Aliases → the canonical key id used by the label maps below.
 *
 * Lowercased on lookup, so `CTRL`, `Ctrl` and `ctrl` are one key. `mod` is the
 * portable modifier — the whole reason this map exists — and resolves per
 * platform in `capLabel`; everything else names a real, fixed key.
 */
const ALIASES: Record<string, string> = {
	mod: 'mod',
	cmd: 'cmd', command: 'cmd', meta: 'cmd', '⌘': 'cmd',
	ctrl: 'ctrl', control: 'ctrl', '⌃': 'ctrl',
	alt: 'alt', opt: 'alt', option: 'alt', '⌥': 'alt',
	shift: 'shift', '⇧': 'shift',
	win: 'win', windows: 'win', super: 'win',
	enter: 'enter', return: 'enter',
	esc: 'esc', escape: 'esc',
	tab: 'tab',
	space: 'space', spacebar: 'space',
	backspace: 'backspace', bksp: 'backspace',
	del: 'delete', delete: 'delete',
	ins: 'insert', insert: 'insert',
	up: 'up', arrowup: 'up',
	down: 'down', arrowdown: 'down',
	left: 'left', arrowleft: 'left',
	right: 'right', arrowright: 'right',
	pgup: 'pageup', pageup: 'pageup',
	pgdn: 'pagedown', pagedown: 'pagedown',
	home: 'home',
	end: 'end',
};

/**
 * The spelled-out labels — what a PC keyboard prints on its caps, and what a Mac
 * shows when `symbols` is off.
 *
 * Arrows are absent on purpose: `↑` is not shorthand for the Up key, it is the
 * legend on the cap. They live in `ARROWS` and are used on every platform.
 */
const LABELS: Record<string, string> = {
	cmd: 'Cmd',
	ctrl: 'Ctrl',
	alt: 'Alt',
	shift: 'Shift',
	win: 'Win',
	enter: 'Enter',
	esc: 'Esc',
	tab: 'Tab',
	space: 'Space',
	backspace: 'Backspace',
	delete: 'Delete',
	insert: 'Insert',
	pageup: 'Page Up',
	pagedown: 'Page Down',
	home: 'Home',
	end: 'End',
};

/** Legends every keyboard agrees on, symbols or not. */
const ARROWS: Record<string, string> = {
	up: '↑',
	down: '↓',
	left: '←',
	right: '→',
};

/**
 * The Mac symbol set. A Mac shortcut is written in glyphs (`⇧⌘P`), never words,
 * which is exactly why `symbols` defaults on and why the chord joiner disappears
 * with it: `⇧+⌘+P` is nobody's idea of a Mac shortcut.
 *
 * `win` is deliberately missing — there is no Windows key to draw on a Mac, so it
 * falls through to its label rather than being mapped onto `⌘`.
 */
const MAC_SYMBOLS: Record<string, string> = {
	cmd: '⌘',
	ctrl: '⌃',
	alt: '⌥',
	shift: '⇧',
	enter: '↩',
	esc: '⎋',
	tab: '⇥',
	space: '␣',
	backspace: '⌫',
	delete: '⌦',
	pageup: '⇞',
	pagedown: '⇟',
	home: '↖',
	end: '↘',
};

/**
 * One chord's tokens, split on `+`.
 *
 * `+` is both the separator and a key, so the split cannot be a `String.split`:
 * a `+` with nothing to its left is the *plus key* (`Ctrl++` → Ctrl and Plus),
 * and a run of them collapses to one, so `++` is a plus cap rather than two.
 * A trailing `+` has already done its job as a separator and adds nothing.
 */
function tokenizeChord(chord: string): string[] {
	const tokens: string[] = [];
	let buffer = '';
	for (const ch of chord) {
		if (ch !== '+') {
			buffer += ch;
			continue;
		}
		if (buffer) {
			tokens.push(buffer);
			buffer = '';
		} else if (tokens[tokens.length - 1] !== '+') {
			tokens.push('+');
		}
	}
	if (buffer) tokens.push(buffer);
	return tokens;
}

/**
 * The legend for one token, on one platform.
 *
 * An unknown token is passed through as typed (`F5`, `/`, `Æ`) — a shortcut may
 * name any key, and inventing a fallback label would only hide the author's typo.
 * A single character is uppercased, because a keycap is engraved `K`, not `k`,
 * whatever the author wrote.
 */
export function capLabel(token: unknown, platform: Platform = 'pc', symbols: boolean = true): string {
	if (typeof token !== 'string') return '';
	const text = token.trim();
	if (!text) return '';

	let key = ALIASES[text.toLowerCase()];
	if (key === 'mod') key = platform === 'mac' ? 'cmd' : 'ctrl';

	if (!key) return [...text].length === 1 ? text.toUpperCase() : text;
	if (ARROWS[key]) return ARROWS[key];
	if (platform === 'mac' && symbols && MAC_SYMBOLS[key]) return MAC_SYMBOLS[key];
	return LABELS[key] ?? text;
}

/**
 * An author's `keys` string as the caps to render.
 *
 * Whitespace separates chords (a *sequence*: press, release, press again), `+`
 * separates the keys within one. Anything that survives neither — `''`, `'  '`,
 * a non-string — yields no chords at all, so a `Kbd` with a junk spec renders
 * nothing rather than an empty keycap.
 */
export function parseKeys(spec: unknown, platform: Platform = 'pc', symbols: boolean = true): Chords {
	if (typeof spec !== 'string') return [];
	return spec
		.trim()
		.split(/\s+/)
		.filter(Boolean)
		.map((chord) => tokenizeChord(chord).map((token) => capLabel(token, platform, symbols)).filter(Boolean))
		.filter((chord) => chord.length > 0);
}

/**
 * What goes between the keys of one chord.
 *
 * A PC shortcut is written `Ctrl+Shift+P`; a Mac one is written `⇧⌘P`, with the
 * glyphs run together. So the joiner is empty exactly when the Mac symbols are in
 * play — turn `symbols` off and the `+` comes back, because `Shift Cmd P` would
 * not read as a chord.
 */
export function chordJoiner(platform: Platform = 'pc', symbols: boolean = true): string {
	return platform === 'mac' && symbols ? '' : '+';
}

/** Anything that quacks like `navigator`. Passed in, never read off a global, so
    this stays pure — and so a test can be a Mac without being one. */
export interface PlatformHints {
	platform?: string;
	userAgent?: string;
	userAgentData?: { platform?: string };
}

/**
 * Which keyboard the *viewer* has, for `platform="auto"`.
 *
 * Client-only by nature: there is no navigator during SSR, and `undefined` hints
 * yield `'pc'` — the deterministic fallback a prerendered page and a Text
 * artifact both need. Checks `userAgentData` first (`navigator.platform` is
 * deprecated), then falls back to the UA string, which still says `Macintosh`.
 */
export function detectPlatform(hints?: PlatformHints | null): Platform {
	if (!hints) return 'pc';
	const text = hints.userAgentData?.platform || hints.platform || hints.userAgent || '';
	return /mac|iphone|ipad|ipod/i.test(text) ? 'mac' : 'pc';
}
