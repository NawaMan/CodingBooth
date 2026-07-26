// Sprite PATH mode — `path={PathShape}` replaces discrete stops with a real
// curve the component samples internally (pointAt → centre, angleAt → tangent).
// The output is still pure generated CSS keyframes (prerenders, scrubs), but
// the ADJUST editor is the CURVE itself: from/to + control handles like a
// <Curve>'s, re-routing the flight live — no per-stop ghosts, no keyframe panel.
import { render } from '@testing-library/svelte';
import { tick } from 'svelte';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { redo, undo } from '../src/lib/stores/adjustHistory';
import { canAdjust, adjustMode } from '../src/lib/stores/adjustMode';
import DrawSpritePathHost from './DrawSpritePathHost.svelte';
import DrawSpriteRefHost from './DrawSpriteRefHost.svelte';

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

describe('Sprite path mode rendering', () => {
	beforeEach(() => {
		canAdjust.set(false);
		adjustMode.set(false);
	});

	it('base pose centres the box on the path start', () => {
		const { container } = render(DrawSpritePathHost);
		const el = spriteEl(container);
		// from [100, 900], size 80 → box top-left = centre − half size.
		expect(el.style.left).toBe('60px');
		expect(el.style.top).toBe('860px');
		expect(el.style.width).toBe('80px');
		expect(el.style.height).toBe('80px');
		expect(el.textContent?.trim()).toBe('FLIER');
	});

	it('samples the curve into dense keyframes that end exactly on `to`', () => {
		const { container } = render(DrawSpritePathHost);
		const css = keyframeStyle(container);
		// Default samples=40 → 41 frames.
		expect(css.match(/left:/g)).toHaveLength(41);
		expect(css).toContain('0% {');
		expect(css).toContain('50% {');
		// Last frame centres on to [1800, 200]: left 1800−40, top 200−40.
		expect(css).toContain('100% { left:1760px; top:160px;');
		expect(css).not.toContain('NaN');
		// It runs as an ordinary scrubbable CSS animation.
		expect(spriteEl(container).style.animation).toContain('draw-sprite-');
	});

	it('`delay` holds the start pose: the shorthand carries duration THEN delay', () => {
		const { container } = render(DrawSpritePathHost);
		// animation: <name> 3s ease-in-out 1.5s both — second <time> is the delay.
		// The AnimationBar's timeline extends to delay + animate on its own.
		expect(spriteEl(container).style.animation).toMatch(/3s ease-in-out 1\.5s both/);
	});

	it('spaces frames uniformly by DISTANCE, so it tracks a draw-on pen tip', () => {
		// The host cubic is parameter-skewed; uniform-t sampling would sprint and
		// dawdle. Frames must sit at equal arc-length strides instead — that (plus
		// the shared duration + ease-in-out) is what keeps a Sprite glued to a
		// same-duration `draw` stroke's tip.
		const { container } = render(DrawSpritePathHost);
		const css = keyframeStyle(container);
		const pts = [...css.matchAll(/left:(-?\d+)px; top:(-?\d+)px/g)].map(
			(m) => [Number(m[1]), Number(m[2])] as const
		);
		expect(pts).toHaveLength(41);
		const steps = pts.slice(1).map((p, i) => Math.hypot(p[0] - pts[i][0], p[1] - pts[i][1]));
		const spread = Math.max(...steps) / Math.min(...steps);
		expect(spread).toBeLessThan(1.15); // near-equal strides (integer-px rounding noise only)
	});

	it('banks to the tangent: rotation varies across the flight', () => {
		const { container } = render(DrawSpritePathHost);
		const css = keyframeStyle(container);
		const rots = [...css.matchAll(/rotate\((-?\d+)deg\)/g)].map((m) => Number(m[1]));
		expect(rots).toHaveLength(41);
		expect(new Set(rots).size).toBeGreaterThan(5); // genuinely turning, not constant
	});
});

describe('Sprite path mode editing (ADJUST)', () => {
	beforeEach(() => {
		canAdjust.set(true);
		adjustMode.set(true);
	});
	afterEach(() => {
		canAdjust.set(false);
		adjustMode.set(false);
	});

	it('shows the curve as the editor: ghost path + hit stroke, NO stop ghosts', () => {
		const { container } = render(DrawSpritePathHost);
		expect(container.querySelector('.sprite-path')).not.toBeNull();
		expect(container.querySelector('.draw-hit')).not.toBeNull();
		// The generated stops never surface as ghosts or handles.
		expect(container.querySelectorAll('.sprite-hit')).toHaveLength(0);
		expect(container.querySelectorAll('.sprite-box')).toHaveLength(0);
		expect(container.querySelector('.draw-handle')).toBeNull();
	});

	it('selecting reveals from/to/c1/c2 handles with guides — and NO keyframe panel', async () => {
		const { container } = render(DrawSpritePathHost);
		await grab(container.querySelector('.draw-hit')!);
		// A cubic's editor: 2 endpoint + 2 control handles, 2 guide lines.
		expect(container.querySelectorAll('.draw-handle')).toHaveLength(4);
		expect(container.querySelectorAll('.draw-guide')).toHaveLength(2);
		// The stops are generated — no rows of them to edit.
		expect(container.querySelector('.tb-keyframes')).toBeNull();
	});

	it('dragging the `from` handle re-routes the flight live; undo/redo walk it', async () => {
		const { container } = render(DrawSpritePathHost);
		await grab(container.querySelector('.draw-hit')!);
		// Handles render in from/to/c1/c2 order — first is `from` at [100, 900].
		const fromHandle = container.querySelectorAll('.draw-handle')[0];
		await grab(fromHandle, 0, 0);
		moveTo(100, -100); // +100x, −100y at scale 1 → from [200, 800]
		release();
		await tick();
		// The base pose re-sampled from the NEW curve: centre [200, 800] − 40.
		expect(spriteEl(container).style.left).toBe('160px');
		expect(spriteEl(container).style.top).toBe('760px');
		// …and so did the generated keyframes.
		expect(keyframeStyle(container)).toContain('left:160px; top:760px;');

		undo();
		await tick();
		expect(spriteEl(container).style.left).toBe('60px');
		redo();
		await tick();
		expect(spriteEl(container).style.left).toBe('160px');
	});
});

describe('Sprite path="name" (riding a named shape)', () => {
	beforeEach(() => {
		canAdjust.set(false);
		adjustMode.set(false);
	});

	it('rides the named Curve: base pose centres on ITS from, keyframes end on ITS to', () => {
		const { container } = render(DrawSpriteRefHost);
		const el = spriteEl(container);
		// Same geometry as the literal-path host, but owned by the <Curve>.
		expect(el.style.left).toBe('60px');
		expect(el.style.top).toBe('860px');
		const css = keyframeStyle(container);
		expect(css).toContain('100% { left:1760px; top:160px;');
		expect(css).not.toContain('NaN');
	});

	it('`ease` overrides the whole-flight timing function (linear = position ∝ time)', () => {
		const { container } = render(DrawSpriteRefHost);
		expect(spriteEl(container).style.animation).toMatch(/3s linear both/);
	});

	it('an unknown name renders NO flight — never a stranded glyph', () => {
		const { container } = render(DrawSpriteRefHost);
		// Only the resolved rider mounts a moving element; "ghost-road" is absent.
		const els = Array.from(container.querySelectorAll('.sprite-el'));
		expect(els).toHaveLength(1);
		expect(els[0].textContent?.trim()).toBe('RIDER');
	});
});

describe('Sprite path="name" editing (ADJUST)', () => {
	beforeEach(() => {
		canAdjust.set(true);
		adjustMode.set(true);
	});
	afterEach(() => {
		canAdjust.set(false);
		adjustMode.set(false);
	});

	it('the rider grows NO editor of its own — the named shape is the editor', () => {
		const { container } = render(DrawSpriteRefHost);
		// No sprite ghost path, no stop ghosts; the only hit stroke is the Curve's.
		expect(container.querySelectorAll('.sprite-path')).toHaveLength(0);
		expect(container.querySelectorAll('.sprite-hit')).toHaveLength(0);
		expect(container.querySelectorAll('.draw-hit')).toHaveLength(1);
	});

	it("dragging the CURVE's from handle re-routes the rider live; undo walks it back", async () => {
		const { container } = render(DrawSpriteRefHost);
		// Select the Curve via its own hit stroke; its chrome is from/to/c1/c2.
		await grab(container.querySelector('.draw-hit')!);
		const fromHandle = container.querySelectorAll('.draw-handle')[0];
		await grab(fromHandle, 0, 0);
		moveTo(100, -100); // Curve from [100, 900] → [200, 800]
		release();
		await tick();
		// The rider re-sampled from the CURVE's new geometry: centre − half size.
		expect(spriteEl(container).style.left).toBe('160px');
		expect(spriteEl(container).style.top).toBe('760px');
		expect(keyframeStyle(container)).toContain('left:160px; top:760px;');

		undo();
		await tick();
		expect(spriteEl(container).style.left).toBe('60px');
	});
});
