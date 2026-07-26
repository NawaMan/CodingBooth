// Sprite POLYLINE path mode — `path={{ kind: 'polyline', points }}` flies a
// waypoint route: straight legs whose heading SNAPS at every corner (no
// continuous tangent exists there), sampled by arc length into the same
// generated CSS keyframes as every other path kind. The ADJUST editor is one
// handle PER WAYPOINT — no from/to, no control guides, no keyframe panel.
// A named <Polyline> can also be ridden by reference; it draws no editor of
// its own, so the rider must grow none either.
import { render } from '@testing-library/svelte';
import { tick } from 'svelte';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { undo, redo } from '../src/lib/stores/adjustHistory';
import { canAdjust, adjustMode } from '../src/lib/stores/adjustMode';
import DrawSpritePolylineHost from './DrawSpritePolylineHost.svelte';
import DrawSpritePolylineRefHost from './DrawSpritePolylineRefHost.svelte';

const moveTo = (clientX: number, clientY: number) =>
	window.dispatchEvent(new MouseEvent('pointermove', { clientX, clientY }));
const release = () => window.dispatchEvent(new MouseEvent('pointerup'));

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

describe('Sprite polyline path rendering', () => {
	beforeEach(() => {
		canAdjust.set(false);
		adjustMode.set(false);
	});

	it('base pose centres the box on the first waypoint', () => {
		const { container } = render(DrawSpritePolylineHost);
		const el = spriteEl(container);
		// First waypoint [100, 900], size 80 → box top-left = centre − half size.
		expect(el.style.left).toBe('60px');
		expect(el.style.top).toBe('860px');
		expect(el.textContent?.trim()).toBe('ZIG');
	});

	it('samples the route into keyframes that end exactly on the LAST waypoint', () => {
		const { container } = render(DrawSpritePolylineHost);
		const css = keyframeStyle(container);
		expect(css.match(/left:/g)).toHaveLength(41); // default samples=40 → 41 frames
		expect(css).toContain('100% { left:1260px; top:460px;'); // [1300, 500] − 40
		expect(css).not.toContain('NaN');
		expect(spriteEl(container).style.animation).toContain('draw-sprite-');
	});

	it('the heading SNAPS between leg angles — two values, never a blend', () => {
		const { container } = render(DrawSpritePolylineHost);
		const css = keyframeStyle(container);
		const rots = [...css.matchAll(/rotate\((-?\d+)deg\)/g)].map((m) => Number(m[1]));
		expect(rots).toHaveLength(41);
		// Three straight legs alternating up-right (rot 45) / down-right (rot 135):
		// every frame carries one of the two leg headings — a corner snaps, so no
		// intermediate angle ever appears (contrast the curve test's >5 values).
		expect(new Set(rots)).toEqual(new Set([45, 135]));
	});

	it('frames stride uniformly by DISTANCE across all legs', () => {
		const { container } = render(DrawSpritePolylineHost);
		const css = keyframeStyle(container);
		const frames = [...css.matchAll(/left:(-?\d+)px; top:(-?\d+)px;.*?rotate\((-?\d+)deg\)/g)].map(
			(m) => ({ p: [Number(m[1]), Number(m[2])] as const, rot: Number(m[3]) })
		);
		expect(frames).toHaveLength(41);
		// Same-leg strides only: a pair straddling a corner is legitimately
		// SHORTER in euclidean terms (the chord cuts the corner) even though the
		// stride ALONG the path is constant — so compare within a heading.
		const steps: number[] = [];
		for (let i = 1; i < frames.length; i++) {
			if (frames[i].rot !== frames[i - 1].rot) continue; // corner straddle
			steps.push(
				Math.hypot(frames[i].p[0] - frames[i - 1].p[0], frames[i].p[1] - frames[i - 1].p[1])
			);
		}
		const spread = Math.max(...steps) / Math.min(...steps);
		expect(spread).toBeLessThan(1.15); // integer-px rounding noise only
	});
});

describe('Sprite polyline path editing (ADJUST)', () => {
	beforeEach(() => {
		canAdjust.set(true);
		adjustMode.set(true);
	});
	afterEach(() => {
		canAdjust.set(false);
		adjustMode.set(false);
	});

	it('selecting reveals ONE handle per waypoint — no guides, no keyframe panel', async () => {
		const { container } = render(DrawSpritePolylineHost);
		expect(container.querySelector('.sprite-path')).not.toBeNull();
		await grab(container.querySelector('.draw-hit')!);
		expect(container.querySelectorAll('.draw-handle')).toHaveLength(4); // 4 waypoints
		expect(container.querySelectorAll('.draw-guide')).toHaveLength(0);
		expect(container.querySelector('.tb-keyframes')).toBeNull();
	});

	it('dragging a waypoint re-routes the flight live; undo/redo walk it', async () => {
		const { container } = render(DrawSpritePolylineHost);
		await grab(container.querySelector('.draw-hit')!);
		// Handles render in waypoint order — first is [100, 900].
		const first = container.querySelectorAll('.draw-handle')[0];
		await grab(first, 0, 0);
		moveTo(100, -100); // +100x, −100y at scale 1 → waypoint [200, 800]
		release();
		await tick();
		// The base pose re-sampled from the NEW route: centre [200, 800] − 40.
		expect(spriteEl(container).style.left).toBe('160px');
		expect(spriteEl(container).style.top).toBe('760px');
		expect(keyframeStyle(container)).toContain('left:160px; top:760px;');

		undo();
		await tick();
		expect(spriteEl(container).style.left).toBe('60px');
		redo();
		await tick();
		expect(spriteEl(container).style.left).toBe('160px');
	});
});

describe('Sprite path="name" riding a named Polyline', () => {
	beforeEach(() => {
		canAdjust.set(false);
		adjustMode.set(false);
	});

	it('rides the Polyline: base pose on ITS first point, keyframes end on ITS last', () => {
		const { container } = render(DrawSpritePolylineRefHost);
		const el = spriteEl(container);
		expect(el.style.left).toBe('60px'); // [100, 900] − 40
		expect(el.style.top).toBe('860px');
		const css = keyframeStyle(container);
		expect(css).toContain('100% { left:860px; top:860px;'); // [900, 900] − 40
		expect(css).not.toContain('NaN');
		// The route itself renders as the Polyline's smooth stroke.
		expect(container.querySelector('.draw-polyline')).not.toBeNull();
	});

	it('the rider itself grows NO editor — the named Polyline is the editor', async () => {
		canAdjust.set(true);
		adjustMode.set(true);
		try {
			const { container } = render(DrawSpritePolylineRefHost);
			await tick();
			// The sprite adds no ghost path of its own; the ONE hit stroke belongs
			// to the Polyline (now a selectable shape), not the rider.
			expect(container.querySelectorAll('.sprite-path')).toHaveLength(0);
			expect(container.querySelectorAll('.draw-hit')).toHaveLength(1);
		} finally {
			canAdjust.set(false);
			adjustMode.set(false);
		}
	});

	it("dragging the named Polyline's waypoint re-routes the rider live; undo walks it", async () => {
		canAdjust.set(true);
		adjustMode.set(true);
		try {
			const { container } = render(DrawSpritePolylineRefHost);
			// Select the Polyline via its own hit stroke; its chrome is one handle
			// per waypoint (route is [[100,900],[500,500],[900,900]]).
			await grab(container.querySelector('.draw-hit')!);
			const handles = container.querySelectorAll('.draw-handle');
			expect(handles).toHaveLength(3);
			// Drag the FIRST waypoint [100, 900] → [200, 800]; the rider starts there.
			await grab(handles[0], 0, 0);
			moveTo(100, -100);
			release();
			await tick();
			expect(spriteEl(container).style.left).toBe('160px'); // [200, 800] − 40
			expect(spriteEl(container).style.top).toBe('760px');
			expect(keyframeStyle(container)).toContain('left:160px; top:760px;');

			undo();
			await tick();
			expect(spriteEl(container).style.left).toBe('60px');
		} finally {
			canAdjust.set(false);
			adjustMode.set(false);
		}
	});
});
