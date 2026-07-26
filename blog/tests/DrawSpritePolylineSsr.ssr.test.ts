// @vitest-environment node
//
// Prerender guarantee for the Sprite polyline path mode: rendered through
// svelte/server (server compile, no DOM), the whole flight must come out as
// static markup — base pose, generated @keyframes, the ridden Polyline's
// stroke — from props alone. (Built deck HTML can't show this: SlideDeck
// gates slide content behind onMount, so this render IS the evidence.)
import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';
import DrawSpritePolylineHost from './DrawSpritePolylineHost.svelte';
import DrawSpritePolylineRefHost from './DrawSpritePolylineRefHost.svelte';

describe('Sprite polyline path (SSR)', () => {
	it('a literal polyline flight prerenders: base pose + sampled keyframes', () => {
		const { body } = render(DrawSpritePolylineHost, { props: {} });
		expect(body).toContain('@keyframes draw-sprite-');
		expect(body).toContain('left:60px; top:860px;'); // base pose on [100, 900] − 40
		expect(body).toContain('100% { left:1260px; top:460px;'); // ends on [1300, 500] − 40
		expect(body).toContain('>ZIG<'); // the slot content rides along
		expect(body).not.toContain('NaN');
		// No ADJUST chrome in a server render — ever.
		expect(body).not.toContain('draw-handle');
		expect(body).not.toContain('sprite-path');
	});

	it('a named-Polyline rider prerenders: the stroke AND the flight, one geometry', () => {
		const { body } = render(DrawSpritePolylineRefHost, { props: {} });
		// The Polyline's own smooth stroke (Catmull-Rom starts at the first point).
		expect(body).toContain('class="draw-polyline');
		expect(body).toContain('d="M 100 900 C ');
		// The rider sampled the same registered geometry, server-side.
		expect(body).toContain('@keyframes draw-sprite-');
		expect(body).toContain('left:60px; top:860px;');
		expect(body).toContain('100% { left:860px; top:860px;'); // last point [900, 900] − 40
		expect(body).toContain('>RIDER<');
		expect(body).not.toContain('NaN');
	});
});
