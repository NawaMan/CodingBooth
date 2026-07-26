// @vitest-environment node
//
// True server-side render of ProgressBar (svelte/server, no DOM). The bar is purely
// declarative — it reads getProgress() (the slide list from context + the $page store),
// with no onMount or browser API — so its full markup must come from the server render,
// which is what prerendering a slide does. This locks in that the prerendered HTML carries
// the position, the total and the fill width, so a progress bar works without JS.
import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';
import Host from './ProgressBarSsrHost.svelte';

describe('ProgressBar (SSR)', () => {
	it('prerenders the bar with its position, total and fill width', () => {
		const { body } = render(Host);
		expect(body).toContain('role="progressbar"');
		// stub.html is the 3rd of 3 visible slides (see the host)
		expect(body).toContain('aria-valuenow="3"');
		expect(body).toContain('aria-valuemax="3"');
		expect(body).toContain('aria-label="Slide 3 of 3"');
		expect(body).toContain('width: 100.000%');
	});
});
