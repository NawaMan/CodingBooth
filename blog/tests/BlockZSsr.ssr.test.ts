// @vitest-environment node
//
// True server-side render of a Block's `z` (svelte/server, no DOM). On the
// server `editing` is always false (canAdjust/adjustMode are off), so the author
// z is the presentation z — a non-zero value must reach the prerendered wrapper's
// z-index, and z=0 must leave the style clean (no stacking context, so a slide's
// Blocks keep painting in DOM order until an author opts one out).
import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';
import Block from '../src/lib/components/Block.svelte';

describe('Block z (SSR)', () => {
	it('prerenders a non-zero z as the wrapper z-index', () => {
		const { body } = render(Block, { props: { z: 5 } });
		expect(body).toContain('z-index:5');
	});

	it('emits no z-index at the default z=0', () => {
		const { body } = render(Block, { props: {} });
		expect(body).not.toContain('z-index');
	});

	it('prerenders a negative z (send-to-back)', () => {
		const { body } = render(Block, { props: { z: -2 } });
		expect(body).toContain('z-index:-2');
	});
});
