import { fireEvent, render } from '@testing-library/svelte';
import { tick } from 'svelte';
import { get } from 'svelte/store';
import { beforeEach, describe, expect, it } from 'vitest';
import MenuDismissHost from './MenuDismissHost.svelte';
import { closeMoreMenu, moreMenuOpen, toggleMoreMenu } from '../src/lib/stores/chromeArm';

// THE regression: clicking SOURCE opened the source panel and left the ☰ drop sitting on
// top of it. The latch closed and focus was blurred — but `.annot-menu:hover .annot-drop`
// still matched, because after clicking a row the pointer is by definition still on it,
// and the drop covers the very panel the row just opened, so moving toward it never
// leaves the menu. `dismissed` is the force-close that path lacked.
//
// NOTE ON WHAT THESE ASSERT: jsdom does not apply Svelte's scoped CSS, so
// getComputedStyle().opacity is empty here and no test can prove the drop is VISUALLY
// gone. They assert the `dismissed` STATE that the `:not(.dismissed)` guards key off.
// Treat the CSS itself as reviewed, not tested.

const menu = () => document.querySelector('.annot-menu') as HTMLElement;
const isLatched = () => menu().classList.contains('menu-open');
const isDismissed = () => menu().classList.contains('dismissed');
const row = (kind: string) => document.querySelector(`[data-row="${kind}"]`) as Element;

describe('the ☰ drop dismisses when a row is picked', () => {
	beforeEach(() => {
		closeMoreMenu();
	});

	it('dismisses on an ordinary row click — the pointer is still on the row', async () => {
		render(MenuDismissHost);
		toggleMoreMenu();
		await tick();
		expect(isLatched()).toBe(true);
		expect(isDismissed()).toBe(false);

		await fireEvent.click(row('ordinary'));
		await tick();
		expect(get(moreMenuOpen)).toBe(false); // the latch drops, as before
		expect(isDismissed()).toBe(true); // and hover/focus are now overridden
	});

	it('dismisses on SOURCE — the row that opens a panel under the drop', async () => {
		render(MenuDismissHost);
		toggleMoreMenu();
		await tick();

		await fireEvent.click(row('source'));
		await tick();
		expect(isLatched()).toBe(false);
		expect(isDismissed()).toBe(true);
	});

	it('does NOT dismiss for PRINT, whose flyout lives inside the drop', async () => {
		render(MenuDismissHost);
		toggleMoreMenu();
		await tick();

		await fireEvent.click(row('print')); // stops propagation
		await tick();
		expect(isLatched()).toBe(true); // still open…
		expect(isDismissed()).toBe(false); // …and not dismissed
	});

	it('clears the dismissal once the pointer leaves, so hover-to-open still works', async () => {
		render(MenuDismissHost);
		toggleMoreMenu();
		await tick();
		await fireEvent.click(row('ordinary'));
		await tick();
		expect(isDismissed()).toBe(true);

		await fireEvent.pointerLeave(menu());
		await tick();
		expect(isDismissed()).toBe(false); // hover may open it again
	});

	it('reopening beats a past dismissal, even with the pointer still parked on ☰', async () => {
		render(MenuDismissHost);
		toggleMoreMenu();
		await tick();
		await fireEvent.click(row('ordinary'));
		await tick();
		expect(isDismissed()).toBe(true);

		// No pointerleave — M (or a click on the hamburger) straight after a dismissal.
		toggleMoreMenu();
		await tick();
		expect(isLatched()).toBe(true);
		expect(isDismissed()).toBe(false);
	});

	it('starts undismissed, so the first hover opens the drop', async () => {
		render(MenuDismissHost);
		await tick();
		expect(isDismissed()).toBe(false);
	});
});
