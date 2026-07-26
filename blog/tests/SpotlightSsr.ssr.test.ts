// @vitest-environment node
//
// True server-side render of Spotlight (svelte/server, no DOM). The load-bearing
// fact: at prerender NOTHING is highlighted (the store is a runtime, per-window
// concern the presenter drives), so a prerendered slide must ship no overlay —
// no stray box, no dim scrim over the deck. We also prove that WHEN a target is
// set the geometry reaches the markup (so the derived path is SSR-safe), which is
// what a Text artifact driving setHighlight in flow would rely on.
import { render } from 'svelte/server';
import { beforeEach, describe, expect, it } from 'vitest';
import Spotlight from '../src/lib/components/Spotlight.svelte';
import { blockAnchors } from '../src/lib/stores/blockAnchors';
import { setHighlight } from '../src/lib/stores/highlightTarget';

// Module state, no onDestroy on the server — reset both stores per test.
beforeEach(() => {
	blockAnchors.set(new Map());
	setHighlight(null);
});

describe('Spotlight (SSR)', () => {
	it('renders nothing when no target is set — inert at prerender', () => {
		const { body } = render(Spotlight, { props: {} });
		expect(body).not.toContain('spotlight-surface');
		expect(body).not.toContain('<svg');
	});

	it('renders nothing for a target with no registered box', () => {
		setHighlight('db'); // no anchor for it
		const { body } = render(Spotlight, { props: {} });
		expect(body).not.toContain('spotlight-surface');
	});

	it('rings the box and dims the rest once a target resolves', () => {
		blockAnchors.set(new Map([['db', { x: 100, y: 100, width: 200, height: 80 }]]));
		setHighlight('db');
		const { body } = render(Spotlight, { props: {} });
		expect(body).toContain('spotlight-surface');
		expect(body).toContain('pointer-events:none');
		expect(body).toContain('viewBox="0 0 1920 1080"');
		expect(body).toContain('spotlight-ring');
		expect(body).toContain('<mask');
		expect(body).not.toContain('NaN');
	});
});
