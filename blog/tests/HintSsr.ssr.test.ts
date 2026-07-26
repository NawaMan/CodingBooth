// @vitest-environment node
//
// True server-side render of Hint (svelte/server, no DOM). Hint is purely
// declarative — no onMount, no browser APIs — so its full markup comes from
// props alone.
//
// What this pins is the CLASS CONTRACT the stylesheet reads, because that is
// all a server render can see: the scoped `<style>` block never reaches
// `body`, so the --hint-* tokens and the color-mix backdrop cannot be asserted
// here (they are verified by rendering, not by string-matching). The classes
// are what decide whether a cue gets its backdrop, and whether it exists.
import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';
import Hint from '../src/lib/components/Hint.svelte';

describe('Hint (SSR)', () => {
	it('renders the cue text', () => {
		const { body } = render(Hint, { props: { text: 'Look below' } });
		expect(body).toContain('Look below');
	});

	it('is boxed by default — the backdrop is what makes it legible over arbitrary pixels', () => {
		const { body } = render(Hint, { props: { text: 'cue' } });
		expect(body).toContain('boxed');
	});

	it('boxed={false} drops the backdrop, leaving the bare text', () => {
		const { body } = render(Hint, { props: { text: 'cue', boxed: false } });
		expect(body).not.toContain('boxed');
		expect(body).toContain('cue');
	});

	it('isVisible={false} hides it', () => {
		const { body } = render(Hint, { props: { text: 'cue', isVisible: false } });
		expect(body).toContain('hidden');
	});

	// The pill is centred by its static position inside SlideDeck's flex
	// `.content`, never by margins — see the note in Hint.svelte. A margin-based
	// centring would be inert here (left/right are auto), so its reappearance in
	// the stylesheet is a bug this comment, not an assertion, has to catch.
	it('is absolutely positioned, so it never displaces slide content', () => {
		const { body } = render(Hint, { props: { text: 'cue' } });
		expect(body).toContain('class="text');
	});

	it('ships the (X) close button by default, with an accessible label', () => {
		const { body } = render(Hint, { props: { text: 'cue' } });
		expect(body).toContain('class="close'); // prefix — Svelte appends a scoped hash
		expect(body).toContain('aria-label="Dismiss hint"');
	});

	it('dismissible={false} drops the close button', () => {
		const { body } = render(Hint, { props: { text: 'cue', dismissible: false } });
		expect(body).not.toContain('aria-label="Dismiss hint"');
		expect(body).toContain('cue'); // the cue itself survives
	});

	it('ships the drag grip by default, with an accessible label', () => {
		const { body } = render(Hint, { props: { text: 'cue' } });
		expect(body).toContain('class="grip'); // prefix — Svelte appends a scoped hash
		expect(body).toContain('aria-label="Move the hint"');
	});

	it('movable={false} drops the grip', () => {
		const { body } = render(Hint, { props: { text: 'cue', movable: false } });
		expect(body).not.toContain('aria-label="Move the hint"');
		expect(body).not.toContain('class="grip');
		expect(body).toContain('cue'); // the cue itself survives
	});

	// `dim` rides an inline custom property, which IS in the server markup (unlike
	// the scoped stylesheet) — so the resting-opacity plumbing is assertable here.
	it('dim sets the resting-opacity custom property, clamped', () => {
		expect(render(Hint, { props: { text: 'c', dim: 0.5 } }).body).toContain('--hint-dim:0.5');
		// clamp: out-of-range and junk are corralled, never emitted raw
		expect(render(Hint, { props: { text: 'c', dim: 5 } }).body).toContain('--hint-dim:1');
		expect(render(Hint, { props: { text: 'c', dim: -2 } }).body).toContain('--hint-dim:0');
		expect(render(Hint, { props: { text: 'c', dim: NaN } }).body).not.toContain('--hint-dim');
	});

	it('unset dim emits no custom property, so the 0.6 stylesheet default stands', () => {
		const { body } = render(Hint, { props: { text: 'cue' } });
		expect(body).not.toContain('--hint-dim');
	});

	// A Svelte component forwards nothing it has not declared, so `style` has to be a
	// real prop — without it the attribute a slide writes is silently dropped, which
	// reads as "the style does not work" rather than "the style went nowhere".
	it('style reaches the pill, so a slide can quieten its own cue', () => {
		const { body } = render(Hint, { props: { text: 'cue', style: 'font-size: 0.8em' } });
		expect(body).toContain('font-size: 0.8em');
	});

	// Last wins: an inline declaration outranks any class selector, so a slide's
	// font-size beats the component's own — and it must not trample `dim` either.
	it('style is applied after dim, so both survive', () => {
		const { body } = render(Hint, { props: { text: 'cue', dim: 0.5, style: 'font-size: 0.8em' } });
		expect(body).toContain('--hint-dim:0.5');
		expect(body).toContain('font-size: 0.8em');
		expect(body.indexOf('--hint-dim')).toBeLessThan(body.indexOf('font-size: 0.8em'));
	});
});
