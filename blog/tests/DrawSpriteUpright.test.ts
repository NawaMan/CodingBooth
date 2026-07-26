// Sprite UPRIGHT mode (opt-in) — a side-view glyph that must never roll onto
// its roof. Instead of `orient`'s tangent banking (which flips a side glyph
// upside down on right-to-left stretches), upright keeps the glyph LEVEL
// (rot = the fixed `rotate`, here 0) and MIRRORS it (scaleX(-1)) to face its
// direction of travel, flipping at each turnaround. The host route runs
// rightward then doubles back leftward, so the mirror must toggle mid-flight.
// Default (no `upright`) must be byte-for-byte the old banking behaviour.
import { render } from '@testing-library/svelte';
import { tick } from 'svelte';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { canAdjust, adjustMode } from '../src/lib/stores/adjustMode';
import DrawSpriteUprightHost from './DrawSpriteUprightHost.svelte';

async function grab(el: Element, clientX = 0, clientY = 0) {
	const ev = new MouseEvent('pointerdown', { clientX, clientY, bubbles: true });
	Object.defineProperty(ev, 'pointerId', { value: 1 });
	el.dispatchEvent(ev);
	await tick();
}

const spriteEl = (c: HTMLElement) => c.querySelector('.sprite-el') as HTMLElement;
const keyframeStyle = (c: HTMLElement) =>
	Array.from(c.querySelectorAll('style'))
		.map((s) => s.textContent ?? '')
		.find((t) => t.includes('@keyframes draw-sprite-')) ?? '';

describe('Sprite upright mode', () => {
	beforeEach(() => {
		canAdjust.set(false);
		adjustMode.set(false);
	});

	it('keeps the glyph LEVEL: every frame is rotate(0deg), never a tangent bank', () => {
		const { container } = render(DrawSpriteUprightHost, { props: { upright: true } });
		const css = keyframeStyle(container);
		const rots = [...css.matchAll(/rotate\((-?\d+)deg\)/g)].map((m) => Number(m[1]));
		expect(rots.length).toBeGreaterThan(10);
		expect(new Set(rots)).toEqual(new Set([0])); // level throughout — no roll
	});

	it('MIRRORS to face travel: scaleX(-1) on the rightward leg, none on the leftward', () => {
		const { container } = render(DrawSpriteUprightHost, { props: { upright: true } });
		const css = keyframeStyle(container);
		const frames = [...css.matchAll(/\{[^}]*\}/g)].map((m) => m[0]);
		const flipped = frames.filter((f) => f.includes('scaleX(-1)')).length;
		// Leg 1 heads rightward (mirrored), leg 2 doubles back leftward (not) — so
		// BOTH kinds appear: the truck turns around at the elbow.
		expect(flipped).toBeGreaterThan(0);
		expect(flipped).toBeLessThan(frames.length);
	});

	it('base pose carries the mirror when the flight starts rightward', () => {
		const { container } = render(DrawSpriteUprightHost, { props: { upright: true } });
		// The route starts [200,500]→[900,900] (rightward) → the 0% pose is flipped.
		expect(spriteEl(container).style.transform).toContain('scaleX(-1)');
		expect(spriteEl(container).style.transform).toContain('rotate(0deg)');
	});

	it('default (no upright) is unchanged: it BANKS (rot varies) and never mirrors', () => {
		const { container } = render(DrawSpriteUprightHost, { props: { upright: false } });
		const css = keyframeStyle(container);
		expect(css).not.toContain('scaleX'); // no mirror in the classic mode
		const rots = [...css.matchAll(/rotate\((-?\d+)deg\)/g)].map((m) => Number(m[1]));
		// Two straight legs → two tangent headings: rot VARIES (banking), unlike
		// upright's constant level pose. (More legs would give more angles; the
		// point is simply that it is not a single constant.)
		expect(new Set(rots).size).toBeGreaterThan(1);
	});
});

describe('Sprite upright serialization (ADJUST Copy)', () => {
	beforeEach(() => {
		canAdjust.set(true);
		adjustMode.set(true);
	});
	afterEach(() => {
		canAdjust.set(false);
		adjustMode.set(false);
	});

	it('Copy emits the `upright` flag so the tag round-trips', async () => {
		const writeText = vi.fn().mockResolvedValue(undefined);
		Object.defineProperty(navigator, 'clipboard', { value: { writeText }, configurable: true });
		const { container } = render(DrawSpriteUprightHost, { props: { upright: true } });
		await grab(container.querySelector('.draw-hit')!); // select the flight path
		(container.querySelector('.draw-toolbar .tb-copy') as HTMLButtonElement).click();
		await tick();
		expect(writeText.mock.calls[0][0]).toContain(' upright');
	});
});
