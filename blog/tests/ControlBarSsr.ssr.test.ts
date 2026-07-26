// @vitest-environment node
//
// True server-side render of ControlBar (svelte/server, no DOM). Like <SlideToolbar> and
// <Annotate>, the ControlBar is live chrome that must be SSR-INERT: it is `browser`-gated, so a
// prerendered slide ships no bar, no Table of Contents trigger and no pager — none of it belongs
// in the static HTML of a deck built on a dev machine, and the pager's buttons do nothing without
// JS anyway.
import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';
import ControlBar from '../src/lib/components/ControlBar.svelte';

describe('ControlBar (SSR)', () => {
	it('prerenders NOTHING — no bar, no separators', () => {
		const { body } = render(ControlBar, { props: {} });
		expect(body).not.toContain('ctrl-bar');
	});
});
