// @vitest-environment node
//
// True server-side render of the appendix pair (svelte/server, no DOM).
//
// Why this is asserted HERE rather than against built HTML: SlideDeck gates SSR,
// so a built slide page contains the deck shell and nothing of the slide itself —
// there is no markup in `docs/` to grep. Prerender-safety therefore has to be
// proven through svelte/server, which is what this file does (the house pattern:
// tests/*.ssr.test.ts).
//
// What it buys: both halves must render on the server WITHOUT a DOM. Neither may
// reach for `window` to work out where it is — AppendixLink derives the return
// address from `$page`, and AppendixPage reads it back out of the URL's query — so
// the href and the RETURN control exist in the first render, not on hydration.
import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';
import AppendixSsrHost from './AppendixSsrHost.svelte';

// The $app/stores stub renders at /slides/stub.html, so that is the caller name
// AppendixLink stamps into its href during SSR (see tests/stubs/app-stores.ts).
describe('AppendixLink (SSR) — the way in', () => {
	it('emits a real href carrying the caller as the return address', () => {
		const { body } = render(AppendixSsrHost, { props: { which: 'link' } });
		expect(body).toContain('href="./detail.html?return=stub.html"');
		expect(body).toContain('how the GC actually marks');
	});
});

describe('AppendixPage (SSR) — the slide jumped into', () => {
	it('prerenders as an ordinary slide: header, subtitle and content', () => {
		const { body } = render(AppendixSsrHost, { props: { which: 'appendix' } });
		expect(body).toContain('>How the GC marks</h1>');
		expect(body).toContain('>The long version</span>');
		expect(body).toContain('Tri-colour marking.');
	});

	// It pages like the rest of the deck — the appendix is a chapter, not a dead end —
	// so the deck's own bar is in the prerendered markup, with the way out riding in it.
	it('prerenders the deck’s pager, with its way out in the same bar', () => {
		const { body } = render(AppendixSsrHost, { props: { which: 'appendix' } });
		expect(body).toContain('>NEXT<');
		expect(body).toContain('>PREV<');
		// One bar, not two: the way out sits in the pager's row rather than in a second
		// box of its own somewhere on the canvas.
		expect(body.match(/class="nav/g)?.length).toBe(1);
	});

	// The stub URL carries no `?return=`, which is the direct-link case: the control
	// degrades to DECK rather than leaving the slide with no way out at all.
	it('degrades to the DECK control when the URL names no caller', () => {
		const { body } = render(AppendixSsrHost, { props: { which: 'appendix' } });
		expect(body).toContain('>DECK<');
		expect(body).not.toContain('>RETURN<');
	});
});
