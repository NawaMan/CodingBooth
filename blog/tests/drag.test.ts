import { describe, expect, it, vi } from 'vitest';
import { trackPointer } from '../src/lib/utils/drag';

// jsdom has no PointerEvent; the helper only reads clientX/clientY/target/
// pointerId from the initiating event and clientX/clientY/modifiers from the
// window moves, so MouseEvent (plus a cast) is a faithful stand-in.
function down(clientX = 0, clientY = 0): PointerEvent {
	return {
		clientX,
		clientY,
		target: document.createElement('div'),
		pointerId: 1
	} as unknown as PointerEvent;
}
const moveTo = (clientX: number, clientY: number, init: MouseEventInit = {}) =>
	window.dispatchEvent(new MouseEvent('pointermove', { clientX, clientY, ...init }));
const release = () => window.dispatchEvent(new MouseEvent('pointerup'));
const escape = () => window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));

describe('trackPointer', () => {
	it('streams cumulative deltas divided by the live scale', () => {
		const moves: Array<[number, number]> = [];
		trackPointer(down(100, 100), {
			scaleFrom: () => 2, // 2 screen px per canvas px
			onMove: (dx, dy) => moves.push([dx, dy])
		});
		moveTo(110, 104);
		moveTo(120, 90);
		release();
		expect(moves).toEqual([
			[5, 2],
			[10, -5]
		]);
	});

	it('defaults to scale 1 and calls onEnd exactly once on pointerup', () => {
		const onMove = vi.fn();
		const onEnd = vi.fn();
		trackPointer(down(0, 0), { onMove, onEnd });
		moveTo(7, 3);
		release();
		expect(onMove).toHaveBeenLastCalledWith(7, 3, expect.anything());
		expect(onEnd).toHaveBeenCalledTimes(1);
		// torn down: further moves/ups are ignored
		moveTo(50, 50);
		release();
		expect(onMove).toHaveBeenCalledTimes(1);
		expect(onEnd).toHaveBeenCalledTimes(1);
	});

	it('Esc cancels: onCancel fires, onEnd does not, listeners are torn down', () => {
		const onMove = vi.fn();
		const onEnd = vi.fn();
		const onCancel = vi.fn();
		trackPointer(down(0, 0), { onMove, onEnd, onCancel });
		moveTo(10, 0);
		escape();
		expect(onCancel).toHaveBeenCalledTimes(1);
		expect(onEnd).not.toHaveBeenCalled();
		moveTo(99, 99);
		release();
		expect(onMove).toHaveBeenCalledTimes(1);
		expect(onEnd).not.toHaveBeenCalled(); // gesture already dead
	});

	it('without onCancel, Esc is not intercepted and the gesture continues', () => {
		const onMove = vi.fn();
		const onEnd = vi.fn();
		trackPointer(down(0, 0), { onMove, onEnd });
		escape(); // no Esc listener installed — nothing happens
		moveTo(5, 5);
		release();
		expect(onMove).toHaveBeenCalledTimes(1);
		expect(onEnd).toHaveBeenCalledTimes(1);
	});

	it('passes the raw event through to onMove (modifiers, client coords)', () => {
		let shift = false;
		trackPointer(down(0, 0), {
			onMove: (_dx, _dy, e) => (shift = e.shiftKey)
		});
		moveTo(1, 1, { shiftKey: true });
		release();
		expect(shift).toBe(true);
	});
});
