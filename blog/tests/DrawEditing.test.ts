// ADJUST-mode editing (DRAW-3): the DrawHandle primitive and, in later
// suites, per-shape handles + the selection/Copy toolbar. jsdom has no
// PointerEvent/getBoundingClientRect layout, so the live scale falls back to
// 1 (screen px == canvas px) — which is exactly what the math expects here.
import { render } from '@testing-library/svelte';
import { get } from 'svelte/store';
import { tick } from 'svelte';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import DrawHandle from '../src/lib/draw/DrawHandle.svelte';
import type { Point } from '../src/lib/draw/types';
import { shapeChanges } from '../src/lib/stores/adjustChanges';
import { redo, undo } from '../src/lib/stores/adjustHistory';
import { canAdjust, adjustMode } from '../src/lib/stores/adjustMode';
import DrawEditHost from './DrawEditHost.svelte';
import PathHost from './PathHost.svelte';

const moveTo = (clientX: number, clientY: number, init: MouseEventInit = {}) =>
	window.dispatchEvent(new MouseEvent('pointermove', { clientX, clientY, ...init }));
const release = () => window.dispatchEvent(new MouseEvent('pointerup'));
const escape = () => window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));

// A shape's editing chrome (guide lines + handles) sits inside its own <g>
// until the shape is SELECTED — at which point Draw re-parents that chrome into
// the surface's top layer, so its handles out-rank every other shape's stroke
// and handles (select-to-front; SVG has no z-index). Chrome is therefore
// addressed by its OWNER, never by where it currently sits: the wrapper carries
// data-shape and matches in either home.
const handlesOf = (c: HTMLElement, shape: string, kind = '') =>
	c.querySelectorAll(`g.draw-chrome[data-shape="${shape}"] circle.draw-handle${kind}`);
const guidesOf = (c: HTMLElement, shape: string) =>
	c.querySelectorAll(`g.draw-chrome[data-shape="${shape}"] .draw-guide`);

// jsdom has no PointerEvent and fireEvent.pointerDown drops the coordinates;
// a bubbling MouseEvent with a pointerId reaches Svelte's delegated handler
// with everything trackPointer reads.
async function grab(circle: Element, clientX = 0, clientY = 0) {
	const ev = new MouseEvent('pointerdown', { clientX, clientY, bubbles: true });
	Object.defineProperty(ev, 'pointerId', { value: 1 });
	circle.dispatchEvent(ev);
	await tick();
}

describe('DrawHandle', () => {
	it('renders an SVG knob at the point', () => {
		const { container } = render(DrawHandle, {
			point: [100, 200] as Point,
			onmove: () => {}
		});
		const circle = container.querySelector('circle')!;
		expect(circle.getAttribute('cx')).toBe('100');
		expect(circle.getAttribute('cy')).toBe('200');
		expect(circle.getAttribute('class')).toContain('draw-handle');
	});

	it('drags: streams snapped points, commits before → after on release', async () => {
		const moves: Point[] = [];
		const oncommit = vi.fn();
		const { container } = render(DrawHandle, {
			point: [100, 100] as Point,
			onmove: (p: Point) => moves.push(p),
			oncommit
		});
		await grab(container.querySelector('circle')!);
		moveTo(30, -10);
		release();
		expect(moves).toEqual([[130, 90]]);
		expect(oncommit).toHaveBeenCalledWith([100, 100], [130, 90]);
	});

	it('grid snapping quantizes the dragged point', async () => {
		const moves: Point[] = [];
		const { container } = render(DrawHandle, {
			point: [100, 100] as Point,
			grid: 20,
			onmove: (p: Point) => moves.push(p)
		});
		await grab(container.querySelector('circle')!);
		moveTo(28, 7);
		release();
		expect(moves).toEqual([[120, 100]]);
	});

	it('Shift routes through the shiftSnap hook', async () => {
		const moves: Point[] = [];
		const { container } = render(DrawHandle, {
			point: [0, 0] as Point,
			shiftSnap: ([x]: Point) => [x, 0] as Point, // pin to horizontal
			onmove: (p: Point) => moves.push(p)
		});
		await grab(container.querySelector('circle')!);
		moveTo(50, 30, { shiftKey: true });
		release();
		expect(moves).toEqual([[50, 0]]);
	});

	it('Esc cancels: restores the start point and never commits', async () => {
		const moves: Point[] = [];
		const oncommit = vi.fn();
		const { container } = render(DrawHandle, {
			point: [100, 100] as Point,
			onmove: (p: Point) => moves.push(p),
			oncommit
		});
		await grab(container.querySelector('circle')!);
		moveTo(50, 50);
		escape();
		expect(moves).toEqual([
			[150, 150],
			[100, 100] // restored
		]);
		expect(oncommit).not.toHaveBeenCalled();
	});

	it('a click that does not move commits nothing', async () => {
		const oncommit = vi.fn();
		const onselect = vi.fn();
		const { container } = render(DrawHandle, {
			point: [100, 100] as Point,
			onmove: () => {},
			oncommit,
			onselect
		});
		await grab(container.querySelector('circle')!);
		release();
		expect(oncommit).not.toHaveBeenCalled();
		expect(onselect).toHaveBeenCalledTimes(1); // pointerdown still selects
	});
});

describe('Line editing (ADJUST mode)', () => {
	beforeEach(() => {
		canAdjust.set(true);
		adjustMode.set(true);
	});
	afterEach(() => {
		canAdjust.set(false);
		adjustMode.set(false);
	});

	const handles = (c: HTMLElement) => handlesOf(c, 'main');
	const mainPath = (c: HTMLElement) =>
		c.querySelector('g.draw-line path:not(.draw-hit):not(.draw-selglow)')!;

	it('renders an endpoint handle pair and a hit stroke only while editing', async () => {
		const { container } = render(DrawEditHost);
		expect(handles(container)).toHaveLength(2);
		expect(container.querySelector('.draw-hit')).not.toBeNull();
		adjustMode.set(false);
		await tick();
		expect(handles(container)).toHaveLength(0);
		expect(container.querySelector('.draw-hit')).toBeNull();
	});

	it('published build (canAdjust false) shows no chrome even with adjustMode on', async () => {
		canAdjust.set(false);
		const { container } = render(DrawEditHost);
		expect(container.querySelectorAll('circle.draw-handle')).toHaveLength(0);
		expect(container.querySelector('.draw-hit')).toBeNull();
		// and the surface itself still never intercepts pointer events
		expect(container.querySelector('svg')!.style.pointerEvents).toBe('none');
	});

	it('dragging the from-handle moves the line; undo/redo walk the gesture', async () => {
		const { container } = render(DrawEditHost);
		const fromHandle = handles(container)[0];
		expect(fromHandle.getAttribute('cx')).toBe('100');

		await grab(fromHandle);
		moveTo(30, 50);
		release();
		await tick();
		expect(mainPath(container).getAttribute('d')).toContain('M 130 150');

		undo();
		await tick();
		expect(mainPath(container).getAttribute('d')).toContain('M 100 100');

		redo();
		await tick();
		expect(mainPath(container).getAttribute('d')).toContain('M 130 150');
		undo(); // leave history clean for other tests
	});

	it('Esc mid-drag restores the start geometry and records nothing', async () => {
		const { container } = render(DrawEditHost);
		await grab(handles(container)[1]); // `to` handle at [500, 100]
		moveTo(40, 40);
		await tick();
		expect(handles(container)[1].getAttribute('cx')).toBe('540');
		escape();
		await tick();
		expect(handles(container)[1].getAttribute('cx')).toBe('500');
	});

	it('Shift snaps the dragged endpoint to H/V/45° relative to the other one', async () => {
		const { container } = render(DrawEditHost);
		await grab(handles(container)[1]); // to = [500, 100], from = [100, 100]
		moveTo(100, 12, { shiftKey: true }); // near-horizontal from [100,100]
		release();
		await tick();
		const h = handles(container)[1];
		expect(h.getAttribute('cx')).toBe('600');
		expect(h.getAttribute('cy')).toBe('100'); // pinned to horizontal
		undo();
	});
});

describe('Curve editing (ADJUST mode)', () => {
	beforeEach(() => {
		canAdjust.set(true);
		adjustMode.set(true);
	});
	afterEach(() => {
		canAdjust.set(false);
		adjustMode.set(false);
	});

	const curveG = (c: HTMLElement) => c.querySelector('g.draw-curve')!;

	it('renders endpoint + control handles and guide lines while editing', () => {
		const { container } = render(DrawEditHost);
		expect(handlesOf(container, 'hop')).toHaveLength(4); // from, to, c1, c2
		expect(handlesOf(container, 'hop', '.control')).toHaveLength(2);
		const guides = guidesOf(container, 'hop');
		expect(guides).toHaveLength(2);
		expect(guides[0].getAttribute('d')).toBe('M 200 200 L 100 300'); // c1 → from
		expect(guides[1].getAttribute('d')).toBe('M 400 200 L 500 300'); // c2 → to
	});

	it('guide lines and handles never render outside ADJUST mode', async () => {
		adjustMode.set(false);
		const { container } = render(DrawEditHost);
		expect(guidesOf(container, 'hop')).toHaveLength(0);
		expect(handlesOf(container, 'hop')).toHaveLength(0);
	});

	it('dragging a control point reshapes the curve and its guide; undo restores', async () => {
		const { container } = render(DrawEditHost);
		const g = curveG(container);
		await grab(handlesOf(container, 'hop', '.control')[0]);
		moveTo(50, -100);
		release();
		await tick();
		expect(g.querySelector('path')!.getAttribute('d')).toBe('M 100 300 C 250 100 400 200 500 300');
		// the drag selected the curve, so its guides now live in Draw's top layer
		expect(guidesOf(container, 'hop')[0].getAttribute('d')).toBe('M 250 100 L 100 300');

		undo();
		await tick();
		expect(g.querySelector('path')!.getAttribute('d')).toBe('M 100 300 C 200 200 400 200 500 300');
	});
});

describe('animated-Line stop editing (ADJUST mode)', () => {
	beforeEach(() => {
		canAdjust.set(true);
		adjustMode.set(true);
	});
	afterEach(() => {
		canAdjust.set(false);
		adjustMode.set(false);
	});

	// the host's animated line is the second g.draw-line
	const beamG = (c: HTMLElement) => c.querySelectorAll('g.draw-line')[1];
	const beamHandles = (c: HTMLElement) => handlesOf(c, 'beam');

	it('shows a handle per stop position and hides the base handle for the animated point', () => {
		const { container } = render(DrawEditHost);
		const handles = beamHandles(container);
		// base `from` (not animated) + the 0% and 100% stop positions of `to`
		expect(handles).toHaveLength(3);
		expect(handles[0].getAttribute('cx')).toBe('100'); // base from
		expect(handles[1].getAttribute('cx')).toBe('500');
		expect(handles[1].getAttribute('cy')).toBe('600'); // to @ 0%
		expect(handles[2].getAttribute('cy')).toBe('400'); // to @ 100%
		expect(handles[2].getAttribute('class')).toContain('control'); // later stop = hollow
	});

	it('dragging the 100% stop rewrites the keyframes and the copied tag; undo restores', async () => {
		const writeText = vi.fn().mockResolvedValue(undefined);
		Object.defineProperty(navigator, 'clipboard', {
			value: { writeText },
			configurable: true
		});
		const { container } = render(DrawEditHost);
		await grab(beamHandles(container)[2]); // to @ 100% at [500, 400]
		moveTo(50, -50);
		release();
		await tick();
		expect(beamG(container).querySelector('style')!.textContent).toContain(
			'100% { d: path("M 100 600 L 550 350"); }'
		);

		(container.querySelector('.draw-toolbar .tb-copy') as HTMLButtonElement).click();
		await tick();
		expect(writeText.mock.calls[0][0]).toBe(
			'<Line name="beam" from={[100, 600]} to={[500, 600]} stops={[{ pct: 0, to: [500, 600] }, { pct: 100, to: [550, 350] }]} animate={2} />'
		);

		undo();
		await tick();
		expect(beamG(container).querySelector('style')!.textContent).toContain(
			'100% { d: path("M 100 600 L 500 400"); }'
		);
	});

	it('dragging the 0% stop keeps the base geometry in sync', async () => {
		const { container } = render(DrawEditHost);
		await grab(beamHandles(container)[1]); // to @ 0% at [500, 600]
		moveTo(10, 10);
		release();
		await tick();
		// the static fallback (d attribute) follows the 0% pose
		expect(beamG(container).querySelector('path')!.getAttribute('d')).toBe('M 100 600 L 510 610');
		expect(beamG(container).querySelector('style')!.textContent).toContain(
			'0% { d: path("M 100 600 L 510 610"); }'
		);
		undo();
		await tick();
		expect(beamG(container).querySelector('path')!.getAttribute('d')).toBe('M 100 600 L 500 600');
	});

	async function selectBeam(container: HTMLElement) {
		const hit = beamG(container).querySelector('.draw-hit')!;
		const ev = new MouseEvent('pointerdown', { bubbles: true });
		Object.defineProperty(ev, 'pointerId', { value: 1 });
		hit.dispatchEvent(ev);
		await tick();
	}

	it('selecting an animated line shows a keyframe panel; a static shape does not', async () => {
		const { container } = render(DrawEditHost);
		await selectBeam(container);
		const panel = container.querySelector('.tb-keyframes')!;
		expect(panel).not.toBeNull();
		expect(panel.querySelectorAll('.tb-kfrow')).toHaveLength(2); // 0% and 100%
		expect(
			Array.from(panel.querySelectorAll('input[aria-label="keyframe percent"]')).map(
				(i) => (i as HTMLInputElement).value
			)
		).toEqual(['0', '100']);

		// select the static "main" line instead — no panel
		const mainHit = container.querySelector('g.draw-line .draw-hit')!;
		const ev = new MouseEvent('pointerdown', { bubbles: true });
		Object.defineProperty(ev, 'pointerId', { value: 1 });
		mainHit.dispatchEvent(ev);
		await tick();
		expect(container.querySelector('.tb-keyframes')).toBeNull();
	});

	it('"+ keyframe" inserts a stop in the widest gap with interpolated geometry', async () => {
		const { container } = render(DrawEditHost);
		await selectBeam(container);
		(container.querySelector('.tb-keyframes .tb-add') as HTMLButtonElement).click();
		await tick();
		expect(container.querySelectorAll('.tb-keyframes .tb-kfrow')).toHaveLength(3);
		// no live playhead in jsdom → widest gap: midpoint of 0↔100 = 50%,
		// geometry lerped between the two `to`s
		expect(beamG(container).querySelector('style')!.textContent).toContain(
			'50% { d: path("M 100 600 L 500 500"); }'
		);
	});

	it('"+ keyframe" lands at the AnimationBar playhead when one is running', async () => {
		const { container } = render(DrawEditHost);
		await selectBeam(container);
		// stub the shaft's live animation at 600ms of the 2s timeline → 30%
		// (the shaft is the path carrying the geometry animation, not the glow)
		const shaft = Array.from(beamG(container).querySelectorAll('path')).find((p) =>
			p.getAttribute('style')?.includes('animation: draw-move')
		) as SVGPathElement;
		shaft.getAnimations = () => [{ currentTime: 600 } as Animation];
		(container.querySelector('.tb-keyframes .tb-add') as HTMLButtonElement).click();
		await tick();
		const pcts = Array.from(container.querySelectorAll('.tb-keyframes .tb-pct')).map(
			(i) => (i as HTMLInputElement).value
		);
		expect(pcts).toContain('30');
		// to lerped 0%[500,600]→100%[500,400] at frac 0.3 → [500, 540]
		expect(beamG(container).querySelector('style')!.textContent).toContain(
			'30% { d: path("M 100 600 L 500 540"); }'
		);
	});

	it('a draw-on shape shows a draw-on panel (time + delay), live-editable and copyable', async () => {
		const writeText = vi.fn().mockResolvedValue(undefined);
		Object.defineProperty(navigator, 'clipboard', {
			value: { writeText },
			configurable: true
		});
		const { container } = render(DrawEditHost);
		// select the reveal line (third g.draw-line) via its hit stroke
		const revealG = container.querySelectorAll('g.draw-line')[2];
		const hit = revealG.querySelector('.draw-hit')!;
		const ev = new MouseEvent('pointerdown', { bubbles: true });
		Object.defineProperty(ev, 'pointerId', { value: 1 });
		hit.dispatchEvent(ev);
		await tick();

		const panel = container.querySelector('.tb-keyframes')!;
		expect(panel.querySelector('.tb-kftitle')?.textContent).toBe('draw-on');
		const inputs = Array.from(panel.querySelectorAll('.tb-pct')) as HTMLInputElement[];
		expect(inputs.map((i) => i.value)).toEqual(['2', '0.5']); // time, delay
		// no keyframe stop rows for a plain draw-on shape
		expect(panel.querySelector('.tb-add')).toBeNull();

		// retime the reveal to 3.5s — the live animation duration follows
		inputs[0].value = '3.5';
		inputs[0].dispatchEvent(new Event('change', { bubbles: true }));
		await tick();
		const shaft = revealG.querySelector('path.draw-anim') as SVGPathElement;
		expect(shaft.getAttribute('style')).toContain('animation-duration: 3.5s');

		// Copy reflects the edited draw timing
		(container.querySelector('.tb-copy') as HTMLButtonElement).click();
		await tick();
		expect(writeText.mock.calls[0][0]).toBe(
			'<Line name="reveal" from={[100, 700]} to={[500, 700]} draw={3.5} drawDelay={0.5} />'
		);
	});

	it('a stop can be removed (down to a floor of 2) and retimed via its % field', async () => {
		const { container } = render(DrawEditHost);
		await selectBeam(container);
		// add one so removal is allowed
		(container.querySelector('.tb-keyframes .tb-add') as HTMLButtonElement).click();
		await tick();
		expect(container.querySelectorAll('.tb-kfrow')).toHaveLength(3);

		// retime the middle (50%) stop to 30%
		const midPct = Array.from(container.querySelectorAll('.tb-pct')).find(
			(i) => (i as HTMLInputElement).value === '50'
		) as HTMLInputElement;
		midPct.value = '30';
		midPct.dispatchEvent(new Event('change', { bubbles: true }));
		await tick();
		expect(beamG(container).querySelector('style')!.textContent).toContain('30% { d: path(');

		// remove it → back to 2, and the remove buttons disable at the floor
		const rows = Array.from(container.querySelectorAll('.tb-kfrow'));
		const midRow = rows.find((r) => (r.querySelector('.tb-pct') as HTMLInputElement).value === '30')!;
		(midRow.querySelector('.tb-del') as HTMLButtonElement).click();
		await tick();
		expect(container.querySelectorAll('.tb-kfrow')).toHaveLength(2);
		expect(
			Array.from(container.querySelectorAll('.tb-del')).every((b) => (b as HTMLButtonElement).disabled)
		).toBe(true);
	});
});

describe('keyframe panel — per-stop drawn %', () => {
	beforeEach(() => {
		canAdjust.set(true);
		adjustMode.set(true);
	});
	afterEach(() => {
		canAdjust.set(false);
		adjustMode.set(false);
	});

	// the progress Curve is the sole g.draw-curve[?] with a reveal track;
	// select it via its hit stroke.
	async function selectProgress(container: HTMLElement) {
		const g = Array.from(container.querySelectorAll('g.draw-curve')).find((cg) =>
			cg.querySelector('style')?.textContent?.includes('stroke-dashoffset')
		)!;
		const hit = g.querySelector('.draw-hit')!;
		const ev = new MouseEvent('pointerdown', { bubbles: true });
		Object.defineProperty(ev, 'pointerId', { value: 1 });
		hit.dispatchEvent(ev);
		await tick();
		return g;
	}

	it('shows a drawn % field per keyframe and edits the reveal live + copyable', async () => {
		const writeText = vi.fn().mockResolvedValue(undefined);
		Object.defineProperty(navigator, 'clipboard', { value: { writeText }, configurable: true });
		const { container } = render(DrawEditHost);
		const g = await selectProgress(container);

		const rows = container.querySelectorAll('.tb-keyframes .tb-kfrow');
		expect(rows).toHaveLength(2);
		// each row: [pct, drawn] — 0%/0 and 100%/100
		const drawnInputs = Array.from(container.querySelectorAll('input[aria-label="keyframe drawn percent"]')) as HTMLInputElement[];
		expect(drawnInputs.map((i) => i.value)).toEqual(['0', '100']);

		// set the 0% stop's drawn to 25% → stroke-dashoffset 0.75 at 0%
		drawnInputs[0].value = '25';
		drawnInputs[0].dispatchEvent(new Event('change', { bubbles: true }));
		await tick();
		expect(g.querySelector('style')!.textContent).toContain('0% { stroke-dashoffset: 0.75; }');

		// Copy reflects the edited drawn fraction (25% → 0.25)
		(container.querySelector('.draw-toolbar .tb-copy') as HTMLButtonElement).click();
		await tick();
		expect(writeText.mock.calls[0][0]).toContain('{ pct: 0, c1: [300, 800], drawn: 0.25 }');
	});

	it('per-stop easing picker sets the segment timing function, live + copyable', async () => {
		const writeText = vi.fn().mockResolvedValue(undefined);
		Object.defineProperty(navigator, 'clipboard', { value: { writeText }, configurable: true });
		const { container } = render(DrawEditHost);
		const g = await selectProgress(container);
		const easeSelects = () =>
			Array.from(container.querySelectorAll('select[aria-label="keyframe easing"]')) as HTMLSelectElement[];
		expect(easeSelects().length).toBe(2); // one per keyframe
		expect(easeSelects()[0].value).toBe(''); // default

		// pick ease-out on the 0% stop → it rides its geometry keyframe
		const sel = easeSelects()[0];
		sel.value = 'ease-out';
		sel.dispatchEvent(new Event('change', { bubbles: true }));
		await tick();
		expect(g.querySelector('style')!.textContent).toContain('animation-timing-function: ease-out;');

		// Copy carries the ease
		(container.querySelector('.draw-toolbar .tb-copy') as HTMLButtonElement).click();
		await tick();
		expect(writeText.mock.calls[0][0]).toContain('ease: "ease-out"');
	});

	it('previews the timeline % and interpolated drawn % live while scrubbing', async () => {
		// jsdom runs no CSS animation, so stub what the preview reads: the
		// shaft's live playhead (getAnimations currentTime) and its animated
		// stroke-dashoffset (getComputedStyle).
		const real = window.getComputedStyle;
		const spy = vi
			.spyOn(window, 'getComputedStyle')
			.mockImplementation((el: Element, pseudo?: string | null) => {
				const cs = real.call(window, el, pseudo ?? undefined);
				return new Proxy(cs, {
					get: (t, p) => (p === 'strokeDashoffset' ? '0.4' : Reflect.get(t, p))
				}) as CSSStyleDeclaration;
			});
		try {
			const { container } = render(DrawEditHost);
			const g = await selectProgress(container);
			// progress Curve: animate={3} → currentTime 1500ms = 50% of the timeline
			const shaft = Array.from(g.querySelectorAll('path')).find((p) =>
				p.getAttribute('style')?.includes('animation: draw-move')
			) as SVGPathElement;
			shaft.getAnimations = () => [{ currentTime: 1500 } as Animation];
			await new Promise((r) => setTimeout(r, 40)); // let the rAF poll fire
			// 50% timeline · 60% drawn (dashoffset 0.4)
			expect(container.querySelector('.tb-livedrawn')?.textContent).toContain('50%');
			expect(container.querySelector('.tb-livedrawn')?.textContent).toContain('60% drawn');
		} finally {
			spy.mockRestore();
		}
	});

	it('preview on a geometry-only shape shows the timeline % but no drawn', async () => {
		const { container } = render(DrawEditHost);
		// select the geometry-only beam Line (second g.draw-line)
		const beam = container.querySelectorAll('g.draw-line')[1];
		const hit = beam.querySelector('.draw-hit')!;
		const ev = new MouseEvent('pointerdown', { bubbles: true });
		Object.defineProperty(ev, 'pointerId', { value: 1 });
		hit.dispatchEvent(ev);
		await tick();
		const shaft = Array.from(beam.querySelectorAll('path')).find((p) =>
			p.getAttribute('style')?.includes('animation: draw-move')
		) as SVGPathElement;
		shaft.getAnimations = () => [{ currentTime: 600 } as Animation]; // animate={2} → 30%
		await new Promise((r) => setTimeout(r, 40));
		const text = container.querySelector('.tb-livedrawn')?.textContent ?? '';
		expect(text).toContain('30%');
		expect(text).not.toContain('drawn');
	});

	it('a geometry-only animated Line offers empty drawn fields (add reveal on demand)', async () => {
		const { container } = render(DrawEditHost);
		// select the beam (geometry-only Line, second g.draw-line)
		const beam = container.querySelectorAll('g.draw-line')[1];
		const hit = beam.querySelector('.draw-hit')!;
		const ev = new MouseEvent('pointerdown', { bubbles: true });
		Object.defineProperty(ev, 'pointerId', { value: 1 });
		hit.dispatchEvent(ev);
		await tick();
		// Line supports reveal → drawn fields present, but blank (no reveal keyframes yet)
		const drawnInputs = () =>
			Array.from(
				container.querySelectorAll('input[aria-label="keyframe drawn percent"]')
			) as HTMLInputElement[];
		expect(drawnInputs().length).toBe(2);
		expect(drawnInputs().every((i) => i.value === '')).toBe(true);
		expect(beam.querySelector('style')!.textContent).not.toContain('stroke-dashoffset');

		// filling BOTH stops' drawn (reveal needs ≥2) activates the reveal track
		const setDrawn = async (idx: number, v: string) => {
			const el = drawnInputs()[idx];
			el.value = v;
			el.dispatchEvent(new Event('change', { bubbles: true }));
			await tick();
		};
		await setDrawn(0, '0'); // 0% → drawn 0 → dashoffset 1
		await setDrawn(1, '100'); // 100% → drawn 1 → dashoffset 0
		const style = beam.querySelector('style')!.textContent!;
		expect(style).toContain('0% { stroke-dashoffset: 1; }');
		expect(style).toContain('100% { stroke-dashoffset: 0; }');
	});
});

describe('Arc editing (ADJUST mode)', () => {
	beforeEach(() => {
		canAdjust.set(true);
		adjustMode.set(true);
	});
	afterEach(() => {
		canAdjust.set(false);
		adjustMode.set(false);
	});

	const arcG = (c: HTMLElement) => c.querySelector('g.draw-arc')!;

	it('renders endpoint handles plus one bend handle at the apex', () => {
		const { container } = render(DrawEditHost);
		expect(handlesOf(container, 'loop')).toHaveLength(3);
		const bendHandle = handlesOf(container, 'loop', '.bend')[0];
		// arc [100,500]→[500,500] bend 0.25: apex at [300, 500 − 0.25·400]
		expect(bendHandle.getAttribute('cx')).toBe('300');
		expect(bendHandle.getAttribute('cy')).toBe('400');
	});

	it('dragging the bend handle across the chord flips the sign of bend', async () => {
		const { container } = render(DrawEditHost);
		const g = arcG(container);
		await grab(handlesOf(container, 'loop', '.bend')[0]);
		moveTo(0, 200); // from apex [300,400] down to [300,600] — 100 past the chord
		release();
		await tick();
		// bend −0.25 → sweep flag flips from 1 to 0, same radius
		expect(g.querySelector('path')!.getAttribute('d')).toContain(' 0 0 0 500 500');
		// and the handle re-rendered on the new apex, below the chord (the drag
		// selected the arc, so its chrome is now in Draw's top layer)
		expect(handlesOf(container, 'loop', '.bend')[0].getAttribute('cy')).toBe('600');

		undo();
		await tick();
		expect(g.querySelector('path')!.getAttribute('d')).toContain(' 0 0 1 500 500');
	});
});

describe('Rect/Ellipse editing via Block (ADJUST mode)', () => {
	beforeEach(() => {
		canAdjust.set(true);
		adjustMode.set(true);
	});
	afterEach(() => {
		canAdjust.set(false);
		adjustMode.set(false);
	});

	const blockOf = (c: HTMLElement, name: string) =>
		Array.from(c.querySelectorAll('div.movable')).find((m) =>
			m.querySelector('.readout')?.textContent?.includes(name)
		)!;

	// A Draw-hosted Rect/Ellipse writes back through the shape save-patch registry
	// (its Block wrapper is track={false}), so its live opening tag lives there.
	const newTagOf = (name: string) =>
		[...get(shapeChanges).values()].find((e) => e.name === name)?.newTag;

	it('Draw hosts one editing Block per box shape, aligned to it', async () => {
		const { container } = render(DrawEditHost);
		await tick(); // registrations land in a post-render effect
		const movables = container.querySelectorAll('div.movable');
		expect(movables).toHaveLength(4); // hosted Rect + Ellipse + reveal Rect, plus the slide Block
		const rectBlock = blockOf(container, 'frame') as HTMLElement;
		expect(rectBlock.style.left).toBe('700px');
		expect(rectBlock.style.top).toBe('100px');
	});

	it('no hosted Blocks outside ADJUST mode', async () => {
		adjustMode.set(false);
		const { container } = render(DrawEditHost);
		await tick();
		// only the slide-level Block's plain wrapper remains — no editing chrome
		expect(container.querySelectorAll('div.movable')).toHaveLength(1);
		expect(container.querySelector('div.movable .readout')).toBeNull();
	});

	it('dragging the Block moves the svg rect; undo restores', async () => {
		const { container } = render(DrawEditHost);
		await tick();
		const rectBlock = blockOf(container, 'frame');
		await grab(rectBlock);
		moveTo(50, 30);
		release();
		await tick();
		const rect = container.querySelector('rect.draw-rect')!;
		expect(rect.getAttribute('x')).toBe('750');
		expect(rect.getAttribute('y')).toBe('130');

		undo();
		await tick();
		expect(rect.getAttribute('x')).toBe('700');
		expect(rect.getAttribute('y')).toBe('100');
	});

	it('a draw-on Rect/Ellipse gets draw-on fields in its Block toolbar, live + saved', async () => {
		const { container } = render(DrawEditHost);
		await tick();
		const block = blockOf(container, 'revealbox');
		const drawon = block.querySelector('.drawon')!;
		expect(drawon).not.toBeNull();
		const inputs = Array.from(drawon.querySelectorAll('input')) as HTMLInputElement[];
		expect(inputs.map((i) => i.value)).toEqual(['1.5', '0.5']); // time, delay

		// a plain box (no draw) shows no draw-on editor
		expect(blockOf(container, 'frame').querySelector('.drawon')).toBeNull();

		// retime the reveal → the svg rect's animation-duration follows
		inputs[0].value = '3';
		inputs[0].dispatchEvent(new Event('change', { bubbles: true }));
		await tick();
		const rect = Array.from(container.querySelectorAll('rect.draw-rect')).find((r) =>
			r.getAttribute('style')?.includes('animation-duration: 3s')
		);
		expect(rect).toBeTruthy();

		// the shape's save-patch tag carries the updated draw timing
		expect(newTagOf('revealbox')).toBe(
			'<Rect name="revealbox" draw={3} drawDelay={0.5} x={1100} y={100} width={220} height={120} />'
		);
	});

	it("the save patch carries the shape's OWN tag with live geometry and extra attrs", async () => {
		render(DrawEditHost);
		await tick();
		expect(newTagOf('ring')).toBe(
			'<Ellipse name="ring" x={700} y={400} width={200} height={100} />'
		);
	});
});

describe('selection + Copy toolbar (ADJUST mode)', () => {
	beforeEach(() => {
		canAdjust.set(true);
		adjustMode.set(true);
	});
	afterEach(() => {
		canAdjust.set(false);
		adjustMode.set(false);
	});

	async function clickStroke(c: HTMLElement, group: string) {
		const hit = c.querySelector(`g.${group} .draw-hit`)!;
		const ev = new MouseEvent('pointerdown', { bubbles: true });
		Object.defineProperty(ev, 'pointerId', { value: 1 });
		hit.dispatchEvent(ev);
		await tick();
	}

	it('no toolbar until a shape is selected; stroke click brings it up', async () => {
		const { container } = render(DrawEditHost);
		expect(container.querySelector('.draw-toolbar')).toBeNull();
		await clickStroke(container, 'draw-line');
		const toolbar = container.querySelector('.draw-toolbar')!;
		expect(toolbar.querySelector('.tb-shape')?.textContent).toBe('main');
		expect(toolbar.querySelector('.tb-readout')?.textContent).toContain('from [100, 100]');
	});

	it('selecting another shape swaps the toolbar target; the glow follows', async () => {
		const { container } = render(DrawEditHost);
		await clickStroke(container, 'draw-line');
		expect(container.querySelector('g.draw-line .draw-selglow')).not.toBeNull();
		await clickStroke(container, 'draw-curve');
		expect(container.querySelector('.draw-toolbar .tb-shape')?.textContent).toBe('hop');
		expect(container.querySelector('g.draw-line .draw-selglow')).toBeNull();
		expect(container.querySelector('g.draw-curve .draw-selglow')).not.toBeNull();
	});

	it('Copy emits the opening tag with LIVE geometry after a drag', async () => {
		const writeText = vi.fn().mockResolvedValue(undefined);
		Object.defineProperty(navigator, 'clipboard', {
			value: { writeText },
			configurable: true
		});
		const { container } = render(DrawEditHost);
		// drag the line's from-handle by (30, 50) — this also selects the shape
		const fromHandle = handlesOf(container, 'main')[0];
		await grab(fromHandle);
		moveTo(30, 50);
		release();
		await tick();

		(container.querySelector('.draw-toolbar .tb-copy') as HTMLButtonElement).click();
		await tick();
		expect(writeText).toHaveBeenCalledWith(
			'<Line name="main" from={[130, 150]} to={[500, 100]} arrow="end" thickness={6} />'
		);
		undo();
	});

	it('the surface is raised above the HTML chrome whenever editing, so handles are always reachable', async () => {
		const { container } = render(DrawEditHost);
		const svg = container.querySelector('svg.draw')!;
		// raised from the moment ADJUST is on — a Block/ghost sitting on a
		// handle must never make it unselectable
		expect(svg.classList.contains('raised')).toBe(true);

		// ✕ deselects (toolbar + glow gone) but the surface stays raised
		await clickStroke(container, 'draw-line');
		(container.querySelector('.draw-toolbar .tb-close') as HTMLButtonElement).click();
		await tick();
		expect(container.querySelector('.draw-toolbar')).toBeNull();
		expect(container.querySelector('g.draw-line .draw-selglow')).toBeNull();
		expect(svg.classList.contains('raised')).toBe(true);

		// leaving ADJUST mode drops it back down
		adjustMode.set(false);
		await tick();
		expect(svg.classList.contains('raised')).toBe(false);
	});

	it('grabbing anything outside the Draw chrome deselects (single selection)', async () => {
		const { container } = render(DrawEditHost);
		await clickStroke(container, 'draw-line');
		expect(container.querySelector('.draw-toolbar')).not.toBeNull();

		// pointerdown on a hosted editing Block (the Rect's) — not Draw chrome
		const rectBlock = Array.from(container.querySelectorAll('div.movable')).find((m) =>
			m.querySelector('.readout')?.textContent?.includes('frame')
		)!;
		const ev = new MouseEvent('pointerdown', { bubbles: true });
		Object.defineProperty(ev, 'pointerId', { value: 1 });
		rectBlock.dispatchEvent(ev);
		await tick();
		expect(container.querySelector('.draw-toolbar')).toBeNull();
		expect(container.querySelector('g.draw-line .draw-selglow')).toBeNull();
		escape(); // end the Block drag the pointerdown started
	});

	it('clicking empty page space deselects too', async () => {
		const { container } = render(DrawEditHost);
		await clickStroke(container, 'draw-curve');
		expect(container.querySelector('.draw-toolbar')).not.toBeNull();
		document.body.dispatchEvent(new MouseEvent('pointerdown', { bubbles: true }));
		await tick();
		expect(container.querySelector('.draw-toolbar')).toBeNull();
	});

	it('interacting with the AnimationBar keeps the selection (toolbar stays up)', async () => {
		const { container } = render(DrawEditHost);
		await clickStroke(container, 'draw-curve');
		expect(container.querySelector('.draw-toolbar')).not.toBeNull();
		// a pointerdown originating inside an .anim-bar must not deselect
		const bar = document.createElement('div');
		bar.className = 'anim-bar';
		const knob = document.createElement('div');
		bar.appendChild(knob);
		document.body.appendChild(bar);
		knob.dispatchEvent(new MouseEvent('pointerdown', { bubbles: true }));
		await tick();
		expect(container.querySelector('.draw-toolbar')).not.toBeNull();
		bar.remove();
	});

	it('"Copy changed" emits an OLD/NEW patch of every dragged shape, in markup order', async () => {
		const writeText = vi.fn().mockResolvedValue(undefined);
		Object.defineProperty(navigator, 'clipboard', {
			value: { writeText },
			configurable: true
		});
		const { container } = render(DrawEditHost);
		await tick();

		// drag the line's from-handle…
		const fromHandle = handlesOf(container, 'main')[0];
		await grab(fromHandle);
		moveTo(30, 50);
		release();
		// …and the Rect's hosted Block
		const rectBlock = Array.from(container.querySelectorAll('div.movable')).find((m) =>
			m.querySelector('.readout')?.textContent?.includes('frame')
		)!;
		await grab(rectBlock);
		moveTo(10, 10);
		release();
		await tick();

		// the toolbar stays up (dirty shapes), even with nothing selected
		document.body.dispatchEvent(new MouseEvent('pointerdown', { bubbles: true }));
		await tick();
		const toolbar = container.querySelector('.draw-toolbar')!;
		expect(toolbar).not.toBeNull();
		expect(toolbar.querySelector('.tb-count')?.textContent).toBe('2 changed');
		expect(toolbar.querySelector('.tb-readout')).toBeNull(); // no shape row

		(toolbar.querySelector('.tb-patch') as HTMLButtonElement).click();
		await tick();
		const patch = writeText.mock.calls[0][0] as string;
		expect(patch).toContain('Slide shape updates (2 changed)');
		expect(patch).toContain(
			'1) Line "main"\nOLD: <Line name="main" from={[100, 100]} to={[500, 100]} arrow="end" thickness={6} />\nNEW: <Line name="main" from={[130, 150]} to={[500, 100]} arrow="end" thickness={6} />'
		);
		expect(patch).toContain(
			'2) Rect "frame"\nOLD: <Rect name="frame" rounded={12} color="#2980b9" x={700} y={100} width={300} height={200} />\nNEW: <Rect name="frame" rounded={12} color="#2980b9" x={710} y={110} width={300} height={200} />'
		);

		// undo both drags → nothing dirty → toolbar goes away
		undo();
		undo();
		await tick();
		expect(container.querySelector('.draw-toolbar')).toBeNull();
	});

	it('dragging ONLY a Rect still surfaces the toolbar and includes it in the patch', async () => {
		const writeText = vi.fn().mockResolvedValue(undefined);
		Object.defineProperty(navigator, 'clipboard', {
			value: { writeText },
			configurable: true
		});
		const { container } = render(DrawEditHost);
		await tick();
		expect(container.querySelector('.draw-toolbar')).toBeNull();

		const rectBlock = Array.from(container.querySelectorAll('div.movable')).find((m) =>
			m.querySelector('.readout')?.textContent?.includes('frame')
		)!;
		await grab(rectBlock);
		moveTo(25, 15);
		release();
		await tick();

		const toolbar = container.querySelector('.draw-toolbar')!;
		expect(toolbar).not.toBeNull();
		expect(toolbar.querySelector('.tb-count')?.textContent).toBe('1 changed');
		(toolbar.querySelector('.tb-patch') as HTMLButtonElement).click();
		await tick();
		const patch = writeText.mock.calls[0][0] as string;
		expect(patch).toContain('1) Rect "frame"');
		expect(patch).toContain('NEW: <Rect name="frame" rounded={12} color="#2980b9" x={725} y={115}');
		undo();
	});

	it('RESIZING a Rect (corner grip) also marks it changed', async () => {
		const { container } = render(DrawEditHost);
		await tick();
		const rectBlock = Array.from(container.querySelectorAll('div.movable')).find((m) =>
			m.querySelector('.readout')?.textContent?.includes('frame')
		)!;
		await grab(rectBlock.querySelector('.handle')!); // bottom-right resize grip
		moveTo(40, 20);
		release();
		await tick();
		const toolbar = container.querySelector('.draw-toolbar')!;
		expect(toolbar).not.toBeNull();
		expect(toolbar.querySelector('.tb-count')?.textContent).toBe('1 changed');
		const rect = container.querySelector('rect.draw-rect')!;
		expect(rect.getAttribute('width')).toBe('340');
		undo();
	});

	it('dragging a plain slide-level Block enters the patch too', async () => {
		const writeText = vi.fn().mockResolvedValue(undefined);
		Object.defineProperty(navigator, 'clipboard', {
			value: { writeText },
			configurable: true
		});
		const { container } = render(DrawEditHost);
		await tick();

		const nodeBlock = Array.from(container.querySelectorAll('div.movable')).find((m) =>
			m.querySelector('.readout')?.textContent?.includes('node')
		)!;
		await grab(nodeBlock);
		moveTo(25, 15);
		release();
		await tick();

		const toolbar = container.querySelector('.draw-toolbar')!;
		expect(toolbar.querySelector('.tb-count')?.textContent).toBe('1 changed');
		(toolbar.querySelector('.tb-patch') as HTMLButtonElement).click();
		await tick();
		const patch = writeText.mock.calls[0][0] as string;
		expect(patch).toContain(
			'1) Block "node"\nOLD: <Block name="node" x={100} y={800} width={200} height={100}>\nNEW: <Block name="node" x={125} y={815} width={200} height={100}>'
		);
		undo();
	});

	it("Draw-hosted Rect/Ellipse Blocks don't double-enter the patch", async () => {
		const writeText = vi.fn().mockResolvedValue(undefined);
		Object.defineProperty(navigator, 'clipboard', {
			value: { writeText },
			configurable: true
		});
		const { container } = render(DrawEditHost);
		await tick();
		const rectBlock = Array.from(container.querySelectorAll('div.movable')).find((m) =>
			m.querySelector('.readout')?.textContent?.includes('frame')
		)!;
		await grab(rectBlock);
		moveTo(25, 15);
		release();
		await tick();

		const toolbar = container.querySelector('.draw-toolbar')!;
		expect(toolbar.querySelector('.tb-count')?.textContent).toBe('1 changed');
		(toolbar.querySelector('.tb-patch') as HTMLButtonElement).click();
		await tick();
		const patch = writeText.mock.calls[0][0] as string;
		expect(patch.split('OLD:')).toHaveLength(2); // exactly one entry
		expect(patch).toContain('1) Rect "frame"');
		undo();
	});

	it('the toolbar never exists outside ADJUST mode', async () => {
		const { container } = render(DrawEditHost);
		await clickStroke(container, 'draw-line');
		expect(container.querySelector('.draw-toolbar')).not.toBeNull();
		adjustMode.set(false);
		await tick();
		expect(container.querySelector('.draw-toolbar')).toBeNull();
	});
});

describe('Path editing (ADJUST mode)', () => {
	beforeEach(() => {
		canAdjust.set(true);
		adjustMode.set(true);
	});
	afterEach(() => {
		canAdjust.set(false);
		adjustMode.set(false);
	});

	// Host Path: start [700,700], arrow="end", segments =
	//   line → [900,700], quad → [1100,600] c1[1000,700], arc → [1300,600] bend 0.4
	const pathG = (c: HTMLElement) => c.querySelector('g.draw-path')!;
	const shaft = (c: HTMLElement) => pathG(c).querySelector('path.draw-path-shaft')!;

	it('renders one handle per vertex — start, each `to`, controls, and arc bend', () => {
		const { container } = render(DrawEditHost);
		// start + seg0.to + seg1.to + seg1.c1 + seg2.to + seg2.bend
		expect(handlesOf(container, 'route')).toHaveLength(6);
		expect(handlesOf(container, 'route', '.control')).toHaveLength(1); // the curve's c1
		expect(handlesOf(container, 'route', '.bend')).toHaveLength(1); // the arc's apex
		const guides = guidesOf(container, 'route');
		expect(guides).toHaveLength(2); // c1 → from, c1 → to (the quadratic segment)
		expect(guides[0].getAttribute('d')).toBe('M 1000 700 L 900 700');
		expect(guides[1].getAttribute('d')).toBe('M 1000 700 L 1100 600');
	});

	it('handles and guides never render outside ADJUST mode', () => {
		adjustMode.set(false);
		const { container } = render(DrawEditHost);
		expect(handlesOf(container, 'route')).toHaveLength(0);
		expect(guidesOf(container, 'route')).toHaveLength(0);
		expect(pathG(container).querySelector('.draw-hit')).toBeNull();
	});

	it('dragging the start point re-chains the whole stroke; undo restores', async () => {
		const { container } = render(DrawEditHost);
		const startHandle = handlesOf(container, 'route')[0];
		expect(startHandle.getAttribute('cx')).toBe('700'); // the start vertex
		await grab(startHandle);
		moveTo(20, -30);
		release();
		await tick();
		expect(shaft(container).getAttribute('d')).toMatch(/^M 720 670 L 900 700 Q 1000 700 1100 600 /);

		undo();
		await tick();
		expect(shaft(container).getAttribute('d')).toMatch(/^M 700 700 L 900 700 Q 1000 700 1100 600 /);
	});

	it('Copy emits the whole <Path> tag with the live start point after a drag', async () => {
		const writeText = vi.fn().mockResolvedValue(undefined);
		Object.defineProperty(navigator, 'clipboard', { value: { writeText }, configurable: true });
		const { container } = render(DrawEditHost);
		await grab(handlesOf(container, 'route')[0]); // start, also selects
		moveTo(20, -30);
		release();
		await tick();

		(container.querySelector('.draw-toolbar .tb-copy') as HTMLButtonElement).click();
		await tick();
		expect(writeText).toHaveBeenCalledWith(
			'<Path name="route" start={[720, 670]} segments={[{ to: [900, 700] }, { to: [1100, 600], c1: [1000, 700] }, { to: [1300, 600], bend: 0.4 }]} arrow="end" />'
		);
		undo();
	});

	// The demo authors these Paths on ONE line each so the ADJUST "Save"
	// endpoint (literal indexOf(oldTag) in patchSource) can find and rewrite
	// them. This pins that canonical single-line form: an author selecting the
	// shape and hitting Copy must get back the exact string sitting in source.
	it('a Path Copies back its exact canonical single-line source tag (Save round-trip)', async () => {
		const writeText = vi.fn().mockResolvedValue(undefined);
		Object.defineProperty(navigator, 'clipboard', { value: { writeText }, configurable: true });
		const { container } = render(PathHost);
		const paths = container.querySelectorAll('g.draw-path');

		const copyOf = async (g: Element) => {
			const ev = new MouseEvent('pointerdown', { bubbles: true });
			Object.defineProperty(ev, 'pointerId', { value: 1 });
			g.querySelector('.draw-hit')!.dispatchEvent(ev);
			await tick();
			writeText.mockClear();
			(container.querySelector('.draw-toolbar .tb-copy') as HTMLButtonElement).click();
			await tick();
			return writeText.mock.calls[0][0] as string;
		};

		expect(await copyOf(paths[0])).toBe(
			'<Path name="flow" start={[200, 620]} segments={[{ to: [520, 620] }, { to: [820, 470], c1: [670, 620] }, { to: [1180, 470], bend: 0.5 }, { to: [1520, 620], c1: [1360, 470], c2: [1400, 620] }]} arrow="end" color="#2980b9" thickness={6} label="a straight line, a curve, an arc and a cubic chained into one arrow" labelText="one continuous stroke" labelAt={0.4} labelOffset={40} />'
		);
		expect(await copyOf(paths[1])).toBe(
			'<Path name="wave" start={[220, 940]} segments={[{ to: [480, 940], bend: 0.6 }, { to: [740, 940], bend: -0.6 }, { to: [1000, 940], bend: 0.6 }, { to: [1260, 940], bend: -0.6 }, { to: [1520, 940], bend: 0.6 }]} color="#f39c12" thickness={5} label="a serpentine of alternating arcs drawing itself on as one stroke" draw={2.5} />'
		);
	});

	it('the arc bend handle rides the apex; dragging it across the chord retimes bend', async () => {
		const writeText = vi.fn().mockResolvedValue(undefined);
		Object.defineProperty(navigator, 'clipboard', { value: { writeText }, configurable: true });
		const { container } = render(DrawEditHost);
		const bendHandle = handlesOf(container, 'route', '.bend')[0];
		// apex of arc from[1100,600]→to[1300,600] bend 0.4: midpoint [1200,600]
		// offset up by the sagitta (80) → [1200, 520].
		expect(bendHandle.getAttribute('cx')).toBe('1200');
		expect(bendHandle.getAttribute('cy')).toBe('520');
		await grab(bendHandle);
		moveTo(0, 100); // apex → [1200, 620]: across the chord, bend flips to −0.1
		release();
		await tick();

		(container.querySelector('.draw-toolbar .tb-copy') as HTMLButtonElement).click();
		await tick();
		expect(writeText).toHaveBeenCalledWith(
			'<Path name="route" start={[700, 700]} segments={[{ to: [900, 700] }, { to: [1100, 600], c1: [1000, 700] }, { to: [1300, 600], bend: -0.1 }]} arrow="end" />'
		);
		undo();
	});
});

describe('animated-Path stop editing (ADJUST mode)', () => {
	beforeEach(() => {
		canAdjust.set(true);
		adjustMode.set(true);
	});
	afterEach(() => {
		canAdjust.set(false);
		adjustMode.set(false);
	});

	// The host's animated Path (`morph`, stops + animate) is the second g.draw-path.
	const morphG = (c: HTMLElement) => c.querySelectorAll('g.draw-path')[1];

	it('generates sampled morph keyframes and one handle set per stop pose', () => {
		const { container } = render(DrawEditHost);
		const g = morphG(container);
		expect(g.querySelector('style')!.textContent).toContain('@keyframes draw-move-');
		// 2 stops × (start + 2 segment `to`s) = 6; the later (100%) stop's are hollow.
		expect(handlesOf(container, 'morph')).toHaveLength(6);
		expect(handlesOf(container, 'morph', '.control')).toHaveLength(3);
	});

	it('Copy round-trips the stops + animate; a stop drag rewrites its pose (undo restores)', async () => {
		const writeText = vi.fn().mockResolvedValue(undefined);
		Object.defineProperty(navigator, 'clipboard', { value: { writeText }, configurable: true });
		const { container } = render(DrawEditHost);
		// drag the 100% stop's start handle (a hollow handle at [700,900]) up-left
		const handle = handlesOf(container, 'morph')[3];
		await grab(handle);
		moveTo(20, -30);
		release();
		await tick();

		(container.querySelector('.draw-toolbar .tb-copy') as HTMLButtonElement).click();
		await tick();
		const tag = writeText.mock.calls[0][0] as string;
		expect(tag).toContain('animate={2}');
		expect(tag).toContain('stops={[');
		expect(tag).toContain('start: [720, 870]'); // the dragged 100% stop gained an explicit start

		undo();
		await tick();
		writeText.mockClear();
		(container.querySelector('.draw-toolbar .tb-copy') as HTMLButtonElement).click();
		await tick();
		expect(writeText.mock.calls[0][0] as string).not.toContain('start: [720, 870]');
	});
});
