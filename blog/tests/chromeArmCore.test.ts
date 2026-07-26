import { describe, expect, it } from 'vitest';
import {
	chromeKeyIntent,
	moreMenuKeyIntent,
	isAdjustSaveChord,
	isChromeTypingTarget
} from '../src/lib/chrome/chromeArmCore';

function key(
	partial: Partial<KeyboardEvent> & { key: string; code?: string }
): KeyboardEvent {
	return {
		key: partial.key,
		code: partial.code ?? '',
		altKey: !!partial.altKey,
		ctrlKey: !!partial.ctrlKey,
		metaKey: !!partial.metaKey,
		shiftKey: !!partial.shiftKey,
		defaultPrevented: !!partial.defaultPrevented,
		target: partial.target ?? null
	} as KeyboardEvent;
}

describe('isChromeTypingTarget', () => {
	it('protects fields, not buttons', () => {
		expect(isChromeTypingTarget({ tagName: 'INPUT' } as unknown as EventTarget)).toBe(true);
		expect(isChromeTypingTarget({ tagName: 'BUTTON' } as unknown as EventTarget)).toBe(false);
		expect(isChromeTypingTarget(null)).toBe(false);
	});
});

describe('chromeKeyIntent', () => {
	it('Alt+. arms (by code or key)', () => {
		expect(chromeKeyIntent(key({ key: '.', code: 'Period', altKey: true }), false)).toBe('arm');
		expect(chromeKeyIntent(key({ key: 'Dead', code: 'Period', altKey: true }), false)).toBe(
			'arm'
		);
	});

	it('does not arm with Ctrl/Meta+Alt+.', () => {
		expect(
			chromeKeyIntent(key({ key: '.', code: 'Period', altKey: true, ctrlKey: true }), false)
		).toBe('ignore');
	});

	it('ignores letter mnemonics until armed', () => {
		expect(chromeKeyIntent(key({ key: 'a' }), false)).toBe('ignore');
		expect(chromeKeyIntent(key({ key: 't' }), false)).toBe('ignore');
	});

	it('maps the armed alphabet', () => {
		expect(chromeKeyIntent(key({ key: 'a' }), true)).toBe('annotate');
		expect(chromeKeyIntent(key({ key: 'A' }), true)).toBe('annotate');
		expect(chromeKeyIntent(key({ key: 'j' }), true)).toBe('adjust');
		expect(chromeKeyIntent(key({ key: 'z' }), true)).toBe('display');
		expect(chromeKeyIntent(key({ key: 'p' }), true)).toBe('present');
		// R is PRINT's ☰ mnemonic — not a chrome-arm letter.
		expect(chromeKeyIntent(key({ key: 'r' }), true)).toBe('ignore');
		expect(chromeKeyIntent(key({ key: 'd' }), true)).toBe('ignore');
		expect(chromeKeyIntent(key({ key: 'm' }), true)).toBe('more');
		expect(chromeKeyIntent(key({ key: 'M' }), true)).toBe('more');
		expect(chromeKeyIntent(key({ key: 't' }), true)).toBe('toc');
		expect(chromeKeyIntent(key({ key: 'u' }), true)).toBe('kiosk-pause');
		expect(chromeKeyIntent(key({ key: 'U' }), true)).toBe('kiosk-pause');
	});

	it('falls back to the physical key on a non-Latin layout', () => {
		// Cyrillic layout: the M cap reports 'ь'. The cap the user pressed is still M.
		expect(chromeKeyIntent(key({ key: 'ь', code: 'KeyM' }), true)).toBe('more');
		expect(chromeKeyIntent(key({ key: 'ф', code: 'KeyA' }), true)).toBe('annotate');
		// A Latin key still wins over the code, so Dvorak/Colemak get the cap they SEE.
		expect(chromeKeyIntent(key({ key: 'm', code: 'KeyV' }), true)).toBe('more');
		// Garbage in, 'ignore' out — never a throw.
		expect(chromeKeyIntent(key({ key: '', code: '' }), true)).toBe('ignore');
		expect(chromeKeyIntent(key({ key: 'ь', code: 'Digit1' }), true)).toBe('ignore');
	});

	it('Escape disarms / closes ☰ whether or not bars are Alt+.-armed', () => {
		expect(chromeKeyIntent(key({ key: 'Escape' }), true)).toBe('disarm');
		expect(chromeKeyIntent(key({ key: 'Escape' }), false)).toBe('disarm');
	});

	it('ignores mnemonics while typing even when armed', () => {
		const input = { tagName: 'INPUT' } as unknown as EventTarget;
		expect(chromeKeyIntent(key({ key: 'a', target: input }), true)).toBe('ignore');
	});
});

describe('moreMenuKeyIntent — ☰ row letters', () => {
	it('is idle when chrome is unarmed and the drop is closed', () => {
		expect(moreMenuKeyIntent(key({ key: 'c' }), false, false)).toBe('ignore');
		expect(moreMenuKeyIntent(key({ key: 'r' }), false, false)).toBe('ignore');
	});

	it('maps O/K/C/R/S/E while the drop is open (even if arm timed out)', () => {
		expect(moreMenuKeyIntent(key({ key: 'o' }), true, false)).toBe('overview');
		expect(moreMenuKeyIntent(key({ key: 'k' }), true, false)).toBe('kiosk');
		expect(moreMenuKeyIntent(key({ key: 'c' }), true, false)).toBe('capture');
		expect(moreMenuKeyIntent(key({ key: 'C' }), true, false)).toBe('capture');
		// PRINT is R — P is PRESENT on the bar.
		expect(moreMenuKeyIntent(key({ key: 'r' }), true, false)).toBe('print');
		expect(moreMenuKeyIntent(key({ key: 's' }), true, false)).toBe('source');
		expect(moreMenuKeyIntent(key({ key: 'e' }), true, false)).toBe('edit');
	});

	it('also fires while chrome is armed with the drop still closed', () => {
		// Alt+. then c should open ☰ and run CAPTURE — the underline is not a lie.
		expect(moreMenuKeyIntent(key({ key: 'c' }), false, true)).toBe('capture');
		expect(moreMenuKeyIntent(key({ key: 'r' }), false, true)).toBe('print');
	});

	it('does not claim bar-level letters (those stay on chromeKeyIntent)', () => {
		expect(moreMenuKeyIntent(key({ key: 'm' }), true, true)).toBe('ignore');
		expect(moreMenuKeyIntent(key({ key: 'a' }), true, true)).toBe('ignore');
		expect(moreMenuKeyIntent(key({ key: 'p' }), true, true)).toBe('ignore');
	});

	it('ignores typing targets and modifier chords', () => {
		const input = { tagName: 'INPUT' } as unknown as EventTarget;
		expect(moreMenuKeyIntent(key({ key: 'c', target: input }), true, true)).toBe('ignore');
		expect(moreMenuKeyIntent(key({ key: 'c', ctrlKey: true }), true, true)).toBe('ignore');
	});

	it('falls back to the physical key on a non-Latin layout', () => {
		expect(moreMenuKeyIntent(key({ key: 'с', code: 'KeyC' }), true, false)).toBe('capture');
	});
});

describe('isAdjustSaveChord', () => {
	it('claims Ctrl+S and Cmd+S while ADJUST is active', () => {
		expect(isAdjustSaveChord(key({ key: 's', ctrlKey: true }), true)).toBe(true);
		expect(isAdjustSaveChord(key({ key: 's', metaKey: true }), true)).toBe(true);
		// Capital S (Shift-lock, not Shift held) and non-Latin layouts via e.code.
		expect(isAdjustSaveChord(key({ key: 'S', ctrlKey: true }), true)).toBe(true);
		expect(isAdjustSaveChord(key({ key: 'ы', code: 'KeyS', ctrlKey: true }), true)).toBe(true);
	});

	it('stays inert when ADJUST is not active — the browser keeps Ctrl+S', () => {
		expect(isAdjustSaveChord(key({ key: 's', ctrlKey: true }), false)).toBe(false);
		expect(isAdjustSaveChord(key({ key: 's', metaKey: true }), false)).toBe(false);
	});

	it('leaves other chords to the browser', () => {
		// Bare S types a letter; Shift/Alt carry Save As and friends.
		expect(isAdjustSaveChord(key({ key: 's' }), true)).toBe(false);
		expect(isAdjustSaveChord(key({ key: 's', ctrlKey: true, shiftKey: true }), true)).toBe(false);
		expect(isAdjustSaveChord(key({ key: 's', ctrlKey: true, altKey: true }), true)).toBe(false);
		// A different letter under Ctrl is not ours.
		expect(isAdjustSaveChord(key({ key: 'a', ctrlKey: true }), true)).toBe(false);
	});

	it('fires even with the caret in a field — Ctrl+S means save, not the dialog', () => {
		const input = { tagName: 'INPUT' } as unknown as EventTarget;
		expect(isAdjustSaveChord(key({ key: 's', ctrlKey: true, target: input }), true)).toBe(true);
	});
});
