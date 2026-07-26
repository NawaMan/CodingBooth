import { render } from '@testing-library/svelte';
import { tick } from 'svelte';
import { beforeEach, describe, expect, it } from 'vitest';
import Spotlight from '../src/lib/components/Spotlight.svelte';
import { blockAnchors } from '../src/lib/stores/blockAnchors';
import { highlightTarget, setHighlight } from '../src/lib/stores/highlightTarget';

// Spotlight reads two module stores — WHICH box (highlightTarget) and WHERE it is
// (blockAnchors) — so a test drives both directly, the same way the note-line
// trigger and a Block's registration do at runtime.
const surface = (root: ParentNode) => root.querySelector('svg.spotlight-surface');
const ring = (root: ParentNode) => root.querySelector('.spotlight-ring');

beforeEach(() => {
	blockAnchors.set(new Map());
	setHighlight(null);
});

describe('Spotlight', () => {
	it('renders nothing until a target is set', async () => {
		const { container } = render(Spotlight);
		await tick();
		expect(surface(container)).toBeNull();
	});

	it('rings the named Block once its box and target are known', async () => {
		blockAnchors.set(new Map([['db', { x: 100, y: 100, width: 200, height: 80 }]]));
		const { container } = render(Spotlight);
		setHighlight('db');
		await tick();

		const r = ring(container);
		expect(r).not.toBeNull();
		// Box grown by the default 14px pad on every side.
		expect(r?.getAttribute('x')).toBe('86');
		expect(r?.getAttribute('y')).toBe('86');
		expect(r?.getAttribute('width')).toBe('228');
		expect(r?.getAttribute('height')).toBe('108');
		// The dim scrim is punched out by a mask, and the overlay never eats a click.
		expect(container.querySelector('mask')).not.toBeNull();
		expect(surface(container)?.getAttribute('style')?.replace(/\s/g, '')).toContain('pointer-events:none');
		expect(container.innerHTML).not.toContain('NaN');
	});

	it('tracks the box when it moves — a ADJUST-mode drag re-anchors the ring', async () => {
		blockAnchors.set(new Map([['db', { x: 100, y: 100, width: 200, height: 80 }]]));
		const { container } = render(Spotlight);
		setHighlight('db');
		await tick();
		expect(ring(container)?.getAttribute('x')).toBe('86');

		// The same mutation a drag makes.
		blockAnchors.set(new Map([['db', { x: 500, y: 300, width: 200, height: 80 }]]));
		await tick();
		expect(ring(container)?.getAttribute('x')).toBe('486');
	});

	it('renders nothing for a name that resolves to no anchor', async () => {
		blockAnchors.set(new Map([['db', { x: 100, y: 100, width: 200, height: 80 }]]));
		const { container } = render(Spotlight);
		setHighlight('nope');
		await tick();
		expect(surface(container)).toBeNull();
	});

	it('clears when the target is set back to null', async () => {
		blockAnchors.set(new Map([['db', { x: 100, y: 100, width: 200, height: 80 }]]));
		const { container } = render(Spotlight);
		setHighlight('db');
		await tick();
		expect(surface(container)).not.toBeNull();

		setHighlight(null);
		await tick();
		expect(surface(container)).toBeNull();
	});

	it('omits the dim scrim when dim is 0 but still rings the box', async () => {
		blockAnchors.set(new Map([['db', { x: 100, y: 100, width: 200, height: 80 }]]));
		const { container } = render(Spotlight, { props: { dim: 0 } });
		setHighlight('db');
		await tick();
		expect(container.querySelector('mask')).toBeNull();
		expect(ring(container)).not.toBeNull();
	});
});
