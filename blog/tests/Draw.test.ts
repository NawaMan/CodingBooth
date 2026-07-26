import { render } from '@testing-library/svelte';
import { createRawSnippet } from 'svelte';
import { describe, expect, it } from 'vitest';
import Arc from '../src/lib/draw/Arc.svelte';
import Curve from '../src/lib/draw/Curve.svelte';
import Draw from '../src/lib/draw/Draw.svelte';
import Ellipse from '../src/lib/draw/Ellipse.svelte';
import Line from '../src/lib/draw/Line.svelte';
import Path from '../src/lib/draw/Path.svelte';
import Polyline from '../src/lib/draw/Polyline.svelte';
import Rect from '../src/lib/draw/Rect.svelte';

const svg = (container: HTMLElement) => container.querySelector('svg')!;

describe('Draw', () => {
	it('renders a full-canvas SVG in 1920x1080 canvas coordinates by default', () => {
		const { container } = render(Draw, { title: 'Test surface' });
		const el = svg(container);
		expect(el).not.toBeNull();
		expect(el.getAttribute('viewBox')).toBe('0 0 1920 1080');
		expect(el.style.width).toBe('1920px');
		expect(el.style.height).toBe('1080px');
	});

	it('supports custom coordinate spaces for portrait decks', () => {
		const { container } = render(Draw, { title: 'Portrait', width: 1080, height: 1920 });
		expect(svg(container).getAttribute('viewBox')).toBe('0 0 1080 1920');
	});

	it('never eats input: pointer-events none on the surface', () => {
		const { container } = render(Draw, { title: 'Test surface' });
		expect(svg(container).style.pointerEvents).toBe('none');
	});

	it('wires role="img" with <title> and <desc>', () => {
		const { container } = render(Draw, {
			title: 'Request flow',
			description: 'An arrow from client to server'
		});
		const el = svg(container);
		expect(el.getAttribute('role')).toBe('img');
		expect(el.querySelector('title')?.textContent).toBe('Request flow');
		expect(el.querySelector('desc')?.textContent).toBe('An arrow from client to server');
	});

	it('decorative surfaces are aria-hidden with no role/title', () => {
		const { container } = render(Draw, { decorative: true });
		const el = svg(container);
		expect(el.getAttribute('aria-hidden')).toBe('true');
		expect(el.getAttribute('role')).toBeNull();
		expect(el.querySelector('title')).toBeNull();
	});

	it('passes raw SVG children through (escape hatch)', () => {
		const { container } = render(Draw, {
			title: 'Escape hatch',
			children: createRawSnippet(() => ({
				render: () => '<circle cx="960" cy="540" r="8" fill="currentColor" />'
			}))
		});
		const circle = svg(container).querySelector('circle');
		expect(circle?.getAttribute('cx')).toBe('960');
	});
});

describe('Line', () => {
	it('renders a path between from and to', () => {
		const { container } = render(Line, { from: [100, 200] as [number, number], to: [900, 540] as [number, number] });
		expect(container.querySelector('path')?.getAttribute('d')).toBe('M 100 200 L 900 540');
	});

	it('arrow="end": head tip lands exactly on `to`, shaft shortened behind it', () => {
		const { container } = render(Line, {
			from: [0, 0] as [number, number],
			to: [100, 0] as [number, number],
			arrow: 'end' as const,
			arrowSize: 20
		});
		const polygons = container.querySelectorAll('polygon');
		expect(polygons).toHaveLength(1);
		expect(polygons[0].getAttribute('points')).toBe('100,0 80,10 80,-10'); // tip first, on `to`
		expect(container.querySelector('path')?.getAttribute('d')).toBe('M 0 0 L 80 0');
	});

	it('arrow="both": two heads, shaft shortened at both ends', () => {
		const { container } = render(Line, {
			from: [0, 0] as [number, number],
			to: [100, 0] as [number, number],
			arrow: 'both' as const,
			arrowSize: 20
		});
		expect(container.querySelectorAll('polygon')).toHaveLength(2);
		expect(container.querySelector('path')?.getAttribute('d')).toBe('M 20 0 L 80 0');
	});

	it('no polygons without arrow', () => {
		const { container } = render(Line, { from: [0, 0] as [number, number], to: [100, 0] as [number, number] });
		expect(container.querySelectorAll('polygon')).toHaveLength(0);
	});

	it('dash: true gives the default pattern, a string passes through', () => {
		const dashed = render(Line, { from: [0, 0] as [number, number], to: [1, 1] as [number, number], dash: true });
		expect(dashed.container.querySelector('path')?.getAttribute('stroke-dasharray')).toBe('12 8');
		const custom = render(Line, { from: [0, 0] as [number, number], to: [1, 1] as [number, number], dash: '3 3' });
		expect(custom.container.querySelector('path')?.getAttribute('stroke-dasharray')).toBe('3 3');
	});

	it('color/thickness props override the --draw-* custom properties', () => {
		const { container } = render(Line, {
			from: [0, 0] as [number, number],
			to: [1, 1] as [number, number],
			color: '#e74c3c',
			thickness: 10
		});
		const style = container.querySelector('path')?.getAttribute('style') ?? '';
		expect(style).toContain('#e74c3c');
		expect(style).toContain('stroke-width: 10');
	});

	it('defaults inherit the custom properties / currentColor', () => {
		const { container } = render(Line, { from: [0, 0] as [number, number], to: [1, 1] as [number, number] });
		const style = container.querySelector('path')?.getAttribute('style') ?? '';
		expect(style).toContain('var(--draw-stroke, currentColor)');
		expect(style).toContain('var(--draw-thickness, 4)');
	});

	it('label wires aria-label on the shape group', () => {
		const { container } = render(Line, {
			from: [0, 0] as [number, number],
			to: [1, 1] as [number, number],
			label: 'arrow from client to server'
		});
		expect(container.querySelector('g')?.getAttribute('aria-label')).toBe(
			'arrow from client to server'
		);
	});

	it('zero-length line never emits NaN', () => {
		const { container } = render(Line, {
			from: [5, 5] as [number, number],
			to: [5, 5] as [number, number],
			arrow: 'both' as const
		});
		expect(container.innerHTML).not.toContain('NaN');
	});
});

describe('Curve', () => {
	it('renders a quadratic path with c1 only', () => {
		const { container } = render(Curve, {
			from: [0, 0] as [number, number],
			to: [100, 0] as [number, number],
			c1: [50, 100] as [number, number]
		});
		expect(container.querySelector('path')?.getAttribute('d')).toBe('M 0 0 Q 50 100 100 0');
	});

	it('renders a cubic path with c1 + c2', () => {
		const { container } = render(Curve, {
			from: [0, 0] as [number, number],
			to: [100, 0] as [number, number],
			c1: [0, 100] as [number, number],
			c2: [100, 100] as [number, number]
		});
		expect(container.querySelector('path')?.getAttribute('d')).toBe('M 0 0 C 0 100 100 100 100 0');
	});

	it('arrow="end" on a strongly-curved quadratic points along the END TANGENT, not the chord', () => {
		// c1 straight above `to`: the curve arrives moving straight down (+y)
		const { container } = render(Curve, {
			from: [0, 0] as [number, number],
			to: [100, 0] as [number, number],
			c1: [100, -100] as [number, number],
			arrow: 'end' as const,
			arrowSize: 20
		});
		const head = container.querySelector('polygon')!;
		// chord-angle head would be "100,0 80,10 80,-10"; tangent head points down
		expect(head.getAttribute('points')).toBe('100,0 90,-20 110,-20');
	});

	it('arrow="both": heads at both ends, shaft trimmed (no longer reaching the tips)', () => {
		const { container } = render(Curve, {
			from: [0, 0] as [number, number],
			to: [100, 0] as [number, number],
			c1: [50, 100] as [number, number],
			arrow: 'both' as const,
			arrowSize: 20
		});
		expect(container.querySelectorAll('polygon')).toHaveLength(2);
		const d = container.querySelector('path')?.getAttribute('d') ?? '';
		expect(d.startsWith('M 0 0')).toBe(false);
		expect(d.endsWith('100 0')).toBe(false);
	});

	it('degenerate curve (all points equal) never emits NaN', () => {
		const { container } = render(Curve, {
			from: [5, 5] as [number, number],
			to: [5, 5] as [number, number],
			c1: [5, 5] as [number, number],
			arrow: 'end' as const
		});
		expect(container.innerHTML).not.toContain('NaN');
	});
});

describe('Arc', () => {
	it('renders an SVG arc path from the bend', () => {
		const { container } = render(Arc, {
			from: [400, 540] as [number, number],
			to: [1500, 540] as [number, number],
			bend: 0.3
		});
		expect(container.querySelector('path')?.getAttribute('d')).toBe(
			'M 400 540 A 623.33 623.33 0 0 1 1500 540'
		);
	});

	it('bend={0} renders exactly the straight line', () => {
		const { container } = render(Arc, {
			from: [0, 0] as [number, number],
			to: [100, 0] as [number, number],
			bend: 0
		});
		expect(container.querySelector('path')?.getAttribute('d')).toBe('M 0 0 L 100 0');
	});

	it('arrow heads sit on the endpoints, pointing along the arc tangents', () => {
		// semicircle: leaves straight up from `from`, arrives straight down at `to`
		const { container } = render(Arc, {
			from: [0, 0] as [number, number],
			to: [100, 0] as [number, number],
			bend: 0.5,
			arrow: 'both' as const,
			arrowSize: 20
		});
		const heads = Array.from(container.querySelectorAll('polygon')).map((p) =>
			p.getAttribute('points')
		);
		expect(heads).toContain('100,0 90,-20 110,-20'); // end head arrives moving +y (down)
		expect(heads).toContain('0,0 -10,-20 10,-20'); // start head points back down the arc
	});

	it('never emits NaN for degenerate geometry', () => {
		const { container } = render(Arc, {
			from: [5, 5] as [number, number],
			to: [5, 5] as [number, number],
			bend: 0.5,
			arrow: 'both' as const
		});
		expect(container.innerHTML).not.toContain('NaN');
	});
});

describe('shape labels (labelText)', () => {
	it('Line: renders <text> at the perpendicular-offset midpoint', () => {
		const { container } = render(Line, {
			from: [0, 0] as [number, number],
			to: [100, 0] as [number, number],
			labelText: 'request'
		});
		const text = container.querySelector('text')!;
		expect(text.textContent).toBe('request');
		expect(text.getAttribute('x')).toBe('50');
		expect(text.getAttribute('y')).toBe('-20'); // default labelOffset 20, screen-up
		expect(text.getAttribute('text-anchor')).toBe('middle');
	});

	it('Arc: labelAt 0.5 places the text at the apex, off the stroke', () => {
		const { container } = render(Arc, {
			from: [400, 540] as [number, number],
			to: [1500, 540] as [number, number],
			bend: 0.3,
			labelText: 'round trip',
			labelAt: 0.5
		});
		const text = container.querySelector('text')!;
		expect(text.getAttribute('x')).toBe('950');
		expect(text.getAttribute('y')).toBe('190'); // apex 210, offset 20 outward
	});

	it('Curve: labelAt/labelOffset are honored', () => {
		const { container } = render(Curve, {
			from: [0, 0] as [number, number],
			to: [100, 0] as [number, number],
			c1: [50, 100] as [number, number],
			labelText: 'flow',
			labelAt: 0.5,
			labelOffset: -10
		});
		const text = container.querySelector('text')!;
		expect(text.getAttribute('x')).toBe('50');
		expect(text.getAttribute('y')).toBe('60'); // apex [50,50], negative offset goes +y
	});

	it('no labelText → no <text>; label stays aria-only', () => {
		const { container } = render(Line, {
			from: [0, 0] as [number, number],
			to: [1, 1] as [number, number],
			label: 'aria only'
		});
		expect(container.querySelector('text')).toBeNull();
		expect(container.querySelector('g')?.getAttribute('aria-label')).toBe('aria only');
	});
});

describe('Polyline', () => {
	const points: [number, number][] = [
		[100, 900],
		[400, 700],
		[700, 950]
	];

	it('renders straight segments by default', () => {
		const { container } = render(Polyline, { points });
		expect(container.querySelector('path')?.getAttribute('d')).toBe(
			'M 100 900 L 400 700 L 700 950'
		);
	});

	it('smooth renders cubic segments; close appends Z', () => {
		const { container } = render(Polyline, { points, smooth: true, close: true });
		const d = container.querySelector('path')?.getAttribute('d') ?? '';
		expect(d).toContain('C');
		expect(d.endsWith('Z')).toBe(true);
	});

	it('renders nothing for fewer than 2 points', () => {
		const { container } = render(Polyline, { points: [[5, 5]] as [number, number][] });
		expect(container.querySelector('path')).toBeNull();
	});
});

describe('Path (multi-segment stroke)', () => {
	const segments = [
		{ to: [500, 300] as [number, number] },
		{ to: [800, 150] as [number, number], c1: [650, 300] as [number, number] },
		{ to: [1150, 150] as [number, number], bend: 0.5 }
	];

	it('chains line + curve + arc into ONE continuous path (redundant Ms dropped)', () => {
		const { container } = render(Path, { start: [200, 300] as [number, number], segments });
		const d = container.querySelector('path')?.getAttribute('d') ?? '';
		expect(d.startsWith('M 200 300 L 500 300 Q 650 300 800 150 ')).toBe(true);
		expect(d).toContain(' A '); // the arc segment
		expect(d.match(/M /g)).toHaveLength(1); // a single sub-path, not one M per segment
	});

	it('uses round joins so segments meet instead of butting caps', () => {
		const { container } = render(Path, { start: [200, 300] as [number, number], segments });
		const path = container.querySelector('path')!;
		expect(path.getAttribute('stroke-linejoin')).toBe('round');
	});

	it('draws ONE arrowhead at the real end, its tip on the last `to`', () => {
		const { container } = render(Path, {
			start: [200, 300] as [number, number],
			segments,
			arrow: 'end' as const
		});
		const heads = container.querySelectorAll('polygon');
		expect(heads).toHaveLength(1); // not one head per shape
		expect(heads[0].getAttribute('points')).toContain('1150,150');
	});

	it('reveals the whole stroke as one draw-on; the head fades in last', () => {
		const { container } = render(Path, {
			start: [200, 300] as [number, number],
			segments,
			arrow: 'end' as const,
			draw: 2
		});
		const path = container.querySelector('path')!;
		expect(path.getAttribute('pathLength')).toBe('1');
		expect(path.getAttribute('class')).toContain('draw-anim');
		expect(path.getAttribute('style')).toContain('animation-duration: 2s');
		const head = container.querySelector('polygon')!;
		expect(head.getAttribute('style')).toContain('animation-delay: 1.6s');
	});

	it('renders a visible label as SVG text', () => {
		const { container } = render(Path, {
			start: [200, 300] as [number, number],
			segments,
			labelText: 'route'
		});
		expect(container.querySelector('text')?.textContent).toBe('route');
	});

	it('renders nothing for an empty segment list', () => {
		const { container } = render(Path, { start: [0, 0] as [number, number], segments: [] });
		expect(container.querySelector('path')).toBeNull();
	});
});

describe('Path geometry keyframes (stops + animate)', () => {
	const props = {
		start: [200, 300] as [number, number],
		segments: [{ to: [500, 300] }, { to: [800, 300] }] as { to: [number, number] }[],
		stops: [
			{ pct: 0, segments: [{ to: [500, 300] }, { to: [800, 300] }] },
			{ pct: 100, segments: [{ to: [500, 100] }, { to: [800, 100] }] }
		] as { pct: number; segments: { to: [number, number] }[] }[],
		animate: 4
	};

	it('emits SAMPLED d:path() keyframes per stop and binds the animation to the shaft', () => {
		const { container } = render(Path, props);
		const style = container.querySelector('g style')!;
		expect(style).not.toBeNull();
		// Both poses sampled from the same start; the 0% pose ends at y=300, the
		// 100% pose at y=100 — the sampled polylines share one command count, so
		// the browser morphs them.
		expect(style.textContent).toContain('d: path("M 200 300 ');
		expect(style.textContent).toContain('L 800 300");'); // 0% pose end
		expect(style.textContent).toContain('L 800 100");'); // 100% pose end
		const path = container.querySelector('path.draw-path-shaft')!;
		expect(path.getAttribute('style')).toMatch(/animation: draw-move-\d+ 4s ease-in-out both/);
		// the static (no-CSS) fallback stays the EXACT base geometry, not sampled
		expect(path.getAttribute('d')).toBe('M 200 300 L 500 300 L 800 300');
	});

	it('the arrowhead rides the moving end via transform keyframes', () => {
		const { container } = render(Path, { ...props, arrow: 'end' as const, arrowSize: 20 });
		const style = container.querySelector('g style')!;
		expect(style.textContent).toContain('translate(800px, 300px)'); // end @ 0%
		expect(style.textContent).toContain('translate(800px, 100px)'); // end @ 100%
		const head = container.querySelector('polygon')!;
		expect(head.getAttribute('points')).toBe('0,0 -20,10 -20,-10'); // tip at origin
		expect(head.getAttribute('style')).toMatch(/animation: draw-move-\d+-end 4s/);
	});

	it('a reveal track (drawn) keyframes stroke-dashoffset independently', () => {
		const { container } = render(Path, {
			start: [0, 0] as [number, number],
			segments: [{ to: [100, 0] }, { to: [100, 100] }] as { to: [number, number] }[],
			stops: [
				{ pct: 0, drawn: 0 },
				{ pct: 100, drawn: 1 }
			],
			animate: 3
		});
		const path = container.querySelector('path.draw-path-shaft')!;
		expect(path.getAttribute('pathLength')).toBe('1');
		const style = container.querySelector('g style')!.textContent ?? '';
		expect(style).toContain('-reveal {');
		expect(style).toContain('stroke-dashoffset: 1'); // 0% = undrawn
		expect(style).toContain('stroke-dashoffset: 0'); // 100% = fully drawn
	});

	it('stops take precedence over draw; fewer than 2 geom stops means no animation', () => {
		const both = render(Path, { ...props, draw: 1.5 });
		// geometry keyframes win: no flat draw-on reveal
		expect(both.container.querySelector('path.draw-path-shaft')?.getAttribute('pathLength')).toBeNull();
		const one = render(Path, {
			...props,
			stops: [{ pct: 0, segments: [{ to: [500, 300] }, { to: [800, 300] }] }]
		});
		expect(one.container.querySelector('g style')).toBeNull();
	});

	// The scrubbing demo (animation/path-move.html): a line+curve+arc chain whose
	// whole pose morphs AND draws itself in non-linearly (a `drawn` track). Pin
	// its exact props so the demo can't silently break.
	it('morphs a line+curve+arc chain with a reveal track (the path-move demo)', () => {
		const { container } = render(Path, {
			start: [260, 820] as [number, number],
			segments: [{ to: [700, 820] }, { to: [1140, 820], c1: [920, 820] }, { to: [1580, 820], bend: 0 }],
			stops: [
				{ pct: 0, segments: [{ to: [700, 820] }, { to: [1140, 820], c1: [920, 820] }, { to: [1580, 820], bend: 0 }], drawn: 0 },
				{ pct: 50, drawn: 0.75 },
				{ pct: 100, segments: [{ to: [700, 520] }, { to: [1140, 780], c1: [920, 320] }, { to: [1580, 540], bend: 0.55 }], drawn: 1 }
			],
			animate: 4,
			arrow: 'end' as const,
			labelText: 'route'
		});
		const shaft = container.querySelector('path.draw-path-shaft')!;
		const style = container.querySelector('g style')!.textContent ?? '';
		expect(style).toContain('@keyframes draw-move-');
		expect(style).toContain('d: path("M 260 820 '); // both poses start at the pinned start
		expect(style).toContain('translate(1580px, 820px)'); // arrowhead at the 0% (flat) end
		expect(style).toContain('translate(1580px, 540px)'); // arrowhead at the 100% (peaked) end
		// The arc's end tangent comes back un-normalized (426.84°); the head must
		// take the SHORT way (66.84°), never whirl a full turn.
		expect(style).toContain('rotate(66.84deg)');
		expect(style).not.toContain('426.84');
		// The reveal track: at the 50% keyframe the line is 75% drawn
		// (stroke-dashoffset 0.25), independent of the geometry morph.
		expect(style).toContain('-reveal {');
		expect(style).toContain('stroke-dashoffset: 0.25'); // 75% drawn at half-time
		expect(shaft.getAttribute('pathLength')).toBe('1');
		expect(shaft.getAttribute('style')).toMatch(/animation: draw-move-\d+ 4s ease-in-out both, draw-move-\d+-reveal 4s/);
	});
});

describe('animated arrowhead rotation is unwrapped (shortest path)', () => {
	// Without unwrapping, a rotation keyframe track interpolates the raw angle
	// numbers — an arc's un-normalized tangent or a branch-cut crossing then
	// whirls the head a full turn (or the long way) between stops. The head math
	// is shared, so this is checked on Arc and Curve (Path is covered above).
	it('Arc: an un-normalized arc tangent takes the short way, not a full spin', () => {
		const { container } = render(Arc, {
			from: [1140, 820] as [number, number],
			to: [1580, 820] as [number, number],
			bend: 0,
			stops: [
				{ pct: 0, from: [1140, 820] as [number, number], to: [1580, 820] as [number, number], bend: 0 },
				{ pct: 100, from: [1140, 780] as [number, number], to: [1580, 540] as [number, number], bend: 0.55 }
			],
			animate: 4,
			arrow: 'end' as const
		});
		const style = container.querySelector('g style')!.textContent ?? '';
		expect(style).toContain('rotate(0deg)');
		expect(style).toContain('rotate(66.84deg)'); // the short way
		expect(style).not.toContain('426.84'); // never the full-turn spin
	});

	it('Curve: the end tangent stays continuous across the ±180° branch cut', () => {
		const { container } = render(Curve, {
			from: [900, 500] as [number, number],
			to: [300, 500] as [number, number],
			c1: [600, 502] as [number, number],
			stops: [
				{ pct: 0, to: [300, 500] as [number, number], c1: [600, 508] as [number, number] },
				{ pct: 100, to: [300, 500] as [number, number], c1: [600, 492] as [number, number] }
			],
			animate: 4,
			arrow: 'end' as const
		});
		const style = container.querySelector('g style')!.textContent ?? '';
		expect(style).toContain('rotate(-178.47deg)');
		expect(style).toContain('rotate(-181.53deg)'); // stays negative — the short way
		expect(style).not.toContain('rotate(178.47deg)'); // NOT the +360° branch flip
	});
});

describe('draw-on animation', () => {
	it('draw sets pathLength=1, the animation class, and the duration inline', () => {
		const { container } = render(Line, {
			from: [0, 0] as [number, number],
			to: [100, 0] as [number, number],
			draw: 1.5
		});
		const path = container.querySelector('path')!;
		expect(path.getAttribute('pathLength')).toBe('1');
		expect(path.getAttribute('class')).toContain('draw-anim');
		expect(path.getAttribute('style')).toContain('animation-duration: 1.5s');
		expect(path.getAttribute('stroke-dasharray')).toBeNull(); // the animation owns the dash
	});

	it('arrowheads fade in over the final fifth of the duration', () => {
		const { container } = render(Line, {
			from: [0, 0] as [number, number],
			to: [100, 0] as [number, number],
			arrow: 'end' as const,
			draw: 2
		});
		const head = container.querySelector('polygon')!;
		expect(head.getAttribute('class')).toContain('head-anim');
		expect(head.getAttribute('style')).toContain('animation-delay: 1.6s');
		expect(head.getAttribute('style')).toContain('animation-duration: 0.4s');
	});

	it('applies to Curve, Arc, and Polyline too', () => {
		const curve = render(Curve, {
			from: [0, 0] as [number, number],
			to: [100, 0] as [number, number],
			c1: [50, 100] as [number, number],
			draw: 1
		});
		expect(curve.container.querySelector('path')?.getAttribute('pathLength')).toBe('1');
		const arc = render(Arc, {
			from: [0, 0] as [number, number],
			to: [100, 0] as [number, number],
			bend: 0.3,
			draw: 1
		});
		expect(arc.container.querySelector('path')?.getAttribute('pathLength')).toBe('1');
		const poly = render(Polyline, {
			points: [
				[0, 0],
				[50, 50],
				[100, 0]
			] as [number, number][],
			draw: 1
		});
		expect(poly.container.querySelector('path')?.getAttribute('pathLength')).toBe('1');
	});

	it('drawDelay staggers the shaft, and heads + labelText wait for it too', () => {
		const { container } = render(Line, {
			from: [0, 0] as [number, number],
			to: [100, 0] as [number, number],
			arrow: 'end' as const,
			labelText: 'step 2',
			draw: 2,
			drawDelay: 1
		});
		const path = container.querySelector('path')!;
		expect(path.getAttribute('style')).toContain('animation-delay: 1s');
		const head = container.querySelector('polygon')!;
		expect(head.getAttribute('style')).toContain('animation-delay: 2.6s'); // 1 + 2·0.8
		const text = container.querySelector('text')!;
		expect(text.getAttribute('class')).toContain('label-anim');
		expect(text.getAttribute('style')).toContain('animation-delay: 2.6s');
	});

	it('labelText without draw stays plain (no fade plumbing)', () => {
		const { container } = render(Line, {
			from: [0, 0] as [number, number],
			to: [100, 0] as [number, number],
			labelText: 'static'
		});
		expect(container.querySelector('text')!.getAttribute('class')).not.toContain('label-anim');
	});

	it('Rect and Ellipse trace their outlines too', () => {
		const rect = render(Rect, { x: 0, y: 0, width: 100, height: 50, draw: 1, drawDelay: 0.5 });
		const r = rect.container.querySelector('rect')!;
		expect(r.getAttribute('pathLength')).toBe('1');
		expect(r.getAttribute('class')).toContain('draw-anim');
		expect(r.getAttribute('style')).toContain('animation-duration: 1s');
		expect(r.getAttribute('style')).toContain('animation-delay: 0.5s');
		expect(r.getAttribute('stroke-dasharray')).toBeNull();

		const ellipse = render(Ellipse, { x: 0, y: 0, width: 100, height: 50, draw: 1 });
		const e = ellipse.container.querySelector('ellipse')!;
		expect(e.getAttribute('pathLength')).toBe('1');
		expect(e.getAttribute('class')).toContain('draw-anim');
	});

	it('no draw → no animation plumbing; invalid draw is ignored', () => {
		const plain = render(Line, { from: [0, 0] as [number, number], to: [1, 1] as [number, number] });
		expect(plain.container.querySelector('path')?.getAttribute('pathLength')).toBeNull();
		const bad = render(Line, {
			from: [0, 0] as [number, number],
			to: [1, 1] as [number, number],
			draw: NaN
		});
		expect(bad.container.querySelector('path')?.getAttribute('pathLength')).toBeNull();
	});
});

describe('geometry keyframes (stops + animate)', () => {
	const props = {
		from: [330, 812] as [number, number],
		to: [1420, 932] as [number, number],
		stops: [
			{ pct: 0, to: [1420, 932] as [number, number] },
			{ pct: 100, to: [1420, 392] as [number, number] }
		],
		animate: 4
	};

	it('emits d:path() keyframes per stop and binds the animation to the shaft', () => {
		const { container } = render(Line, props);
		const style = container.querySelector('g style')!;
		expect(style).not.toBeNull();
		expect(style.textContent).toContain('0% { d: path("M 330 812 L 1420 932"); }');
		expect(style.textContent).toContain('100% { d: path("M 330 812 L 1420 392"); }');
		const path = container.querySelector('path')!;
		expect(path.getAttribute('style')).toMatch(/animation: draw-move-\d+ 4s ease-in-out both/);
		// the static fallback (no-CSS d attribute) stays the base geometry
		expect(path.getAttribute('d')).toBe('M 330 812 L 1420 932');
	});

	it('the arrowhead rides the moving endpoint via transform keyframes', () => {
		const { container } = render(Line, { ...props, arrow: 'end' as const, arrowSize: 20 });
		const style = container.querySelector('g style')!;
		// shaft frames are shortened behind the head at EVERY stop
		expect(style.textContent).not.toContain('L 1420 932");');
		expect(style.textContent).toContain('translate(1420px, 932px)');
		expect(style.textContent).toContain('translate(1420px, 392px)');
		const head = container.querySelector('polygon')!;
		expect(head.getAttribute('points')).toBe('0,0 -20,10 -20,-10'); // tip on the origin
		expect(head.getAttribute('style')).toMatch(/animation: draw-move-\d+-end 4s/);
	});

	it('labelText rides along too', () => {
		const { container } = render(Line, { ...props, labelText: 'B' });
		const text = container.querySelector('text')!;
		expect(text.getAttribute('x')).toBe('0');
		expect(text.getAttribute('style')).toMatch(/animation: draw-move-\d+-label 4s/);
		expect(container.querySelector('g style')!.textContent).toContain(`-label {`);
	});

	it('stops take precedence over draw; fewer than 2 stops means no animation', () => {
		const both = render(Line, { ...props, draw: 1.5 });
		expect(both.container.querySelector('path')?.getAttribute('pathLength')).toBeNull();
		const one = render(Line, {
			from: [0, 0] as [number, number],
			to: [10, 0] as [number, number],
			stops: [{ pct: 0, to: [10, 0] as [number, number] }],
			animate: 2
		});
		expect(one.container.querySelector('g style')).toBeNull();
		expect(one.container.querySelector('path')?.getAttribute('style')).not.toContain('draw-move');
	});

	it('Line reveal keyframes stroke-dashoffset, independent of a geometry track', () => {
		const { container } = render(Line, {
			from: [0, 0] as [number, number],
			to: [100, 0] as [number, number],
			// geometry morphs to at 0/100; reveal-only keyframe at 60
			stops: [
				{ pct: 0, to: [100, 0] as [number, number], drawn: 0 },
				{ pct: 60, drawn: 0.5 },
				{ pct: 100, to: [100, 80] as [number, number], drawn: 1 }
			],
			animate: 3
		});
		const style = container.querySelector('g style')!.textContent!;
		expect(style).toContain('0% { d: path("M 0 0 L 100 0"); }'); // geometry track
		expect(style).not.toContain('60% { d: path'); // reveal-only stop is not a geometry keyframe
		expect(style).toContain('60% { stroke-dashoffset: 0.5; }'); // reveal track
		const s = container.querySelector('path')!.getAttribute('style')!;
		expect(s).toMatch(/animation: draw-move-\d+ 3s ease-in-out both, draw-move-\d+-reveal 3s/);
	});

	it('Arc reveal keyframes compose with a bend morph', () => {
		const { container } = render(Arc, {
			from: [0, 0] as [number, number],
			to: [100, 0] as [number, number],
			bend: 0.2,
			stops: [
				{ pct: 0, bend: 0.2, drawn: 0 },
				{ pct: 100, bend: 0.5, drawn: 1 }
			],
			animate: 4
		});
		const style = container.querySelector('g style')!.textContent!;
		expect(style).toMatch(/@keyframes draw-move-\d+ \{ 0% \{ d: path\("M 0 0 L/); // sampled geometry
		expect(style).toContain('0% { stroke-dashoffset: 1; }'); // reveal
		expect(style).toContain('100% { stroke-dashoffset: 0; }');
	});

	it('per-stop ease emits animation-timing-function inside that keyframe', () => {
		const { container } = render(Curve, {
			from: [0, 0] as [number, number],
			to: [100, 0] as [number, number],
			c1: [50, 50] as [number, number],
			stops: [
				{ pct: 0, c1: [50, 50] as [number, number], drawn: 0, ease: 'ease-in' },
				{ pct: 100, c1: [50, -50] as [number, number], drawn: 1, ease: 'linear' }
			],
			animate: 4
		});
		const style = container.querySelector('g style')!.textContent!;
		// the timing function rides both the geometry (d) and reveal frames
		expect(style).toContain('0% { d: path("M 0 0 Q 50 50 100 0"); animation-timing-function: ease-in; }');
		expect(style).toContain('0% { stroke-dashoffset: 1; animation-timing-function: ease-in; }');
		expect(style).toContain('animation-timing-function: linear;'); // the 100% stop
	});

	it('a malicious ease is sanitized away (no CSS injection)', () => {
		const { container } = render(Curve, {
			from: [0, 0] as [number, number],
			to: [100, 0] as [number, number],
			c1: [50, 50] as [number, number],
			stops: [
				{ pct: 0, c1: [50, 50] as [number, number], ease: 'ease-in} body{display:none}' },
				{ pct: 100, c1: [50, -50] as [number, number] }
			],
			animate: 4
		});
		const style = container.querySelector('g style')!.textContent!;
		expect(style).not.toContain('body{display:none}');
		expect(style).not.toContain('animation-timing-function: ease-in}');
	});

	it('Curve reveal keyframes stroke-dashoffset (non-linear draw progress)', () => {
		const { container } = render(Curve, {
			from: [300, 800] as [number, number],
			to: [1500, 500] as [number, number],
			c1: [900, 640] as [number, number],
			stops: [
				{ pct: 0, drawn: 0 },
				{ pct: 75, drawn: 0.5 },
				{ pct: 100, drawn: 1 }
			],
			animate: 4
		});
		const style = container.querySelector('g style')!;
		// drawn → dashoffset = 1 − drawn
		expect(style.textContent).toContain('0% { stroke-dashoffset: 1; }');
		expect(style.textContent).toContain('75% { stroke-dashoffset: 0.5; }');
		expect(style.textContent).toContain('100% { stroke-dashoffset: 0; }');
		const path = container.querySelector('path')! as SVGPathElement;
		expect(path.getAttribute('pathLength')).toBe('1');
		expect(path.style.strokeDasharray).toBe('1');
		expect(path.getAttribute('style')).toMatch(/animation: draw-move-\d+-reveal 4s/);
	});

	it('Curve composes a geometry morph with a reveal track on one timeline', () => {
		const { container } = render(Curve, {
			from: [300, 800] as [number, number],
			to: [1500, 500] as [number, number],
			c1: [900, 640] as [number, number],
			// one stops array: geometry keyframes at 0/100 (c1), reveal at 0/75/100
			stops: [
				{ pct: 0, c1: [900, 640] as [number, number], drawn: 0 },
				{ pct: 75, drawn: 0.5 },
				{ pct: 100, c1: [700, 150] as [number, number], drawn: 1 }
			],
			animate: 4
		});
		const style = container.querySelector('g style')!.textContent!;
		expect(style).toContain('0% { d: path("M 300 800 Q 900 640 1500 500"); }'); // geometry track (quadratic)
		expect(style).not.toContain('75% { d: path'); // the reveal-only 75% stop is NOT a geometry keyframe
		expect(style).toContain('75% { stroke-dashoffset: 0.5; }'); // reveal track
		// shaft runs BOTH animations
		const s = container.querySelector('path')!.getAttribute('style')!;
		expect(s).toMatch(/animation: draw-move-\d+ 4s ease-in-out both, draw-move-\d+-reveal 4s/);
	});

	it('Arc keyframes a bend change as a fixed-count sampled polyline', () => {
		const { container } = render(Arc, {
			from: [0, 0] as [number, number],
			to: [100, 0] as [number, number],
			bend: 0.3,
			stops: [{ pct: 0, bend: 0.3 }, { pct: 100, bend: -0.3 }],
			animate: 3
		});
		const style = container.querySelector('g style')!;
		expect(style).not.toBeNull();
		// same command count at both stops → interpolable; sampled to a polyline
		const seg = (frag: string) => (style.textContent!.match(new RegExp(`${frag}[^}]*`))![0].match(/L /g) || []).length;
		expect(seg('0% \\{ d: path')).toBe(64);
		expect(seg('100% \\{ d: path')).toBe(64);
		// apex above the chord at 0% (bend +0.3), below at 100% (bend −0.3)
		expect(style.textContent).toContain('L 50 -30'); // 0% apex
		expect(style.textContent).toContain('L 50 30'); // 100% apex
		expect(container.querySelector('path')?.getAttribute('style')).toMatch(/animation: draw-move-\d+ 3s/);
	});

	it('Curve keyframes a cubic: control points animate, structure stays C', () => {
		const { container } = render(Curve, {
			from: [0, 0] as [number, number],
			to: [300, 0] as [number, number],
			c1: [100, 100] as [number, number],
			c2: [200, 100] as [number, number],
			stops: [
				{ pct: 0, c1: [100, 100] as [number, number] },
				{ pct: 100, c1: [100, -100] as [number, number] }
			],
			animate: 3
		});
		const style = container.querySelector('g style')!;
		expect(style.textContent).toContain('0% { d: path("M 0 0 C 100 100 200 100 300 0"); }');
		expect(style.textContent).toContain('100% { d: path("M 0 0 C 100 -100 200 100 300 0"); }');
		expect(container.querySelector('path')?.getAttribute('style')).toMatch(
			/animation: draw-move-\d+ 3s/
		);
	});
});

describe('Rect', () => {
	it('renders Block-shaped box geometry with rounded corners', () => {
		const { container } = render(Rect, { x: 860, y: 480, width: 400, height: 120, rounded: 12 });
		const rect = container.querySelector('rect')!;
		expect(rect.getAttribute('x')).toBe('860');
		expect(rect.getAttribute('y')).toBe('480');
		expect(rect.getAttribute('width')).toBe('400');
		expect(rect.getAttribute('height')).toBe('120');
		expect(rect.getAttribute('rx')).toBe('12');
	});

	it('defaults to no rounding and no fill', () => {
		const { container } = render(Rect, { x: 0, y: 0, width: 10, height: 10 });
		const rect = container.querySelector('rect')!;
		expect(rect.getAttribute('rx')).toBeNull();
		expect(rect.getAttribute('style')).toContain('var(--draw-fill, none)');
	});

	it('fill/color/label props override the defaults', () => {
		const { container } = render(Rect, {
			x: 0,
			y: 0,
			width: 10,
			height: 10,
			fill: '#123456',
			color: 'red',
			label: 'a frame'
		});
		const rect = container.querySelector('rect')!;
		const style = rect.getAttribute('style') ?? '';
		expect(style).toContain('fill: #123456');
		expect(style).toContain('stroke: red');
		expect(rect.getAttribute('aria-label')).toBe('a frame');
	});

	it('zero-size and non-finite geometry never emits negatives or NaN', () => {
		const { container } = render(Rect, { x: NaN, y: 0, width: -5, height: NaN });
		const rect = container.querySelector('rect')!;
		expect(rect.getAttribute('width')).toBe('0');
		expect(rect.getAttribute('height')).toBe('0');
		expect(container.innerHTML).not.toContain('NaN');
	});
});

describe('Ellipse', () => {
	it('inscribes the ellipse in the given box', () => {
		const { container } = render(Ellipse, { x: 1300, y: 200, width: 360, height: 200 });
		const el = container.querySelector('ellipse')!;
		expect(el.getAttribute('cx')).toBe('1480'); // 1300 + 360/2
		expect(el.getAttribute('cy')).toBe('300'); // 200 + 200/2
		expect(el.getAttribute('rx')).toBe('180');
		expect(el.getAttribute('ry')).toBe('100');
	});

	it('dash and thickness wire through', () => {
		const { container } = render(Ellipse, {
			x: 0,
			y: 0,
			width: 10,
			height: 10,
			dash: true,
			thickness: 8
		});
		const el = container.querySelector('ellipse')!;
		expect(el.getAttribute('stroke-dasharray')).toBe('12 8');
		expect(el.getAttribute('style')).toContain('stroke-width: 8');
	});

	it('defaults inherit the --draw-* custom properties', () => {
		const { container } = render(Ellipse, { x: 0, y: 0, width: 10, height: 10 });
		const style = container.querySelector('ellipse')?.getAttribute('style') ?? '';
		expect(style).toContain('var(--draw-stroke, currentColor)');
		expect(style).toContain('var(--draw-thickness, 4)');
		expect(style).toContain('var(--draw-fill, none)');
	});

	it('zero-size box collapses to a point, never NaN', () => {
		const { container } = render(Ellipse, { x: 5, y: 5, width: 0, height: NaN });
		const el = container.querySelector('ellipse')!;
		expect(el.getAttribute('rx')).toBe('0');
		expect(el.getAttribute('ry')).toBe('0');
		expect(container.innerHTML).not.toContain('NaN');
	});
});
