// @vitest-environment node
//
// Prerender guarantee for `upright`: the level pose + horizontal mirror are
// pure CSS (a scaleX(-1) folded into the transform), so they must render from
// props alone through svelte/server — and a default (non-upright) sprite must
// carry NO scaleX, proving the flag is truly opt-in.
import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';
import DrawSpriteUprightHost from './DrawSpriteUprightHost.svelte';

describe('Sprite upright (SSR)', () => {
	it('upright prerenders the level pose and the mirror keyframes', () => {
		const { body } = render(DrawSpriteUprightHost, { props: { upright: true } });
		expect(body).toContain('@keyframes draw-sprite-');
		expect(body).toContain('scaleX(-1)'); // the mirror on the rightward leg
		expect(body).toContain('rotate(0deg)'); // level — no banking
		expect(body).not.toContain('NaN');
	});

	it('default (no upright) ships NO mirror — the flag is opt-in', () => {
		const { body } = render(DrawSpriteUprightHost, { props: { upright: false } });
		expect(body).toContain('@keyframes draw-sprite-');
		expect(body).not.toContain('scaleX');
	});
});
