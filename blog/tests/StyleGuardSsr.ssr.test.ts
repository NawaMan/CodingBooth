// @vitest-environment node
import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';
import StyleGuardSsrHost from './StyleGuardSsrHost.svelte';

describe('Block style guard (SSR)', () => {
	const { body } = render(StyleGuardSsrHost, { props: {} });

	it('prerenders the box at the PROPS geometry, not the style’s', () => {
		expect(body).toContain('SSR_PINNED_MARKER');
		expect(body).toContain('left:200px');
		// The reserved declaration is stripped before the style is applied, so it
		// never reaches the served HTML — a published deck cannot be caught by the
		// collision at all.
		expect(body).not.toContain('left: 40px');
	});

	it('keeps the cosmetics on both Blocks', () => {
		expect(body).toContain('color: red');
		expect(body).toContain('border: 1px solid red');
	});

	it('ships no ADJUST chrome — the badge is author-facing and must not prerender', () => {
		expect(body).not.toContain('style-warn');
		expect(body).not.toContain('ignored');
	});

	it('emits no NaN or undefined into the served markup', () => {
		expect(body).not.toContain('NaN');
		expect(body).not.toContain('undefined');
	});
});
