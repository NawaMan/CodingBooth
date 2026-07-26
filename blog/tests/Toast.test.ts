import { render } from '@testing-library/svelte';
import { tick } from 'svelte';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import Toast from '../src/lib/components/Toast.svelte';
import { blockAnchors } from '../src/lib/stores/blockAnchors';

// Toast is REVEAL-style: it renders nothing until it is both mounted (a client-only
// $effect) and `open`, so every visible-state test awaits a tick to let the mount
// gate flip. Its highlight resolves through blockAnchors — the SAME registry a
// <Connector>/<Spotlight> reads — so a test drives that store directly, exactly as a
// Block's registration does at runtime.
const layer = (root: ParentNode) => root.querySelector('.gp-toast-layer');
const banner = (root: ParentNode) => root.querySelector('.gp-toast');
const ring = (root: ParentNode) => root.querySelector('.gp-toast-ring');

beforeEach(() => {
	blockAnchors.set(new Map());
});
afterEach(() => {
	vi.useRealTimers();
});

describe('Toast', () => {
	it('renders nothing while closed — inert until opened', async () => {
		const { container } = render(Toast, { props: { open: false, text: 'Deployed!' } });
		await tick();
		expect(layer(container)).toBeNull();
	});

	it('shows the banner once mounted and open', async () => {
		const { container } = render(Toast, { props: { open: true, text: 'Deployed!' } });
		await tick();
		expect(banner(container)?.textContent).toContain('Deployed!');
		// A passive cue: the whole layer never eats a click.
		expect(layer(container)?.getAttribute('style')?.replace(/\s/g, '')).toContain(
			'pointer-events:none'
		);
	});

	it('dims around the named Block, growing the punch-out by the pad', async () => {
		blockAnchors.set(new Map([['deploy', { x: 100, y: 100, width: 200, height: 80 }]]));
		const { container } = render(Toast, {
			props: { open: true, text: 'Deployed!', highlight: 'deploy' }
		});
		await tick();

		const r = ring(container);
		expect(r).not.toBeNull();
		// Box grown by the default 14px pad on every side (spotlightRect).
		expect(r?.getAttribute('x')).toBe('86');
		expect(r?.getAttribute('y')).toBe('86');
		expect(r?.getAttribute('width')).toBe('228');
		expect(r?.getAttribute('height')).toBe('108');
		expect(container.querySelector('mask')).not.toBeNull();
		expect(container.querySelector('.gp-toast-scrim')).not.toBeNull();
		expect(container.innerHTML).not.toContain('NaN');
	});

	it('tracks the box when it moves — an ADJUST-mode drag re-anchors the dim', async () => {
		blockAnchors.set(new Map([['deploy', { x: 100, y: 100, width: 200, height: 80 }]]));
		const { container } = render(Toast, {
			props: { open: true, text: 'go', highlight: 'deploy' }
		});
		await tick();
		expect(ring(container)?.getAttribute('x')).toBe('86');

		blockAnchors.set(new Map([['deploy', { x: 500, y: 300, width: 200, height: 80 }]]));
		await tick();
		expect(ring(container)?.getAttribute('x')).toBe('486');
	});

	it('shows a plain banner (no scrim) for a highlight that resolves to no box', async () => {
		const { container } = render(Toast, {
			props: { open: true, text: 'hi', highlight: 'nope' }
		});
		await tick();
		expect(banner(container)).not.toBeNull();
		expect(container.querySelector('mask')).toBeNull();
		expect(container.querySelector('.gp-toast-scrim')).toBeNull();
	});

	it('applies the placement to the layer, falling back to bottom for junk', async () => {
		const top = render(Toast, { props: { open: true, text: 'a', placement: 'top' } });
		await tick();
		expect(top.container.querySelector('.gp-toast-layer--top')).not.toBeNull();

		const bad = render(Toast, {
			props: { open: true, text: 'b', placement: 'middle' as unknown as 'top' }
		});
		await tick();
		expect(bad.container.querySelector('.gp-toast-layer--bottom')).not.toBeNull();
	});

	it('auto-dismisses itself after the duration and calls onclose', async () => {
		vi.useFakeTimers();
		const onclose = vi.fn();
		const { container } = render(Toast, {
			props: { open: true, text: 'Deployed!', duration: 1500, onclose }
		});
		await tick();
		expect(banner(container)).not.toBeNull();

		vi.advanceTimersByTime(1500);
		expect(onclose).toHaveBeenCalledTimes(1);
	});

	it('stays up when duration is 0 (sticky) — no auto-dismiss, no onclose', async () => {
		vi.useFakeTimers();
		const onclose = vi.fn();
		const { container } = render(Toast, {
			props: { open: true, text: 'saving…', duration: 0, onclose }
		});
		await tick();
		expect(banner(container)).not.toBeNull();

		vi.advanceTimersByTime(100000);
		expect(onclose).not.toHaveBeenCalled();
	});
});
