// @vitest-environment node
//
// True server-side render of Quote (svelte/server, no DOM). Quote is purely
// declarative — no onMount, no browser APIs — so its full markup must come from
// props alone, which is what prerendering a slide does. This locks in the
// text/slot rendering, the footer parts, the image-vs-initials avatar choice, and
// the align/mark/rule class contract the stylesheet reads.
import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';
import Quote from '../src/lib/components/Quote.svelte';

describe('Quote (SSR)', () => {
	it('renders the quotation text, left-aligned with rule + mark by default', () => {
		const { body } = render(Quote, { props: { text: 'Hello world' } });
		expect(body).toContain('Hello world');
		expect(body).toContain('align-left');
		expect(body).toContain('has-rule');
		expect(body).toContain('“'); // decorative opening-quote mark on by default
	});

	it('renders the author and role in the footer', () => {
		const { body } = render(Quote, {
			props: { text: 'x', author: 'Grace Hopper', role: 'Rear Admiral' },
		});
		expect(body).toContain('>Grace Hopper</span>');
		expect(body).toContain('>Rear Admiral</span>');
	});

	it('derives an initials disc from the author when no avatar is given', () => {
		const { body } = render(Quote, { props: { text: 'x', author: 'Grace Hopper' } });
		expect(body).toContain('disc');
		expect(body).toContain('>GH</span>'); // first letters of up to two words
		expect(body).not.toContain('<img');
	});

	it('an avatar URL renders an <img> instead of the initials disc', () => {
		const { body } = render(Quote, {
			props: { text: 'x', author: 'Grace Hopper', avatar: '/a.png' },
		});
		expect(body).toContain('<img');
		expect(body).toContain('src="/a.png"');
		expect(body).toContain('alt="Grace Hopper"');
		expect(body).not.toContain('disc');
	});

	it('align="center" switches the class and (visually) drops the rule', () => {
		const { body } = render(Quote, { props: { text: 'x', align: 'center' } });
		expect(body).toContain('align-center');
		expect(body).not.toContain('align-left');
	});

	it('an unknown align falls back to left rather than emitting a stray class', () => {
		// @ts-expect-error — exercising the runtime fallback on bad input
		const { body } = render(Quote, { props: { text: 'x', align: 'sideways' } });
		expect(body).toContain('align-left');
		expect(body).not.toContain('align-sideways');
	});

	it('mark={false} / rule={false} drop the glyph and the rule class', () => {
		const { body } = render(Quote, {
			props: { text: 'x', mark: false, rule: false },
		});
		expect(body).not.toContain('“');
		expect(body).not.toContain('has-rule');
	});

	it('no author/role/avatar → no footer at all', () => {
		const { body } = render(Quote, { props: { text: 'x' } });
		expect(body).not.toContain('figcaption');
		expect(body).not.toContain('disc');
	});

	it('is unframed by default — no border/background classes', () => {
		const { body } = render(Quote, { props: { text: 'x' } });
		expect(body).not.toContain('framed');
		expect(body).not.toContain('bordered');
	});

	it('border makes it a framed card and sets the radius var', () => {
		const { body } = render(Quote, { props: { text: 'x', border: true, radius: '18px' } });
		expect(body).toContain('framed');
		expect(body).toContain('bordered');
		expect(body).toContain('--quote-radius: 18px');
	});

	it('a background frames it (no border) and drives the fill', () => {
		const { body } = render(Quote, { props: { text: 'x', background: '#12181f' } });
		expect(body).toContain('framed');
		expect(body).not.toContain('bordered'); // background alone doesn't draw a border
		expect(body).toContain('--quote-bg: #12181f');
	});

	it('no background → no bg var (falls to transparent)', () => {
		const { body } = render(Quote, { props: { text: 'x', border: true } });
		expect(body).not.toContain('--quote-bg:');
	});
});
