// @vitest-environment node
//
// Server-side render of Steps / Fragment (svelte/server, no DOM). Prerendering a
// slide must still emit every Fragment's markup — the reveal is a client-side CSS
// state, not a server-side omission — so the content is in the HTML from the start
// (and a Fragment used outside a Steps degrades to plain, always-shown content).
import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';
import Steps from '../src/lib/components/Steps.svelte';
import Fragment from '../src/lib/components/Fragment.svelte';

describe('Steps (SSR)', () => {
	it('is layout-transparent: a display:contents wrapper, no box of its own', () => {
		const { body } = render(Steps, { props: {} });
		expect(body).toContain('class="steps');
		expect(body).toContain('display: contents');
	});
});

describe('Fragment (SSR)', () => {
	it('standalone (no Steps) renders shown — content survives prerender', () => {
		const { body } = render(Fragment, { props: {} });
		expect(body).toContain('class="fragment mode-fade');
		expect(body).not.toContain('hidden'); // no Steps → always visible
		expect(body).not.toContain('aria-hidden');
	});

	it('inherits nothing standalone but honours its own transition + tag', () => {
		expect(render(Fragment, { props: { transition: 'fly' } }).body).toContain('mode-fly');
		expect(render(Fragment, { props: { transition: 'scale' } }).body).toContain('mode-scale');
		// `tag` swaps the rendered element so the surrounding markup stays semantic.
		expect(render(Fragment, { props: { tag: 'li' } }).body).toContain('<li');
	});
});
