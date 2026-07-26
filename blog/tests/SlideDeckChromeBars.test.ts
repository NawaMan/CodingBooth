// SlideDeck's window-edge chrome bars are ON by default and opt-out via props —
// `toolBar={false}` / `controlBar={false}`. The top bar holds more authoring/dev
// rows (SOURCE/EDIT, ADJUST SAVE, …); the bottom bar is navigation (TOC + pager).
import { render, cleanup, fireEvent } from '@testing-library/svelte';
import { tick } from 'svelte';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { get } from 'svelte/store';
import SlideDeck from '$lib/components/SlideDeck.svelte';
import { setPageUrl, resetPageUrl } from './stubs/app-stores';
import {
	chromeArmed,
	moreMenuOpen,
	openMoreMenu,
	closeMoreMenu,
	disarmChrome
} from '../src/lib/stores/chromeArm';
import { kioskStatus, kioskPanelPinned, startKiosk, stopKiosk } from '../src/lib/stores/kiosk';

const pages = [{ path: 'stub.html', title: 'Stub' }];

beforeEach(() => disarmChrome());

async function mount(props: Record<string, unknown> = {}) {
	setPageUrl('/slides/stub.html');
	const { container } = render(SlideDeck, { props: { pages, ...props } });
	await tick();
	await tick(); // onMount → initialized → overlay chrome
	return container;
}

afterEach(() => {
	cleanup();
	resetPageUrl();
});

// The PRINT flyout opens on MOUSEENTER, and `onChromeKeys` used to treat "flyout is open" as
// "the flyout owns the whole keyboard" — every unclaimed key returned early. So a printMenuOpen
// that never got its matching mouseleave (the ☰ shutting under the pointer leaves the row
// pointer-events:none, and the browser owes you no mouseleave then) killed Alt+., M, and the
// arrows for the rest of the page's life. Only a reload brought them back.
describe('SlideDeck — a stuck PRINT flyout does not eat the keyboard', () => {
	it('lets Alt+. through while the flyout is open', async () => {
		const root = await mount();
		const flyout = root.querySelector('.print-flyout');
		expect(flyout).not.toBeNull();

		// Pointer wanders onto PRINT: the flyout latches open.
		await fireEvent.mouseEnter(flyout as Element);
		await tick();

		// Alt+. is not one of the flyout's keys (cCwWtT / Escape) — it must fall through.
		await fireEvent.keyDown(window, { key: '.', code: 'Period', altKey: true });
		await tick();
		expect(get(chromeArmed)).toBe(true);

		// And so must the M mnemonic.
		await fireEvent.keyDown(window, { key: 'm', code: 'KeyM' });
		await tick();
		expect(get(moreMenuOpen)).toBe(true);
	});

	it('drops the flyout latch when the ☰ that contains it closes', async () => {
		const root = await mount();
		openMoreMenu();
		await tick();
		await fireEvent.mouseEnter(root.querySelector('.print-flyout') as Element);
		await tick();
		expect(root.querySelector('.print-flyout')?.classList.contains('open')).toBe(true);

		// The menu shuts with the pointer still parked on PRINT — no mouseleave arrives.
		closeMoreMenu();
		await tick();
		expect(root.querySelector('.print-flyout')?.classList.contains('open')).toBe(false);
	});
});

describe('SlideDeck chrome bars — Esc after Alt+.', () => {
	it('blurs top-bar focus so both bars tuck (not only the bottom one)', async () => {
		// Alt+. focuses the first top-bar control for arrow roving. Esc used to clear
		// `chromeArmed` but leave that focus in place — CSS `:focus-within` kept the TOP
		// bar seated while the bottom bar (no focus) tucked. Both must go away.
		const root = await mount();
		await fireEvent.keyDown(window, { key: '.', code: 'Period', altKey: true });
		await tick();
		await tick();
		expect(get(chromeArmed)).toBe(true);

		const tools = root.querySelector('.annot-tools');
		const first = tools?.querySelector('button') as HTMLElement | null;
		// Simulate the arm microtask having focused a top-bar control.
		first?.focus();
		expect(tools?.contains(document.activeElement as Node)).toBe(true);

		await fireEvent.keyDown(window, { key: 'Escape' });
		await tick();
		expect(get(chromeArmed)).toBe(false);
		expect(tools?.contains(document.activeElement as Node)).toBe(false);
		expect(get(moreMenuOpen)).toBe(false);
	});
});

describe('SlideDeck chrome bars — opt-out', () => {
	it('shows both bars by default', async () => {
		const root = await mount();
		expect(root.querySelector('.annot-tools')).not.toBeNull();
		expect(root.querySelector('.ctrl-bar')).not.toBeNull();
	});

	it('hides the ControlBar when controlBar={false}', async () => {
		const root = await mount({ controlBar: false });
		expect(root.querySelector('.ctrl-bar')).toBeNull();
		// Tool bar remains.
		expect(root.querySelector('.annot-tools')).not.toBeNull();
	});

	it('hides the tool bar when toolBar={false}', async () => {
		const root = await mount({ toolBar: false });
		expect(root.querySelector('.annot-tools')).toBeNull();
		// Control bar remains.
		expect(root.querySelector('.ctrl-bar')).not.toBeNull();
	});

	it('hides both when both are off (no empty overlay shell with only bars)', async () => {
		const root = await mount({ toolBar: false, controlBar: false });
		expect(root.querySelector('.annot-tools')).toBeNull();
		expect(root.querySelector('.ctrl-bar')).toBeNull();
		// Overlay itself is gated when neither bar is wanted.
		expect(root.querySelector('.overlay')).toBeNull();
	});
});

describe('SlideDeck chrome bars — kiosk keyboard (Alt+. K / U)', () => {
	beforeEach(() => {
		stopKiosk();
		kioskPanelPinned.set(false);
		// KioskRunner's tick() calls collectFinite() → getAnimations() once a kiosk is
		// running; jsdom ships no Web Animations API. Same stub as SlideDeckRelay.test.ts.
		const none = () => [] as Animation[];
		(Element.prototype as unknown as { getAnimations: () => Animation[] }).getAnimations = none;
		(Document.prototype as unknown as { getAnimations: () => Animation[] }).getAnimations = none;
	});

	afterEach(() => {
		stopKiosk();
		kioskPanelPinned.set(false);
		delete (Element.prototype as unknown as { getAnimations?: unknown }).getAnimations;
		delete (Document.prototype as unknown as { getAnimations?: unknown }).getAnimations;
	});

	async function arm() {
		await fireEvent.keyDown(window, { key: '.', code: 'Period', altKey: true });
		await tick();
		await tick();
		expect(get(chromeArmed)).toBe(true);
	}

	it('K toggles the panel pin instead of the dialog while a kiosk is live', async () => {
		await mount({ kiosk: true });
		startKiosk();
		await arm();

		await fireEvent.keyDown(window, { key: 'k', code: 'KeyK' });
		expect(get(kioskPanelPinned)).toBe(true);

		await arm();
		await fireEvent.keyDown(window, { key: 'k', code: 'KeyK' });
		expect(get(kioskPanelPinned)).toBe(false);
	});

	it('U pauses/resumes a live kiosk and is inert when none is running', async () => {
		await mount({ kiosk: true });
		await arm();
		await fireEvent.keyDown(window, { key: 'u', code: 'KeyU' });
		expect(get(kioskStatus)).toBe('off'); // no kiosk running — no-op, no throw

		startKiosk();
		await arm();
		await fireEvent.keyDown(window, { key: 'u', code: 'KeyU' });
		expect(get(kioskStatus)).toBe('paused');

		await arm();
		await fireEvent.keyDown(window, { key: 'u', code: 'KeyU' });
		expect(get(kioskStatus)).toBe('running');
	});
});
