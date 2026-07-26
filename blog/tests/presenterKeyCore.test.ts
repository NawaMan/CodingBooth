import { describe, expect, it } from 'vitest';
import { presenterKeyIntent } from '../src/lib/chrome/presenterKeyCore';

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

describe('presenterKeyIntent — the three console mnemonics', () => {
	it('maps T / C to the TOC and reset-checks menus', () => {
		expect(presenterKeyIntent(key({ key: 't' }))).toBe('toc');
		expect(presenterKeyIntent(key({ key: 'c' }))).toBe('checks');
	});

	it('is case-insensitive (Shift or CapsLock still hits)', () => {
		expect(presenterKeyIntent(key({ key: 'T' }))).toBe('toc');
		expect(presenterKeyIntent(key({ key: 'C' }))).toBe('checks');
		expect(presenterKeyIntent(key({ key: 'A' }), true)).toBe('ink');
	});

	it('gates A on the ink control being offered', () => {
		// pen offered → A toggles the reset-ink menu…
		expect(presenterKeyIntent(key({ key: 'a' }), true)).toBe('ink');
		// …but inert when annotation was never offered (default false), so it does
		// not toggle a menu that isn't in the bar.
		expect(presenterKeyIntent(key({ key: 'a' }))).toBe('ignore');
		expect(presenterKeyIntent(key({ key: 'a' }), false)).toBe('ignore');
	});

	it('ignores every other letter', () => {
		for (const k of ['b', 'x', 'z', 's', 'q', '1']) {
			expect(presenterKeyIntent(key({ key: k }), true)).toBe('ignore');
		}
	});
});

describe('presenterKeyIntent — TOC browsing (↑/↓/Enter) while the menu is open', () => {
	it('walks the rows only while the menu is open', () => {
		expect(presenterKeyIntent(key({ key: 'ArrowDown' }), false, true)).toBe('tocDown');
		expect(presenterKeyIntent(key({ key: 'ArrowUp' }), false, true)).toBe('tocUp');
		expect(presenterKeyIntent(key({ key: 'Enter' }), false, true)).toBe('tocSelect');
	});

	it('does nothing with those keys while the menu is closed', () => {
		expect(presenterKeyIntent(key({ key: 'ArrowDown' }), false, false)).toBe('ignore');
		expect(presenterKeyIntent(key({ key: 'Enter' }), false, false)).toBe('ignore');
	});

	it('still lets ←/→ page the deck even while the menu is open', () => {
		expect(presenterKeyIntent(key({ key: 'ArrowRight' }), false, true)).toBe('next');
		expect(presenterKeyIntent(key({ key: 'ArrowLeft' }), false, true)).toBe('prev');
	});

	it('still lets T close the menu (toggle) while it is open', () => {
		expect(presenterKeyIntent(key({ key: 't' }), false, true)).toBe('toc');
	});

	it('never fires while typing, even with the menu open (the search box owns its own keys)', () => {
		const input = { tagName: 'INPUT' } as unknown as EventTarget;
		expect(presenterKeyIntent(key({ key: 'ArrowDown', target: input }), false, true)).toBe('ignore');
	});
});

describe('presenterKeyIntent — paging keys', () => {
	it('arrows page the deck (→ next, ← prev), never step', () => {
		expect(presenterKeyIntent(key({ key: 'ArrowRight' }))).toBe('next');
		expect(presenterKeyIntent(key({ key: 'ArrowLeft' }))).toBe('prev');
	});

	it('Shift does not change what an arrow does — it still pages', () => {
		expect(presenterKeyIntent(key({ key: 'ArrowRight', shiftKey: true }))).toBe('next');
		expect(presenterKeyIntent(key({ key: 'ArrowLeft', shiftKey: true }))).toBe('prev');
	});

	it('Space advances the build (relays CONTINUE, never pages)', () => {
		// however the browser reports the space bar
		expect(presenterKeyIntent(key({ key: ' ' }))).toBe('continue');
		expect(presenterKeyIntent(key({ key: 'Spacebar', code: 'Space' }))).toBe('continue');
	});

	it('Shift+Space walks the deck back', () => {
		expect(presenterKeyIntent(key({ key: ' ', shiftKey: true }))).toBe('prev');
		expect(presenterKeyIntent(key({ key: 'Spacebar', code: 'Space', shiftKey: true }))).toBe('prev');
	});

	it('never pages while the caret is in a field (the timer input)', () => {
		const inField = { target: { tagName: 'INPUT' } as EventTarget };
		expect(presenterKeyIntent(key({ key: 'ArrowRight', ...inField }))).toBe('ignore');
		expect(presenterKeyIntent(key({ key: ' ', ...inField }))).toBe('ignore');
	});

	it('leaves modified paging chords to the browser (Alt+←, Cmd+→…)', () => {
		expect(presenterKeyIntent(key({ key: 'ArrowLeft', altKey: true }))).toBe('ignore');
		expect(presenterKeyIntent(key({ key: 'ArrowRight', metaKey: true }))).toBe('ignore');
		expect(presenterKeyIntent(key({ key: ' ', ctrlKey: true }))).toBe('ignore');
	});

	it('respects an already-consumed paging event', () => {
		expect(presenterKeyIntent(key({ key: 'ArrowRight', defaultPrevented: true }))).toBe('ignore');
		expect(presenterKeyIntent(key({ key: ' ', defaultPrevented: true }))).toBe('ignore');
	});
});

describe('presenterKeyIntent — Escape closes menus', () => {
	it('a plain Escape means close', () => {
		expect(presenterKeyIntent(key({ key: 'Escape' }))).toBe('close');
	});

	it('closes even from a typing target — so it dismisses the timer popover', () => {
		expect(
			presenterKeyIntent(key({ key: 'Escape', target: { tagName: 'INPUT' } as EventTarget }))
		).toBe('close');
	});

	it('a modified Escape is left to the browser', () => {
		expect(presenterKeyIntent(key({ key: 'Escape', ctrlKey: true }))).toBe('ignore');
		expect(presenterKeyIntent(key({ key: 'Escape', altKey: true }))).toBe('ignore');
	});
});

describe('presenterKeyIntent — never fires over typing or a chord', () => {
	it('bails while the caret is in a field (the timer input)', () => {
		expect(
			presenterKeyIntent(key({ key: 't', target: { tagName: 'INPUT' } as EventTarget }), true)
		).toBe('ignore');
		expect(
			presenterKeyIntent(
				key({ key: 'c', target: { isContentEditable: true } as unknown as EventTarget }),
				true
			)
		).toBe('ignore');
	});

	it('leaves Ctrl / Cmd / Alt combinations to the browser (Ctrl+A, Cmd+T…)', () => {
		expect(presenterKeyIntent(key({ key: 't', ctrlKey: true }), true)).toBe('ignore');
		expect(presenterKeyIntent(key({ key: 't', metaKey: true }), true)).toBe('ignore');
		expect(presenterKeyIntent(key({ key: 'a', altKey: true }), true)).toBe('ignore');
		expect(presenterKeyIntent(key({ key: 'c', ctrlKey: true }), true)).toBe('ignore');
	});

	it('respects an already-consumed event (defaultPrevented)', () => {
		expect(presenterKeyIntent(key({ key: 't', defaultPrevented: true }), true)).toBe('ignore');
	});
});

describe('presenterKeyIntent — total on garbage', () => {
	it('never throws and answers ignore for junk', () => {
		expect(presenterKeyIntent(key({ key: '' }), true)).toBe('ignore');
		expect(presenterKeyIntent({} as KeyboardEvent, true)).toBe('ignore');
		expect(presenterKeyIntent(key({ key: 'undefined' as unknown as string }))).toBe('ignore');
	});
});
