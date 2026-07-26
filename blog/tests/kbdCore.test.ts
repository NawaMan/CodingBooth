// The parsing behind <Kbd>, tested without a browser. Every function is total:
// the interesting cases are the bad ones (a lone `+`, a chord of nothing but
// separators, a key nobody has an alias for), because a slide must not collapse
// over any of them.
import { describe, expect, it } from 'vitest';
import { capLabel, chordJoiner, detectPlatform, parseKeys } from '../src/lib/utils/kbdCore';

describe('capLabel', () => {
	it('spells modifiers out on a PC', () => {
		expect(capLabel('ctrl')).toBe('Ctrl');
		expect(capLabel('shift')).toBe('Shift');
		expect(capLabel('alt')).toBe('Alt');
		expect(capLabel('cmd')).toBe('Cmd');
	});

	it('draws them as glyphs on a Mac, and spells them out with symbols off', () => {
		expect(capLabel('cmd', 'mac')).toBe('⌘');
		expect(capLabel('shift', 'mac')).toBe('⇧');
		expect(capLabel('alt', 'mac')).toBe('⌥');
		expect(capLabel('ctrl', 'mac')).toBe('⌃');
		expect(capLabel('cmd', 'mac', false)).toBe('Cmd');
		expect(capLabel('shift', 'mac', false)).toBe('Shift');
	});

	it('`mod` is the portable modifier: Ctrl on a PC, ⌘ on a Mac', () => {
		expect(capLabel('mod', 'pc')).toBe('Ctrl');
		expect(capLabel('mod', 'mac')).toBe('⌘');
		expect(capLabel('mod', 'mac', false)).toBe('Cmd');
	});

	it('resolves aliases case-insensitively', () => {
		for (const alias of ['ctrl', 'Ctrl', 'CTRL', 'control', 'Control']) {
			expect(capLabel(alias)).toBe('Ctrl');
		}
		expect(capLabel('Option', 'mac')).toBe('⌥');
		expect(capLabel('Return')).toBe('Enter');
		expect(capLabel('PgUp')).toBe('Page Up');
		expect(capLabel('Del', 'mac')).toBe('⌦');
	});

	it('arrows are glyphs on every platform — ↑ is the legend, not shorthand', () => {
		for (const platform of ['pc', 'mac'] as const) {
			for (const symbols of [true, false]) {
				expect(capLabel('up', platform, symbols)).toBe('↑');
				expect(capLabel('ArrowLeft', platform, symbols)).toBe('←');
			}
		}
	});

	it('there is no Windows key on a Mac, so `win` never becomes ⌘', () => {
		expect(capLabel('win', 'mac')).toBe('Win');
		expect(capLabel('super', 'pc')).toBe('Win');
	});

	it('uppercases a single character, and passes anything else through as typed', () => {
		expect(capLabel('k')).toBe('K');
		expect(capLabel('/')).toBe('/');
		expect(capLabel('F5')).toBe('F5');
		expect(capLabel('Fn')).toBe('Fn');
	});

	it('is total: junk yields the empty string, never a throw', () => {
		expect(capLabel('')).toBe('');
		expect(capLabel('   ')).toBe('');
		expect(capLabel(undefined)).toBe('');
		expect(capLabel(null)).toBe('');
		expect(capLabel(42)).toBe('');
	});
});

describe('parseKeys', () => {
	it('splits keys on `+` and chords on whitespace', () => {
		expect(parseKeys('Ctrl+K')).toEqual([['Ctrl', 'K']]);
		expect(parseKeys('Ctrl+K Ctrl+S')).toEqual([
			['Ctrl', 'K'],
			['Ctrl', 'S'],
		]);
		expect(parseKeys('  Ctrl+Shift+P   Enter  ')).toEqual([['Ctrl', 'Shift', 'P'], ['Enter']]);
	});

	it('follows the platform through to every cap', () => {
		expect(parseKeys('Mod+Shift+P', 'mac')).toEqual([['⌘', '⇧', 'P']]);
		expect(parseKeys('Mod+Shift+P', 'mac', false)).toEqual([['Cmd', 'Shift', 'P']]);
		expect(parseKeys('Mod+Shift+P', 'pc')).toEqual([['Ctrl', 'Shift', 'P']]);
	});

	it('`+` is a key too: a `+` with nothing to its left is the plus cap', () => {
		expect(parseKeys('Ctrl++')).toEqual([['Ctrl', '+']]);
		expect(parseKeys('+')).toEqual([['+']]);
		expect(parseKeys('Mod++ Mod+-', 'mac')).toEqual([
			['⌘', '+'],
			['⌘', '-'],
		]);
	});

	it('collapses a run of separators, and ignores a trailing one', () => {
		// `++` is the plus key, not two of them; `Ctrl+` already used its separator.
		expect(parseKeys('++')).toEqual([['+']]);
		expect(parseKeys('Ctrl+++')).toEqual([['Ctrl', '+']]);
		expect(parseKeys('Ctrl+')).toEqual([['Ctrl']]);
	});

	it('is total: junk yields no chords, so a Kbd renders nothing rather than a blank cap', () => {
		expect(parseKeys('')).toEqual([]);
		expect(parseKeys('    ')).toEqual([]);
		expect(parseKeys(undefined)).toEqual([]);
		expect(parseKeys(null)).toEqual([]);
		expect(parseKeys(['Ctrl'])).toEqual([]);
	});
});

describe('chordJoiner', () => {
	it('is `+` everywhere except under the Mac glyphs, where ⇧+⌘+P reads wrong', () => {
		expect(chordJoiner('pc')).toBe('+');
		expect(chordJoiner('pc', false)).toBe('+');
		expect(chordJoiner('mac')).toBe('');
		expect(chordJoiner('mac', false)).toBe('+');
	});
});

describe('detectPlatform', () => {
	it('prefers userAgentData, which is what navigator.platform was deprecated for', () => {
		expect(detectPlatform({ userAgentData: { platform: 'macOS' }, platform: 'Win32' })).toBe('mac');
		expect(detectPlatform({ userAgentData: { platform: 'Windows' }, userAgent: 'Macintosh' })).toBe('pc');
	});

	it('falls back to navigator.platform, then to the UA string', () => {
		expect(detectPlatform({ platform: 'MacIntel' })).toBe('mac');
		expect(detectPlatform({ userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)' })).toBe('mac');
		expect(detectPlatform({ userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0)' })).toBe('mac');
		expect(detectPlatform({ userAgent: 'Mozilla/5.0 (X11; Linux x86_64)' })).toBe('pc');
	});

	it('no navigator (SSR) is `pc` — the deterministic fallback a prerender needs', () => {
		expect(detectPlatform(undefined)).toBe('pc');
		expect(detectPlatform(null)).toBe('pc');
		expect(detectPlatform({})).toBe('pc');
	});
});
