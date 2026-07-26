// @vitest-environment node
//
// True server-side render of the Draw family (svelte/server, no DOM): the
// node environment gets vitest's SSR transform, so the components compile in
// server mode — proving every shape emits its complete SVG markup from props
// alone, which is what prerendering a slide does. (The slides deck itself
// gates slide content behind onMount in SlideDeck, so the deck's built HTML
// can't demonstrate this — this test is the prerender guarantee.)
import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';
import DrawSsrHost from './DrawSsrHost.svelte';

describe('Draw (SSR)', () => {
	it('renders the full SVG markup server-side from props alone', () => {
		const { body } = render(DrawSsrHost, { props: {} });
		expect(body).toContain('viewBox="0 0 1920 1080"');
		expect(body).toContain('<title>Request flow</title>');
		expect(body).toContain('d="M 510 770 L 1386 770"'); // arrowed shaft, shortened behind the head
		expect(body).toContain('<polygon'); // the arrowhead
		expect(body).toContain('stroke-dasharray="12 8"'); // the dashed line
		expect(body).toContain('rx="16"'); // the rounded Rect
		expect(body).toContain('<ellipse'); // the Ellipse
		expect(body).toContain('cx="960"'); // the raw-SVG escape hatch
		expect(body).toContain('d="M 200 200 C '); // the cubic Curve (shaft trimmed for its arrow)
		expect(body).toContain('"900,700 '); // …whose head tip still lands exactly on `to`
		expect(body).toContain('A 623.33 623.33 0 0 1 1500 540'); // the Arc from bend=0.3
		expect(body).toContain('>round trip</text>'); // the visible Arc label
		// The multi-segment Path: line → curve → arc, all in ONE continuous <path>
		// (the redundant Ms dropped so the chain is a single sub-path).
		expect(body).toContain('d="M 200 300 L 500 300 Q 650 300 800 150 '); // line then quadratic, no second M
		expect(body).toContain('1150,150'); // its end arrowhead tip lands exactly on the last `to`
		expect(body).toContain('>route</text>'); // the Path's visible label
		expect(body).toContain('stroke-linejoin="round"'); // clean joins, not butting caps
		// The animated Path: geometry keyframes prerender as sampled d:path() frames.
		expect(body).toContain('@keyframes draw-move-'); // its morph keyframes, server-side
		expect(body).toContain('d: path("M 100 460 '); // a sampled pose (raw via @html)
		expect(body).toContain('pathLength="1"'); // draw-on plumbing, CSS-only
		expect(body).toContain('animation-duration:1.5s'); // …with its duration inline
		expect(body).toContain('<foreignObject'); // the Sprite's moving HTML element
		expect(body).toContain('@keyframes draw-sprite-'); // …driven by generated CSS
		expect(body).toContain('transform:rotate(20deg);'); // …the 0% pose, server-side
		expect(body).toContain('>ROCKET<'); // …with its slot content
		expect(body).not.toContain('NaN');
	});

	it('ships no editing chrome — neither at home nor in the select-to-front layer', () => {
		const { body } = render(DrawSsrHost, { props: {} });
		// Editing chrome is gated on ADJUST, which no server render is in. Worth
		// pinning for the hoisted layer in particular: it is the one piece of
		// chrome <Draw> renders ITSELF, rather than a shape rendering its own, so
		// a stray `hoisted` would put handles in a published, prerendered slide.
		expect(body).not.toContain('draw-chrome');
		expect(body).not.toContain('draw-handle');
		expect(body).not.toContain('draw-hit');
	});
});
