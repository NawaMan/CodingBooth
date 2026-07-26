import { render } from '@testing-library/svelte';
import { tick } from 'svelte';
import { describe, expect, it, vi } from 'vitest';
import TabsHost from './TabsHost.svelte';

// The interactive half of Tabs / Tab (the SSR half — the strip + panel structure —
// is in TabsSsr.ssr.test.ts). Clicking a tab shows its panel; the roving keyboard
// (←/→, Home/End) moves selection while a tab is focused, skips disabled tabs and
// wraps; and it stops the arrow keys ONLY while a tab is focused, so the deck's
// paging keeps working the instant focus leaves.
//
// The host renders three tabs: JavaScript, Python (icon), Go (disabled).

const tabButtons = (root: ParentNode) =>
	Array.from(root.querySelectorAll('button[role="tab"]')) as HTMLButtonElement[];
const panels = (root: ParentNode) =>
	Array.from(root.querySelectorAll('[role="tabpanel"]')) as HTMLElement[];
const active = (el: HTMLElement) => el.classList.contains('active');

function press(target: EventTarget, key: string) {
	const ev = new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true });
	target.dispatchEvent(ev);
	return ev;
}

describe('Tabs / Tab', () => {
	it('renders a button per tab and shows the first panel by default', async () => {
		const { container } = render(TabsHost);
		await tick();
		const tabs = tabButtons(container);
		const p = panels(container);
		expect(tabs).toHaveLength(3);
		expect(p).toHaveLength(3);
		expect(tabs[0].getAttribute('aria-selected')).toBe('true');
		expect(active(p[0])).toBe(true);
		expect(active(p[1])).toBe(false);
	});

	it('clicking a tab switches to its panel', async () => {
		const { container } = render(TabsHost);
		await tick();
		const tabs = tabButtons(container);
		const p = panels(container);

		tabs[1].click();
		await tick();
		expect(tabs[1].getAttribute('aria-selected')).toBe('true');
		expect(tabs[0].getAttribute('aria-selected')).toBe('false');
		expect(active(p[1])).toBe(true);
		expect(active(p[0])).toBe(false);
	});

	it('clicking a disabled tab does nothing (Go stays unselected)', async () => {
		const { container } = render(TabsHost);
		await tick();
		const tabs = tabButtons(container);
		expect(tabs[2].disabled).toBe(true);
		tabs[2].click(); // a disabled button won't fire click, but assert the state anyway
		await tick();
		expect(tabs[2].getAttribute('aria-selected')).toBe('false');
		expect(tabs[0].getAttribute('aria-selected')).toBe('true');
	});

	it('ArrowRight moves selection and skips the disabled tab, wrapping at the end', async () => {
		const { container } = render(TabsHost);
		await tick();
		const tabs = tabButtons(container);

		press(tabs[0], 'ArrowRight');
		await tick();
		expect(tabs[1].getAttribute('aria-selected')).toBe('true'); // 0 → 1

		press(tabs[1], 'ArrowRight');
		await tick();
		// 1 → (2 is disabled) → wraps to 0
		expect(tabs[0].getAttribute('aria-selected')).toBe('true');
	});

	it('ArrowLeft wraps backwards, skipping disabled; Home/End jump to the ends', async () => {
		const { container } = render(TabsHost);
		await tick();
		const tabs = tabButtons(container);

		press(tabs[0], 'ArrowLeft');
		await tick();
		// 0 → back wraps, 2 is disabled → lands on 1
		expect(tabs[1].getAttribute('aria-selected')).toBe('true');

		press(tabs[1], 'End');
		await tick();
		// End = last ENABLED tab → 1 (Go is disabled)
		expect(tabs[1].getAttribute('aria-selected')).toBe('true');

		press(tabs[1], 'Home');
		await tick();
		expect(tabs[0].getAttribute('aria-selected')).toBe('true');
	});

	it('the roving tabindex keeps exactly one tab-stop', async () => {
		const { container } = render(TabsHost);
		await tick();
		const tabs = tabButtons(container);
		expect(tabs[0].tabIndex).toBe(0);
		expect(tabs[1].tabIndex).toBe(-1);

		tabs[1].click();
		await tick();
		expect(tabs[0].tabIndex).toBe(-1);
		expect(tabs[1].tabIndex).toBe(0);
	});

	it('claims the arrow keys ONLY while a tab is focused (deck paging is safe otherwise)', async () => {
		const { container } = render(TabsHost);
		await tick();
		const tabs = tabButtons(container);

		// A window listener stands in for NavigationBar's arrow-key paging.
		const paged = vi.fn();
		window.addEventListener('keydown', paged);
		try {
			// From a focused tab, the arrow is consumed (prevented + stopped) so it
			// never reaches the window.
			const owned = press(tabs[0], 'ArrowRight');
			await tick();
			expect(owned.defaultPrevented).toBe(true);
			expect(paged).not.toHaveBeenCalled();

			// A plain key the tabs don't handle passes straight through to the deck.
			const other = press(tabs[0], 'ArrowUp'); // handled → also owned
			expect(other.defaultPrevented).toBe(true);
			paged.mockClear();

			// A key from OUTSIDE the strip (the deck body) is never touched.
			press(document.body, 'ArrowRight');
			expect(paged).toHaveBeenCalled();
		} finally {
			window.removeEventListener('keydown', paged);
		}
	});
});
