import { render } from '@testing-library/svelte';
import { tick } from 'svelte';
import { get } from 'svelte/store';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import NoteTriggerHost from './NoteTriggerHost.svelte';
import { presenterMode } from '../src/lib/stores/presenter';
import { lastTrigger } from '../src/lib/stores/triggers';

// The note-driven trigger: checking a `data-trigger` line in the presenter
// console fires that name (locally here; the cross-window relay is covered
// in tests/presenter.test.ts's "trigger pulse channel", and the SlideDeck
// bridge that turns a relayed pulse into fireTrigger has no dedicated test,
// same standard as the highlight bridge it mirrors).
const lines = (root: ParentNode) => [...root.querySelectorAll('.note li')] as HTMLElement[];
const checkbox = (line: HTMLElement) => line.querySelector('.gp-check') as HTMLElement;
const click = (el: HTMLElement, opts: Partial<MouseEventInit> = {}) =>
	el.dispatchEvent(new MouseEvent('click', { bubbles: true, ...opts }));

beforeEach(() => {
	lastTrigger.set(null);
	presenterMode.set(true);
});
afterEach(() => {
	presenterMode.set(false);
	localStorage.clear(); // note check-off state persists across renders — don't leak between tests
});

describe('Note — data-trigger', () => {
	it('marks only the lines that carry a data-trigger', async () => {
		const { container } = render(NoteTriggerHost);
		await tick();
		const [save, plain, menu] = lines(container);
		expect(save.classList.contains('gp-trigger-line')).toBe(true);
		expect(menu.classList.contains('gp-trigger-line')).toBe(true);
		expect(plain.classList.contains('gp-trigger-line')).toBe(false);
	});

	it('fires the named pulse when the checkbox is checked ON', async () => {
		const { container } = render(NoteTriggerHost);
		await tick();
		const [save] = lines(container);
		click(checkbox(save));
		expect(get(lastTrigger)?.name).toBe('save-cursor');
	});

	it('does NOT fire when unchecking', async () => {
		const { container } = render(NoteTriggerHost);
		await tick();
		const [save] = lines(container);
		click(checkbox(save)); // ON — fires
		lastTrigger.set(null);
		click(checkbox(save)); // OFF — must not re-fire
		expect(get(lastTrigger)).toBeNull();
	});

	it('re-checking the same line fires again — a fresh pulse each time', async () => {
		const { container } = render(NoteTriggerHost);
		await tick();
		const [save] = lines(container);
		click(checkbox(save)); // ON — fires
		expect(get(lastTrigger)?.name).toBe('save-cursor');

		lastTrigger.set(null); // clear, so the second fire is unambiguous
		click(checkbox(save)); // OFF — must not re-fire (covered above too)
		expect(get(lastTrigger)).toBeNull();
		click(checkbox(save)); // ON again — fires a FRESH pulse
		expect(get(lastTrigger)?.name).toBe('save-cursor');
	});

	it('does NOT fire on a Shift+Click cumulative catch-up', async () => {
		const { container } = render(NoteTriggerHost);
		await tick();
		const [, , menu] = lines(container); // the 3rd line, checked cumulatively
		click(checkbox(menu), { shiftKey: true });
		expect(get(lastTrigger)).toBeNull();
	});

	it('a plain line with no data-trigger drives nothing', async () => {
		const { container } = render(NoteTriggerHost);
		await tick();
		const plain = lines(container)[1];
		click(checkbox(plain));
		expect(get(lastTrigger)).toBeNull();
	});
});
