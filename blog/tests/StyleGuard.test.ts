import { render } from '@testing-library/svelte';
import { get } from 'svelte/store';
import { tick } from 'svelte';
import { beforeEach, describe, expect, it } from 'vitest';
import Block from '../src/lib/components/Block.svelte';
import DrawHost from './StyleIdClassDrawHost.svelte';
import { adjustChanges } from '../src/lib/stores/adjustChanges';
import { adjustMode, canAdjust } from '../src/lib/stores/adjustMode';

const box = (container: HTMLElement) => container.querySelector('.movable') as HTMLElement;

/** ADJUST chrome only renders when the control is BOTH available and switched on. */
async function enterLayoutMode() {
	canAdjust.set(true);
	adjustMode.set(true);
	await tick();
}

beforeEach(() => {
	canAdjust.set(false);
	adjustMode.set(false);
});

describe('Block — the props own the geometry', () => {
	it('the box renders at x/y even when the style declares left/top', async () => {
		// THE BUG THIS FIXES: both declarations used to land in one inline style
		// block, where the last one wins — so the author's `left` replaced x={200}
		// outright and the box could not be dragged anywhere.
		const { container } = render(Block, {
			props: { name: 'db', x: 200, y: 300, width: 400, height: 160, style: 'left: 40px; top: 9px' }
		});
		const el = box(container);
		expect(el.style.left).toBe('200px');
		expect(el.style.top).toBe('300px');
	});

	it('a reserved declaration never reaches the DOM at all', () => {
		const { container } = render(Block, {
			props: { x: 200, y: 300, width: 400, height: 160, style: 'width: 50px; height: 10px' }
		});
		const el = box(container);
		expect(el.style.width).toBe('400px');
		expect(el.style.height).toBe('160px');
	});

	it('dragging a style-pinned Block actually moves it — the geometry is authoritative', async () => {
		// The whole point: x is free to change and the paint follows it. Before the
		// guard, x changed and the box stayed put, which is what made ADJUST look broken.
		const { container, rerender } = render(Block, {
			props: { x: 200, y: 300, width: 400, height: 160, style: 'left: 40px' }
		});
		expect(box(container).style.left).toBe('200px');
		await rerender({ x: 640, y: 300, width: 400, height: 160, style: 'left: 40px' });
		expect(box(container).style.left).toBe('640px');
	});

	it('cosmetics still win, exactly as before', () => {
		const { container } = render(Block, {
			props: {
				x: 10, y: 20, width: 100, height: 50,
				style: 'left: 40px; border: 2px dashed red; opacity: 0.5'
			}
		});
		const el = box(container);
		expect(el.style.left).toBe('10px'); // reserved -> stripped
		expect(el.style.borderStyle).toBe('dashed'); // cosmetic -> applied
		expect(el.style.opacity).toBe('0.5');
	});

	it('a decorative transform is untouched — rotate is not a collision', () => {
		const { container } = render(Block, {
			props: { x: 10, y: 20, width: 100, height: 50, style: 'transform: rotate(3deg)' }
		});
		expect(box(container).style.transform).toBe('rotate(3deg)');
	});

	it('leaves an ordinary Block byte-for-byte alone (no style prop, no surprises)', () => {
		const { container } = render(Block, { props: { x: 10, y: 20, width: 100, height: 50 } });
		const el = box(container);
		expect(el.style.left).toBe('10px');
		expect(el.getAttribute('style')).not.toContain('undefined');
		expect(el.innerHTML).not.toContain('NaN');
	});
});

describe('Block — the ADJUST badge', () => {
	it('says which property was ignored, and why', async () => {
		const { container } = render(Block, {
			props: { name: 'db', x: 200, y: 300, width: 400, height: 160, style: 'left: 40px' }
		});
		await enterLayoutMode();
		const warn = container.querySelector('.style-warn') as HTMLElement;
		expect(warn).toBeTruthy();
		expect(warn.textContent).toContain('left');
		expect(warn.textContent).toContain('ignored');
	});

	it('warns that a translate displaces the box from its anchors, without stripping it', async () => {
		const { container } = render(Block, {
			props: { x: 200, y: 300, width: 400, height: 160, style: 'transform: translateX(40px)' }
		});
		await enterLayoutMode();
		const warn = container.querySelector('.style-warn') as HTMLElement;
		expect(warn.textContent).toContain('transform');
		// Reported, not confiscated — the transform is still applied.
		expect(box(container).style.transform).toBe('translateX(40px)');
	});

	it('badges a HOSTED shape’s style (a Draw Rect/Ellipse) on the Block you drag', async () => {
		const { container } = render(Block, {
			props: { tag: 'Rect', track: false, x: 0, y: 0, width: 100, height: 50, hostStyle: 'width: 50px' }
		});
		await enterLayoutMode();
		expect((container.querySelector('.style-warn') as HTMLElement).textContent).toContain('width');
	});

	it('shows NO badge for a clean style — a false warning is worse than the bug', async () => {
		const { container } = render(Block, {
			props: { x: 0, y: 0, width: 100, height: 50, style: 'border: 1px solid red; margin: 0; right: 0' }
		});
		await enterLayoutMode();
		expect(container.querySelector('.style-warn')).toBeNull();
	});

	it('shows no badge outside ADJUST mode — the chrome never reaches an audience', async () => {
		const { container } = render(Block, {
			props: { x: 0, y: 0, width: 100, height: 50, style: 'left: 40px' }
		});
		await tick();
		expect(container.querySelector('.style-warn')).toBeNull();
	});
});

// The Draw box shapes are the OTHER draggable geometry. They carry x/y/width/height
// as SVG PRESENTATION attributes — the weakest style there is, outranked by any css,
// an inline `style` included. So `style="width: 50px"` on a <Rect> would silently
// cancel the box, and the ADJUST Block hosting it would drag something that never
// moves: the same bug as Block's, through a different door. Same rule, same core.
describe('Draw shapes — the props own the geometry there too', () => {
	it('Rect: a reserved property never reaches the SVG, so the presentation attrs stand', () => {
		const { container } = render(DrawHost, {
			props: { which: 'Rect', style: 'width: 50px; height: 5px; stroke-dasharray: 4 2' }
		});
		const rect = container.querySelector('rect.draw-rect') as SVGRectElement;
		expect(rect.getAttribute('width')).toBe('80'); // the prop, intact
		expect(rect.getAttribute('height')).toBe('40');
		const style = rect.getAttribute('style') ?? '';
		expect(style).not.toContain('width: 50px');
		expect(style).not.toContain('height: 5px');
		expect(style).toContain('stroke-dasharray: 4 2'); // cosmetics survive
	});

	// `rx` (corner rounding on Rect, a radius on Ellipse) is deliberately NOT reserved,
	// and that is pinned in tests/styleGuardCore.test.ts rather than here: Svelte assigns
	// the style through the CSSOM, and jsdom's css parser silently DROPS properties it
	// doesn't know — rx among them — so a DOM assertion would pass or fail on jsdom's
	// vocabulary instead of on the guard. The core is where that contract is real.

	it('Ellipse: strips the reserved box properties, keeps the cosmetics', () => {
		const { container } = render(DrawHost, {
			props: { which: 'Ellipse', style: 'left: 40px; width: 5px; stroke: red' }
		});
		const style = container.querySelector('ellipse.draw-ellipse')?.getAttribute('style') ?? '';
		expect(style).not.toContain('left: 40px');
		expect(style).not.toContain('width: 5px');
		expect(style).toContain('stroke: red');
	});

	it('leaves a shape with a purely cosmetic style completely alone', () => {
		const { container } = render(DrawHost, {
			props: { which: 'Rect', style: 'opacity: 0.5; transform: rotate(3deg)' }
		});
		const style = container.querySelector('rect.draw-rect')?.getAttribute('style') ?? '';
		expect(style).toContain('opacity: 0.5');
		expect(style).toContain('rotate(3deg)');
	});
});

describe('Block — the author’s source is not touched', () => {
	it('the save patch emits the style verbatim, reserved declaration and all', async () => {
		// Reserving changes what RENDERS, never what the author wrote. The emitted tag
		// hands the original string back, so a drag can never silently delete it.
		render(Block, {
			props: { name: 'db', x: 200, y: 300, width: 400, height: 160, style: 'left: 40px; color: red' }
		});
		await enterLayoutMode();
		const tag = [...get(adjustChanges).values()].find((e) => e.name === 'db')?.newTag ?? '';
		expect(tag).toContain('style="left: 40px; color: red"');
		expect(tag).toContain('x={200}');
	});
});
