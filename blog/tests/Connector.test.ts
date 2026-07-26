import { render } from '@testing-library/svelte';
import { tick } from 'svelte';
import { get } from 'svelte/store';
import { beforeEach, describe, expect, it } from 'vitest';
import ConnectorHost from './ConnectorHost.svelte';
import { blockAnchors } from '../src/lib/stores/blockAnchors';

// The live half of Connector: named Blocks publish their boxes to the anchor
// registry, and the arrow re-routes whenever one of them moves — which is the
// whole point of naming instead of hardcoding coordinates. (The prerender half
// is in ConnectorSsr.ssr.test.ts.)

const shaft = (root: ParentNode) => root.querySelector('path.connector-shaft, .connector path');
const d = (root: ParentNode) => shaft(root)?.getAttribute('d') ?? '';

beforeEach(() => blockAnchors.set(new Map()));

describe('Connector', () => {
	it('registers each named Block and routes between their facing borders', async () => {
		const { container } = render(ConnectorHost);
		await tick();

		expect([...get(blockAnchors).keys()].sort()).toEqual(['api', 'db']);
		expect(get(blockAnchors).get('api')).toEqual({ x: 100, y: 100, width: 200, height: 100 });
		// api's right edge (300) to db's left edge (500), level at y=150.
		expect(d(container)).toBe('M 300 150 L 500 150');
	});

	it('re-routes when a Block moves — the arrow follows its boxes', async () => {
		const { container, rerender } = render(ConnectorHost);
		await tick();
		expect(d(container)).toBe('M 300 150 L 500 150');

		// The same mutation a ADJUST-mode drag makes: push db down and right, so
		// it now sits below api and the shaft has to leave through a new border.
		await rerender({ dbX: 700, dbY: 600 });
		await tick();

		const after = d(container);
		expect(after).not.toBe('M 300 150 L 500 150');
		expect(after).not.toContain('NaN');
		// A straight route attaches where the ray crosses, not at a side midpoint:
		// the shaft now leaves api through its bottom edge (y=200) off-center at
		// x=260, and enters db through its top edge (y=600) off-center at x=740.
		expect(after).toBe('M 260 200 L 740 600');
	});

	it('withdraws an anchor when its Block unmounts, and the arrow disappears', async () => {
		const { container, rerender } = render(ConnectorHost);
		await tick();
		expect(shaft(container)).not.toBeNull();

		await rerender({ showDb: false });
		await tick();

		expect(get(blockAnchors).has('db')).toBe(false);
		expect(shaft(container)).toBeNull();
		// ...and it comes back when the Block does.
		await rerender({ showDb: true });
		await tick();
		expect(shaft(container)).not.toBeNull();
	});

	it('never eats pointer input: the overlay is transparent to clicks', async () => {
		const { container } = render(ConnectorHost);
		await tick();
		const svg = container.querySelector('svg.connector-surface') as SVGSVGElement;
		expect(svg.style.pointerEvents).toBe('none');
	});

	it('draws the visible label and re-places it as the boxes move', async () => {
		const { container, rerender } = render(ConnectorHost);
		await tick();
		const text = container.querySelector('text.connector-label') as SVGTextElement;
		expect(text.textContent).toBe('query');
		// Midpoint of the shaft, lifted labelOffset=20 above a rightward heading.
		expect([text.getAttribute('x'), text.getAttribute('y')]).toEqual(['400', '130']);

		await rerender({ dbX: 900 });
		await tick();
		expect(text.getAttribute('x')).toBe('600');
	});

	it('routes ortho through right angles and curve through a cubic', async () => {
		const { container, rerender } = render(ConnectorHost, { props: { dbY: 600 } });
		await tick();

		await rerender({ route: 'ortho' });
		await tick();
		expect(d(container)).toContain(' Q '); // rounded elbow corners

		await rerender({ route: 'curve' });
		await tick();
		expect(d(container)).toContain(' C ');
	});
});
