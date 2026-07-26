// DOM tests for ProgressBar: it reports the current slide's position over the deck's
// visible total, it tracks paging live (the fill follows the route), and it hides on a
// slide that isn't part of the linear march (a hidden appendix, an off-list route).
import { render, cleanup } from '@testing-library/svelte';
import { afterEach, describe, expect, it } from 'vitest';
import { tick } from 'svelte';
import { setPageUrl, resetPageUrl } from './stubs/app-stores';
import Host from './ProgressBarHost.svelte';

afterEach(() => {
	cleanup();
	resetPageUrl();
});

describe('ProgressBar', () => {
	it('reports position over the VISIBLE total and fills accordingly', () => {
		setPageUrl('/slides/a.html'); // 1st of 4
		const { getByRole } = render(Host);
		const bar = getByRole('progressbar');
		expect(bar.getAttribute('aria-valuenow')).toBe('1');
		expect(bar.getAttribute('aria-valuemax')).toBe('4');
		expect(bar.getAttribute('aria-label')).toBe('Slide 1 of 4');
		const fill = bar.querySelector('.fill') as HTMLElement;
		expect(fill.style.width).toBe('25%');
	});

	it('fills completely on the last slide', () => {
		setPageUrl('/slides/stub.html'); // 4th of 4
		const { getByRole } = render(Host);
		const bar = getByRole('progressbar');
		expect(bar.getAttribute('aria-valuenow')).toBe('4');
		expect((bar.querySelector('.fill') as HTMLElement).style.width).toBe('100%');
	});

	it('tracks paging live — the fill follows the route as it changes', async () => {
		setPageUrl('/slides/a.html');
		const { getByRole } = render(Host);
		expect((getByRole('progressbar').querySelector('.fill') as HTMLElement).style.width).toBe('25%');

		setPageUrl('/slides/c.html'); // paged to the 3rd of 4
		await tick();
		const bar = getByRole('progressbar');
		expect(bar.getAttribute('aria-valuenow')).toBe('3');
		expect((bar.querySelector('.fill') as HTMLElement).style.width).toBe('75%');
	});

	it('renders nothing on a route that is not a visible slide', () => {
		setPageUrl('/slides/ghost.html'); // not in the deck
		const { queryByRole } = render(Host);
		expect(queryByRole('progressbar')).toBeNull();
	});
});
