// Shared pointer-drag helper for ADJUST-mode gestures.
//
// The live-scale drag math (screen-px pointer deltas ÷ the element's rendered
// scale, pointer capture, window listener teardown, Esc-cancel) used to exist
// three times — Block's move/resize, KeyframeStudio's rotate grip, and
// KeyframeStudio's panel drag. This is the single implementation; Draw's
// shape handles are its fourth consumer.
//
// Scale: an element's LIVE rendered scale is getBoundingClientRect().width /
// offsetWidth — how many screen px equal one canvas px right now, in any
// display mode (FITTED or SCALED at any zoom). SVG elements have no
// offsetWidth, so `scaleFrom` also accepts a function returning the scale
// (e.g. svg rect width ÷ viewBox width). Omit it for raw screen-px deltas.

export interface TrackPointerOptions {
	/** Where the screen→canvas scale comes from: an HTML element measured live
	 *  (rect.width / offsetWidth), or a function returning the scale directly.
	 *  Omitted → 1 (deltas stay in screen px). Read once, at gesture start. */
	scaleFrom?: HTMLElement | (() => number);
	/** Every pointermove: cumulative canvas-px deltas from the gesture start,
	 *  plus the raw event (for clientX/clientY, shiftKey, altKey…). */
	onMove: (dx: number, dy: number, event: PointerEvent) => void;
	/** Pointer released — commit the gesture (record undo, etc.). NOT called
	 *  after an Esc cancel. */
	onEnd?: () => void;
	/** Esc pressed mid-gesture — restore the start state. The Esc listener is
	 *  only installed when this is provided (capture phase, stopped, so it
	 *  doesn't also trip an ancestor's Escape handler). */
	onCancel?: () => void;
}

/** Track one pointer gesture from its initiating pointerdown event:
 *  captures the pointer, streams scale-corrected deltas to onMove, and tears
 *  every listener down on pointerup (→ onEnd) or Esc (→ onCancel). */
export function trackPointer(event: PointerEvent, opts: TrackPointerOptions): void {
	const { scaleFrom, onMove, onEnd, onCancel } = opts;
	const scale =
		typeof scaleFrom === 'function'
			? scaleFrom() || 1
			: scaleFrom
				? scaleFrom.getBoundingClientRect().width / scaleFrom.offsetWidth || 1
				: 1;
	const startX = event.clientX;
	const startY = event.clientY;
	const target = event.target as Element | null;
	const pid = event.pointerId;

	const move = (e: PointerEvent) =>
		onMove((e.clientX - startX) / scale, (e.clientY - startY) / scale, e);
	const up = () => {
		teardown();
		onEnd?.();
	};
	const key = (e: KeyboardEvent) => {
		if (e.key !== 'Escape') return;
		e.preventDefault();
		e.stopPropagation();
		teardown();
		onCancel?.();
	};
	function teardown() {
		window.removeEventListener('pointermove', move);
		window.removeEventListener('pointerup', up);
		if (onCancel) window.removeEventListener('keydown', key, true);
		target?.releasePointerCapture?.(pid);
	}

	target?.setPointerCapture?.(pid);
	window.addEventListener('pointermove', move);
	window.addEventListener('pointerup', up);
	if (onCancel) window.addEventListener('keydown', key, true);
}
