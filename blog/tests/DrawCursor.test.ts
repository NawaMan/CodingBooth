// Cursor — a fake pointer built on a LOCKED Sprite. The flight resolves
// waypoints (Block names or literal points) through the same blockAnchors
// registry Connector reads, so it re-routes with a dragged/removed target,
// and it must grow ZERO ADJUST chrome of its own (the locked Sprite
// underneath is the whole point — nothing to select, list or copy besides
// the <Cursor> tag itself). Prerender coverage is DrawCursorSsr.ssr.test.ts.
import { render } from '@testing-library/svelte';
import { tick } from 'svelte';
import { beforeEach, describe, expect, it } from 'vitest';
import { blockAnchors } from '../src/lib/stores/blockAnchors';
import { canAdjust, adjustMode } from '../src/lib/stores/adjustMode';
import DrawCursorHost from './DrawCursorHost.svelte';
import DrawCursorScriptHost from './DrawCursorScriptHost.svelte';
import DrawCursorTriggerHost from './DrawCursorTriggerHost.svelte';
import DrawCursorAttentionHost from './DrawCursorAttentionHost.svelte';
import DrawCursorPathSizeHost from './DrawCursorPathSizeHost.svelte';
import { lastTrigger, fireTrigger } from '../src/lib/stores/triggers';

const spriteEl = (c: HTMLElement) => c.querySelector('.sprite-el') as HTMLElement | null;
const ripples = (c: HTMLElement) => c.querySelectorAll('circle.cursor-ripple');
const keyframeStyle = (c: HTMLElement) =>
	Array.from(c.querySelectorAll('style'))
		.map((s) => s.textContent ?? '')
		.find((t) => t.includes('@keyframes draw-sprite-')) ?? '';

beforeEach(() => {
	blockAnchors.set(new Map());
	canAdjust.set(false);
	adjustMode.set(false);
});

describe('Cursor rendering', () => {
	it('flies a locked Sprite from a literal point onto the named target', async () => {
		const { container } = render(DrawCursorHost);
		await tick();
		// Base pose (0%): the literal [100, 100] start, box 40 → top-left [80, 80].
		const el = spriteEl(container);
		expect(el).not.toBeNull();
		expect(el!.style.left).toBe('80px');
		expect(el!.style.top).toBe('80px');
		// 100%: target centre (500+100, 300+50) = (600, 350) → top-left [580, 330].
		const css = keyframeStyle(container);
		expect(css).toContain('left:80px; top:80px;');
		expect(css).toContain('100% { left:580px; top:330px;');
		expect(css).not.toContain('NaN');
		expect(el!.style.animation).toContain('draw-sprite-');
	});

	it('flashes a click ripple timed to the arrival, delay + animate·pct included', async () => {
		const { container } = render(DrawCursorHost);
		await tick();
		const rs = ripples(container);
		expect(rs).toHaveLength(1); // only the marked waypoint gets a ripple
		const ring = rs[0] as SVGCircleElement;
		expect(ring.getAttribute('cx')).toBe('600');
		expect(ring.getAttribute('cy')).toBe('350');
		// delay 0.2 + animate 1.5 * pct(1.0, the last of 2 targets) = 1.7s.
		expect(ring.style.animationDelay).toBe('1.7s');
	});

	it('a single-waypoint path is a static cursor — no flight, ripple fires at delay', async () => {
		const { container } = render(DrawCursorHost, { props: { legs: 'one' } });
		await tick();
		// No @keyframes: Sprite needs ≥2 stops to animate.
		expect(keyframeStyle(container)).toBe('');
		const el = spriteEl(container);
		expect(el!.style.left).toBe('580px'); // sitting on the target, box 40
		expect(el!.style.top).toBe('330px');
		const ring = ripples(container)[0] as SVGCircleElement;
		expect(ring.style.animationDelay).toBe('0.2s'); // no flight, so just the hold
	});

	it('re-routes when the named target moves — the flight follows it', async () => {
		const { container, rerender } = render(DrawCursorHost);
		await tick();
		expect(keyframeStyle(container)).toContain('100% { left:580px; top:330px;');

		await rerender({ targetX: 900, targetY: 700 });
		await tick();
		// New centre (900+100, 700+50) = (1000, 750) → top-left [980, 730].
		expect(keyframeStyle(container)).toContain('100% { left:980px; top:730px;');
		expect(ripples(container)[0].getAttribute('cx')).toBe('1000');
	});

	it('drops the whole flight when the named target is unresolved — never a stranded glyph', async () => {
		const { container, rerender } = render(DrawCursorHost, { props: { showTarget: false } });
		await tick();
		expect(spriteEl(container)).toBeNull();
		expect(container.querySelector('.draw-cursor')).toBeNull();
		expect(ripples(container)).toHaveLength(0);

		// ...and it comes back once the Block (re)registers.
		await rerender({ showTarget: true });
		await tick();
		expect(spriteEl(container)).not.toBeNull();
	});

	it('never eats pointer input: the root is aria-hidden and the Sprite surface is inert', async () => {
		const { container } = render(DrawCursorHost);
		await tick();
		expect(container.querySelector('.draw-cursor')?.getAttribute('aria-hidden')).toBe('true');
		const fo = container.querySelector('foreignObject')!;
		expect(fo.style.pointerEvents).toBe('none');
	});
});

describe('Cursor in ADJUST mode', () => {
	beforeEach(() => {
		canAdjust.set(true);
		adjustMode.set(true);
	});

	it('grows zero ADJUST chrome — the locked Sprite is not selectable', async () => {
		const { container } = render(DrawCursorHost);
		await tick();
		expect(container.querySelector('.draw-handle')).toBeNull();
		expect(container.querySelector('.sprite-hit')).toBeNull();
		expect(container.querySelector('.sprite-box')).toBeNull();
		// It still flies.
		expect(spriteEl(container)).not.toBeNull();
	});
});

describe('Cursor — script mode (warpTo/moveTo/around chaining)', () => {
	it('compiles the chain into one flight, resolving a named orbit centre', async () => {
		const { container } = render(DrawCursorScriptHost);
		await tick();
		const el = spriteEl(container);
		expect(el).not.toBeNull();
		// Base pose: the literal warpTo [700, 250], box 40 → top-left [680, 230].
		expect(el!.style.left).toBe('680px');
		expect(el!.style.top).toBe('230px');
		const css = keyframeStyle(container);
		expect(css).not.toBe('');
		expect(css).not.toContain('NaN');
		// One full lap returns to the entry angle: centre (700,350) + (0, -50) → [680, 280].
		expect(css).toContain('100% { left:680px; top:280px;');
	});

	it('flashes exactly one ripple, at the completed lap', async () => {
		const { container } = render(DrawCursorScriptHost);
		await tick();
		const rs = ripples(container);
		expect(rs).toHaveLength(1);
		expect((rs[0] as SVGCircleElement).getAttribute('cx')).toBe('700');
		expect((rs[0] as SVGCircleElement).getAttribute('cy')).toBe('300');
	});

	it('drops the whole script when the named centre is unresolved', async () => {
		const { container, rerender } = render(DrawCursorScriptHost, { props: { showDial: false } });
		await tick();
		expect(spriteEl(container)).toBeNull();

		await rerender({ showDial: true });
		await tick();
		expect(spriteEl(container)).not.toBeNull();
	});
});

describe('Cursor — startOn (note-triggered)', () => {
	beforeEach(() => lastTrigger.set(null));

	it('sits idle at its first pose, paused, with no ripple mounted', async () => {
		const { container } = render(DrawCursorTriggerHost);
		await tick();
		const el = spriteEl(container);
		expect(el).not.toBeNull();
		expect(el!.style.left).toBe('80px'); // [100,100] − size/2
		expect(el!.style.animationPlayState).toBe('paused');
		expect(ripples(container)).toHaveLength(0);
	});

	it('an unrelated trigger name leaves it idle', async () => {
		const { container } = render(DrawCursorTriggerHost);
		await tick();
		fireTrigger('something-else');
		await tick();
		expect(spriteEl(container)!.style.animationPlayState).toBe('paused');
	});

	it('the matching trigger starts it playing, with its ripple now mounted', async () => {
		const { container } = render(DrawCursorTriggerHost);
		await tick();
		fireTrigger('go');
		await tick();
		const el = spriteEl(container);
		expect(el!.style.animationPlayState).not.toBe('paused');
		expect(ripples(container)).toHaveLength(1);
	});

	it('a fresh pulse replays from the top — a new element, not a resume', async () => {
		const { container } = render(DrawCursorTriggerHost);
		await tick();
		fireTrigger('go');
		await tick();
		const first = spriteEl(container);
		fireTrigger('go');
		await tick();
		const second = spriteEl(container);
		expect(second).not.toBeNull();
		expect(second).not.toBe(first); // keyed remount, not the same node resuming
	});

	it('a later, unrelated pulse does not re-pause an already-started Cursor', async () => {
		const { container } = render(DrawCursorTriggerHost);
		await tick();
		fireTrigger('go');
		await tick();
		fireTrigger('something-else');
		await tick();
		expect(spriteEl(container)!.style.animationPlayState).not.toBe('paused');
	});
});

describe('Cursor — attention (a size pulse in place)', () => {
	it('the pulse peak/settle sizes derive from the AMBIENT size, not the Cursor default', async () => {
		const { container } = render(DrawCursorAttentionHost);
		await tick();
		const el = spriteEl(container);
		// Base pose: warpTo set size 60, box top-left = 200 − 30.
		expect(el!.style.left).toBe('170px');
		expect(el!.style.top).toBe('170px');
		expect(el!.style.width).toBe('60px');
		const css = keyframeStyle(container);
		expect(css).toContain('width:90px; height:90px;'); // peak: 60 × 1.5
		expect(css).toContain('100% { left:170px; top:170px; width:60px; height:60px;'); // settles back
		expect(css).not.toContain('NaN');
	});

	it("the pulse's ripple radius scales with the PEAK size, not the ambient one", async () => {
		const { container } = render(DrawCursorAttentionHost);
		await tick();
		const rs = ripples(container);
		expect(rs).toHaveLength(1);
		expect((rs[0] as SVGCircleElement).getAttribute('cx')).toBe('200');
		expect(Number(rs[0].getAttribute('r'))).toBeCloseTo(49.5, 5); // 90 × 0.55
	});

	it('defaults to the arrow glyph, and shape swaps in a dot or ring preset', async () => {
		const arrow = render(DrawCursorAttentionHost);
		await tick();
		expect(arrow.container.querySelector('.cursor-glyph path')).not.toBeNull();

		const dot = render(DrawCursorAttentionHost, { props: { shape: 'dot' } });
		await tick();
		expect(dot.container.querySelector('.cursor-glyph circle')).not.toBeNull();
		expect(dot.container.querySelector('.cursor-glyph path')).toBeNull();

		const ring = render(DrawCursorAttentionHost, { props: { shape: 'ring' } });
		await tick();
		const ringCircle = ring.container.querySelector('.cursor-glyph circle');
		expect(ringCircle?.getAttribute('fill')).toBe('none');
	});

	it('an unknown shape value falls back to the arrow, never a blank glyph', async () => {
		const { container } = render(DrawCursorAttentionHost, {
			props: { shape: 'nonsense' as unknown as 'arrow' }
		});
		await tick();
		expect(container.querySelector('.cursor-glyph path')).not.toBeNull();
	});
});

describe('Cursor — per-waypoint size (path mode)', () => {
	it("a waypoint's own size overrides the shared default just for its stop", async () => {
		const { container } = render(DrawCursorPathSizeHost);
		await tick();
		const el = spriteEl(container);
		expect(el!.style.width).toBe('40px'); // base pose: the shared default
		const css = keyframeStyle(container);
		expect(css).toContain('100% { left:360px; top:60px; width:80px; height:80px;'); // overridden
	});

	it("the ripple at an overridden waypoint scales with ITS size, not the shared default", async () => {
		const { container } = render(DrawCursorPathSizeHost);
		await tick();
		const r = ripples(container)[0] as SVGCircleElement;
		expect(r.getAttribute('cx')).toBe('400');
		expect(Number(r.getAttribute('r'))).toBeCloseTo(44, 5); // 80 × 0.55
	});
});
