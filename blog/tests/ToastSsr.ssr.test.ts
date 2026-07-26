// @vitest-environment node
//
// True server-side render of Toast (svelte/server, no DOM). The load-bearing fact:
// a Toast is a runtime, per-window cue driven on the CLIENT (a build step, a button,
// the presenter console), so a prerendered slide must ship NOTHING — no banner over
// the deck, no dim scrim over the slide — even if the author left it `open` in the
// markup. The reveal is gated behind a client-only mount effect, which svelte/server
// never runs, so the SSR contract is simply: always inert.
import { render } from 'svelte/server';
import { beforeEach, describe, expect, it } from 'vitest';
import Toast from '../src/lib/components/Toast.svelte';
import { blockAnchors } from '../src/lib/stores/blockAnchors';

// Module state, no onDestroy on the server — reset the registry per test.
beforeEach(() => {
	blockAnchors.set(new Map());
});

describe('Toast (SSR)', () => {
	it('renders nothing when closed', () => {
		const { body } = render(Toast, { props: { open: false, text: 'Deployed!' } });
		expect(body).not.toContain('gp-toast');
		expect(body).not.toContain('<svg');
	});

	it('renders nothing even when open — the reveal is client-only', () => {
		const { body } = render(Toast, { props: { open: true, text: 'Deployed!' } });
		expect(body).not.toContain('gp-toast');
	});

	it('renders no dim scrim even when open with a resolved highlight', () => {
		blockAnchors.set(new Map([['deploy', { x: 100, y: 100, width: 200, height: 80 }]]));
		const { body } = render(Toast, {
			props: { open: true, text: 'Deployed!', highlight: 'deploy' }
		});
		expect(body).not.toContain('gp-toast');
		expect(body).not.toContain('<mask');
		expect(body).not.toContain('NaN');
	});
});
