// @vitest-environment node
//
// Prerender guarantee for Polyline: rendered through svelte/server (server
// compile, no DOM), the stroke must come out as static markup from props
// alone, and NONE of the ADJUST editing chrome — which is gated on a mode no
// server render is in — may leak into a published, prerendered slide.
import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';
import PolylineEditHost from './PolylineEditHost.svelte';

describe('Polyline (SSR)', () => {
	it('renders the smooth stroke server-side, with no editing chrome', () => {
		const { body } = render(PolylineEditHost, { props: {} });
		expect(body).toContain('class="draw-polyline');
		expect(body).toContain('d="M 100 900 C '); // Catmull-Rom starts at the first point
		expect(body).toContain('stroke-linejoin="round"');
		expect(body).not.toContain('NaN');
		// Editing chrome is ADJUST-only — never in a prerender.
		expect(body).not.toContain('draw-handle');
		expect(body).not.toContain('draw-hit');
		expect(body).not.toContain('draw-chrome');
	});
});
