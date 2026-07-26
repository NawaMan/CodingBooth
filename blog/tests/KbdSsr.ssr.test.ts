// @vitest-environment node
//
// True server-side render of Kbd (svelte/server, no DOM). It is purely
// declarative apart from `platform="auto"` — no browser APIs — so its full markup
// must come from props alone, which is what prerendering a slide (or building a
// Text artifact) does. This locks in the <kbd> nesting, the platform legends, and
// the one thing a server cannot know: whose keyboard the reader has.
import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';
import Kbd from '../src/lib/components/Kbd.svelte';

describe('Kbd (SSR)', () => {
	it('renders a chord as nested <kbd>: one for the input, one per key', () => {
		const { body } = render(Kbd, { props: { keys: 'Ctrl+K' } });
		expect(body).toContain('>Ctrl</kbd>');
		expect(body).toContain('>K</kbd>');
		expect(body).toContain('class="chord');
		// The `+` is punctuation between the caps, never a cap of its own.
		expect(body).toContain('class="join');
	});

	it('a sequence prerenders both chords with the "then" between them', () => {
		const { body } = render(Kbd, { props: { keys: 'Ctrl+K Ctrl+S' } });
		expect(body).toContain('>S</kbd>');
		expect(body).toContain('>then</span>');
		expect(body.match(/class="chord/g)).toHaveLength(2);
	});

	it('platform="mac" swaps in the glyphs and drops the chord joiner', () => {
		const { body } = render(Kbd, { props: { keys: 'Mod+Shift+P', platform: 'mac' } });
		expect(body).toContain('⌘');
		expect(body).toContain('⇧');
		expect(body).not.toContain('class="join');
	});

	it('symbols={false} keeps the words and brings the joiner back', () => {
		const { body } = render(Kbd, { props: { keys: 'Mod+Shift+P', platform: 'mac', symbols: false } });
		expect(body).toContain('>Cmd</kbd>');
		expect(body).not.toContain('⌘');
		expect(body).toContain('class="join');
	});

	it('glyph caps are decorative — the root speaks the shortcut instead', () => {
		const mac = render(Kbd, { props: { keys: 'Mod+Shift+P', platform: 'mac' } });
		expect(mac.body).toContain('aria-label="Cmd Shift P"');
		expect(mac.body).toContain('aria-hidden="true"');

		// Word caps read correctly on their own, so they keep their <kbd> semantics.
		const pc = render(Kbd, { props: { keys: 'Mod+Shift+P' } });
		expect(pc.body).not.toContain('aria-label');
		expect(pc.body).not.toContain('aria-hidden');
	});

	it('platform="auto" prerenders as `pc` — a server has no navigator to ask', () => {
		const { body } = render(Kbd, { props: { keys: 'Mod+K', platform: 'auto' } });
		expect(body).toContain('>Ctrl</kbd>');
		expect(body).not.toContain('⌘');
	});

	it('`join` overrides the platform separator', () => {
		const { body } = render(Kbd, { props: { keys: 'Ctrl+K', join: ' ' } });
		expect(body).not.toContain('>+</span>');
	});

	it('a junk or empty spec (and no slot) renders no keycap, not a blank one', () => {
		// Svelte leaves its hydration anchors behind either way; what must not survive
		// is any element — an empty <kbd> is a key the audience cannot press.
		for (const keys of ['', '   ']) {
			const { body } = render(Kbd, { props: { keys } });
			expect(body).not.toContain('<kbd');
			expect(body).not.toContain('<span');
		}
	});
});
