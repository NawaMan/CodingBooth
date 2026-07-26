// @vitest-environment node
//
// True server-side render (svelte/server, no DOM) of <Canvas>. The canvas
// pixels are inherently client-only, but the component's hidden finite
// @keyframes CLOCK is declarative CSS — so it PRERENDERS. This proves:
//   1. Canvas renders server-side without touching document/rAF (the draw
//      callback and rAF loop are browser/$effect-gated, so nothing throws).
//   2. The clock's @keyframes + the animated span are in the prerendered HTML,
//      so an enclosing AnimationBar discovers the timeline the moment JS boots
//      (no wait for an onMount injection).
import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';
import CanvasSsrHost from './CanvasSsrHost.svelte';

describe('Canvas (SSR)', () => {
	const { body } = render(CanvasSsrHost, { props: {} });

	it('emits the <canvas> surface server-side', () => {
		expect(body).toContain('<canvas');
	});

	it('prerenders the hidden finite @keyframes clock so the bar finds the timeline', () => {
		// A unique clock name + the linear/both animation shorthand at the chosen
		// duration — a real, finite, seekable CSS animation in the static HTML.
		expect(body).toMatch(/@keyframes gp-canvas-clock-\d+/);
		expect(body).toMatch(/animation:gp-canvas-clock-\d+ 5s linear both/);
	});

	it('never runs draw() on the server (no NaN/Infinity leaking into output)', () => {
		expect(body).not.toContain('NaN');
		expect(body).not.toContain('Infinity');
	});
});
