// DOM tests for the top toolbar: it owns the ANNOTATE pen toggle (lifted here from <Annotate>
// so it out-ranks the armed ink surface — the overlay it lives in sits above the surface) and
// folds in the DISPLAY zoom control. The pen's DRAWING behaviour is still tested in
// Annotate.test.ts; this file covers only what the toolbar itself is responsible for.
import { render, cleanup, fireEvent, screen } from '@testing-library/svelte';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { get } from 'svelte/store';
import { tick } from 'svelte';
import SlideToolbarHost from './SlideToolbarHost.svelte';
import { annotationMode, canAnnotate, resetAllInk } from '../src/lib/stores/annotation';
import { toolBarPinned } from '../src/lib/stores/chromePin';
import { armChrome, disarmChrome, moreMenuOpen, toggleMoreMenu } from '../src/lib/stores/chromeArm';
import { overviewOpen } from '../src/lib/stores/overviewOpen';

beforeEach(() => {
	localStorage.clear();
	resetAllInk();
	canAnnotate.set(true);
	annotationMode.set(false);
	toolBarPinned.set(false);
	disarmChrome();
	overviewOpen.set(false);
});

afterEach(cleanup);

describe('SlideToolbar', () => {
	it('arms and disarms the pen from the ANNOTATE toggle', async () => {
		render(SlideToolbarHost);

		// The bug this guards: the toggle used to sit UNDER the ink surface, which owns every
		// pointer while armed — so a speaker could arm the pen and never disarm it. It now lives
		// in the window-fixed overlay, above the surface; its aria-label carries the on/off state.
		const off = screen.getByLabelText('ANNOTATE off');
		await fireEvent.click(off);
		expect(get(annotationMode)).toBe(true);

		await fireEvent.click(screen.getByLabelText('ANNOTATE on'));
		expect(get(annotationMode)).toBe(false);
	});

	it('shows the ANNOTATE toggle DISABLED on a deck that never offered the pen', () => {
		canAnnotate.set(false);
		render(SlideToolbarHost);

		const toggle = screen.getByLabelText('ANNOTATE off') as HTMLButtonElement;
		expect(toggle.disabled).toBe(true);
	});

	it('folds in the DISPLAY zoom control', () => {
		render(SlideToolbarHost);

		// The <SizeMode> renders in its inline (in-row) form, not its standalone corner form.
		const display = document.querySelector('.mode.inline');
		expect(display).toBeTruthy();
		// FITTED is the default label (no persisted mode in a cleared localStorage).
		// Z is not in the word, so the trailing chip stays: "FITTED (Z)".
		expect(display?.textContent).toContain('FITTED (Z)');
	});

	it('underlines in-word mnemonics and keeps chips only for Z/M', () => {
		render(SlideToolbarHost);

		const annotate = screen.getByLabelText('ANNOTATE off');
		expect(annotate.textContent).toBe('ANNOTATE');
		expect(annotate.querySelector('.tool-mn')?.textContent).toBe('A');
		expect(annotate.textContent).not.toContain('(A)');

		// ☰ has no M in the glyph — chip stays.
		const more = screen.getByLabelText('More tools (M)');
		expect(more.textContent).toContain('☰ (M)');
		expect(more.querySelector('.tool-mn')).toBeNull();
	});

	it('pins the bar fully open and unpins back to auto-hide', async () => {
		render(SlideToolbarHost);
		const bar = document.querySelector('.annot-tools');
		expect(bar?.classList.contains('pinned')).toBe(false);

		await fireEvent.click(screen.getByLabelText('PIN off'));
		expect(get(toolBarPinned)).toBe(true);
		expect(bar?.classList.contains('pinned')).toBe(true);
		expect(screen.getByLabelText('PIN on')).toBeTruthy();

		await fireEvent.click(screen.getByLabelText('PIN on'));
		expect(get(toolBarPinned)).toBe(false);
		expect(bar?.classList.contains('pinned')).toBe(false);
	});
});

// The ☰ drop used to have NO open state at all: it was pure CSS `:hover` / `:focus-within`, the
// M mnemonic just focused the hamburger and hoped, and Esc fought back with a sticky
// "held closed" flag that only a mouseenter could clear. These cover the real latch that
// replaced all of that. `menu-open` is the class the CSS opens on.
describe('SlideToolbar ☰ menu', () => {
	const menu = () => document.querySelector('.annot-menu');
	const isOpen = () => !!menu()?.classList.contains('menu-open');

	it('opens and closes from a click on the hamburger', async () => {
		render(SlideToolbarHost);
		const burger = screen.getByLabelText('More tools (M)');
		expect(isOpen()).toBe(false);
		expect(burger.getAttribute('aria-expanded')).toBe('false');

		await fireEvent.click(burger);
		expect(get(moreMenuOpen)).toBe(true);
		expect(isOpen()).toBe(true);
		expect(burger.getAttribute('aria-expanded')).toBe('true');

		await fireEvent.click(burger);
		expect(isOpen()).toBe(false);
	});

	it('survives Esc — the M mnemonic still opens it afterwards', async () => {
		// THE regression. Esc used to latch the drop closed until the pointer visited the menu,
		// so from then on Alt+. raised the bars (a different store, so it all LOOKED fine) and
		// M silently did nothing.
		render(SlideToolbarHost);

		toggleMoreMenu(); // M
		await tick();
		expect(isOpen()).toBe(true);

		disarmChrome(); // Esc
		await tick();
		expect(isOpen()).toBe(false);

		armChrome(); // Alt+.
		toggleMoreMenu(); // M again — with no mouse anywhere near the bar
		await tick();
		expect(isOpen()).toBe(true);
	});

	it('closes when OVERVIEW takes the screen', async () => {
		render(SlideToolbarHost);
		toggleMoreMenu();
		await tick();
		expect(isOpen()).toBe(true);

		overviewOpen.set(true);
		await tick();
		expect(isOpen()).toBe(false);
	});

	it('closes on a click outside, but not on one inside the panel', async () => {
		render(SlideToolbarHost);
		toggleMoreMenu();
		await tick();

		await fireEvent.pointerDown(document.querySelector('.annot-drop') as Element);
		await tick();
		expect(isOpen()).toBe(true);

		await fireEvent.pointerDown(document.body);
		await tick();
		expect(isOpen()).toBe(false);
	});

	it('puts itself away when a row is picked', async () => {
		render(SlideToolbarHost);
		toggleMoreMenu();
		await tick();

		await fireEvent.click(screen.getByText('OVERVIEW'));
		await tick();
		expect(isOpen()).toBe(false);
	});

	it('dismisses even when focus was inside the menu (focus-within would otherwise stick)', async () => {
		render(SlideToolbarHost);
		const burger = screen.getByLabelText('More tools (M)');
		toggleMoreMenu();
		await tick();
		burger.focus();
		expect(isOpen()).toBe(true);

		// Latch closed — without the blur effect, :focus-within would keep the drop open.
		await import('../src/lib/stores/chromeArm').then((m) => m.closeMoreMenu());
		await tick();
		expect(isOpen()).toBe(false);
		expect(document.activeElement === burger).toBe(false);
	});

	it('keeps the bar seated while open, so the arm timeout cannot tuck it away', async () => {
		render(SlideToolbarHost);
		toggleMoreMenu();
		await tick();
		// `armed` is gone (the 5s timer owns it) but `menu-open` holds the same seat.
		expect(document.querySelector('.annot-tools')?.classList.contains('menu-open')).toBe(true);
	});
});
