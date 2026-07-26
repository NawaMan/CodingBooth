<!--
  ScrollDiv — a clipped viewport whose oversized content is panned with the
  mouse wheel by a CSS transform (NOT native overflow scrolling).

  Why a transform and not `overflow: auto`? The whole deck is a fixed 1920×1080
  canvas that SlideDeck transform-`scale()`s to fit (FITTED) or zoom (SCALED).
  Native scrollbars inside a scaled canvas render at the wrong size and, in
  SCALED mode, fight the deck's own scroll-based panning. Panning the inner box
  with a transform keeps everything in canvas coordinates and crisp at any zoom.

  `axis` selects the scrolling direction:
      "x"    — horizontal only (this is the legacy WideDiv behaviour)
      "y"    — vertical only
      "both" — deltaX pans X, deltaY pans Y; hold SHIFT to pan X with a plain
               (vertical-only) mouse wheel

  Note: while hovered, this captures the wheel on its scrolling axis, so in
  SCALED zoom the deck won't pan on that axis until the pointer leaves it.
-->
<script lang="ts">
	export let axis: 'x' | 'y' | 'both' = 'x';

	// The clipped window. The slot content lives in an inner box of inner*
	// size; on a non-scrolling axis the inner box defaults to the window size,
	// so there is simply nothing to pan there.
	export let outerWidth:  string;
	export let outerHeight: string;
	export let innerWidth:  string | undefined = undefined;
	export let innerHeight: string | undefined = undefined;

	export let scrollable: boolean = true;

	// Per-axis start offset and bounds. An `undefined` bound falls back to a
	// default range derived from the content extent (see boundsFor) — the same
	// -25%..+75% envelope the original WideDiv used.
	export let startX: number = 0;
	export let startY: number = 0;
	export let minX: number | undefined = undefined;
	export let maxX: number | undefined = undefined;
	export let minY: number | undefined = undefined;
	export let maxY: number | undefined = undefined;

	// Fired on every wheel/drag with the raw pixel offset AND the normalized
	// 0..1 progress along each axis (progX/progY) — the latter is what you wire to
	// a scroll-driven animation (e.g. AnimationBar's seekFraction), since it is
	// already mapped onto the pan bounds and independent of the content size.
	export let onScroll: (
		target: EventTarget | null,
		position: { x: number; y: number; progX: number; progY: number },
	) => void = () => {};

	// Show a draggable scrollbar on each scrolling axis that overflows. Purely
	// visual/affordance — the wheel still works. (We draw our own because the
	// transform-pan has no native scrollbar; see the header note.)
	export let scrollbar: boolean = false;

	/** Inline style for the root element, applied last so it wins. */
	export let style: string = '';
	/** DOM id for the root element. */
	export let id: string = '';
	/** Extra class(es) for the root element. NOTE: a slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS (global.css / roles.css / a
	    :global(...) block) or a utility class. See AGENTS.md. */
	let klass: string = '';
	export { klass as class };

	let scrollX = startX;
	let scrollY = startY;
	let trackXEl: HTMLDivElement;
	let trackYEl: HTMLDivElement;

	$: scrollsX = axis === 'x' || axis === 'both';
	$: scrollsY = axis === 'y' || axis === 'both';

	$: innerW = innerWidth  ?? outerWidth;
	$: innerH = innerHeight ?? outerHeight;

	// Default pan envelope along one axis: -25%..+75% of the content extent.
	function boundsFor(extent: string, min: number | undefined, max: number | undefined) {
		const size = parseInt(extent);
		return {
			min: min === undefined ? size * -0.25 : min,
			max: max === undefined ? size *  0.75 : max,
		};
	}
	$: bX = boundsFor(innerW, minX, maxX);
	$: bY = boundsFor(innerH, minY, maxY);

	const clamp01 = (v: number) => Math.max(0, Math.min(1, v));

	// Scrollbar geometry, as fractions of the track (0..1). Thumb length is the
	// visible/content ratio; thumb offset is how far through the pan range we are.
	$: thumbFracX = clamp01(parseInt(outerWidth)  / parseInt(innerW));
	$: thumbFracY = clamp01(parseInt(outerHeight) / parseInt(innerH));
	// 0..1 progress along each axis. Computed via plain functions (not only the
	// reactive `progX`/`progY`) so an event handler can read the up-to-date value
	// right after mutating scrollX/scrollY, before Svelte flushes reactivity.
	const progressX = (x: number) => (bX.max > bX.min ? clamp01((x - bX.min) / (bX.max - bX.min)) : 0);
	const progressY = (y: number) => (bY.max > bY.min ? clamp01((y - bY.min) / (bY.max - bY.min)) : 0);
	$: progX = progressX(scrollX);
	$: progY = progressY(scrollY);
	$: showX = scrollbar && scrollsX && thumbFracX < 1;
	$: showY = scrollbar && scrollsY && thumbFracY < 1;

	function handleScroll(event: WheelEvent) {
		if (!scrollable) return;

		// A plain mouse wheel only reports deltaY. Shift+wheel is the conventional
		// "scroll horizontally" gesture (some browsers already map it to deltaX),
		// so when X is in play, route the vertical wheel to X and leave Y alone —
		// the only way to reach the X axis with a 1-D wheel when axis="both".
		const shiftToX = event.shiftKey && scrollsX;

		if (scrollsX) {
			// Real horizontal intent (trackpad / 2-D wheel) wins; otherwise take
			// the vertical wheel when shift is held, or — for an x-only scroller —
			// always (a plain wheel reports vertical movement only).
			const delta =
				event.deltaX != 0          ? event.deltaX :
				shiftToX || !scrollsY      ? event.deltaY : 0;
			scrollX = Math.min(bX.max, Math.max(bX.min, scrollX + delta / 2));
		}
		if (scrollsY && !shiftToX) {
			scrollY = Math.min(bY.max, Math.max(bY.min, scrollY + event.deltaY / 2));
		}

		onScroll(event.target, { x: scrollX, y: scrollY, progX: progressX(scrollX), progY: progressY(scrollY) });
	}

	// Drag a scrollbar thumb. We map screen-pixel pointer movement onto the pan
	// range via the track's measured length, so it stays correct regardless of
	// the deck's SCALED zoom factor (getBoundingClientRect is post-transform).
	function dragThumb(isX: boolean, track: HTMLElement, e: PointerEvent) {
		if (!scrollable) return;
		e.preventDefault();
		e.stopPropagation();
		const thumb = e.currentTarget as HTMLElement;
		const rect = track.getBoundingClientRect();
		const trackPx = isX ? rect.width : rect.height;
		const travelPx = trackPx * (1 - (isX ? thumbFracX : thumbFracY)); // movable px
		const span = (isX ? bX.max : bY.max) - (isX ? bX.min : bY.min);
		const start = isX ? e.clientX : e.clientY;
		const from  = isX ? scrollX : scrollY;
		thumb.setPointerCapture(e.pointerId);

		const move = (ev: PointerEvent) => {
			const d = (isX ? ev.clientX : ev.clientY) - start;
			const next = from + (travelPx > 0 ? (d / travelPx) * span : 0);
			if (isX) scrollX = Math.min(bX.max, Math.max(bX.min, next));
			else     scrollY = Math.min(bY.max, Math.max(bY.min, next));
			onScroll(ev.target, { x: scrollX, y: scrollY, progX: progressX(scrollX), progY: progressY(scrollY) });
		};
		const up = () => {
			thumb.releasePointerCapture(e.pointerId);
			thumb.removeEventListener('pointermove', move);
			thumb.removeEventListener('pointerup', up);
		};
		thumb.addEventListener('pointermove', move);
		thumb.addEventListener('pointerup', up);
	}
</script>

<!--
  The scroll state is published as CSS custom properties on `.outer` (which is NOT
  transform-panned): `--scroll-x`/`--scroll-y` (pixels) and `--prog-x`/`--prog-y`
  (0..1). `.inner` inherits and consumes the pixel vars for its pan transform; a
  `foreground` slot — overlaid and pinned, so it does NOT pan with the content —
  can read the same vars to move at a ratio of the scroll in pure CSS, e.g.
      <div slot="foreground" style="left: calc(var(--prog-x) * 100%)"> … </div>
-->
<div class="outer {klass}"
     id={id || undefined}
     on:wheel={handleScroll}
     style="width: {outerWidth}px; height: {outerHeight}px; --scroll-x: {scrollX}; --scroll-y: {scrollY}; --prog-x: {progX}; --prog-y: {progY}; {style}"
     {...$$restProps}>
	<div
		class="inner"
		style="width: {innerW}px; height: {innerH}px;">
		<slot></slot>
	</div>

	{#if $$slots.foreground}
	<div class="foreground"><slot name="foreground"></slot></div>
	{/if}

	{#if showX}
	<div class="scrollbar sb-x" class:inset={showY} bind:this={trackXEl}>
		<div class="thumb" role="slider" aria-label="Scroll horizontally" aria-orientation="horizontal"
		     aria-valuemin="0" aria-valuemax="100" aria-valuenow={Math.round(progX * 100)} tabindex="-1"
		     style="left: {progX * (1 - thumbFracX) * 100}%; width: {thumbFracX * 100}%;"
		     on:pointerdown={(e) => dragThumb(true, trackXEl, e)}></div>
	</div>
	{/if}
	{#if showY}
	<div class="scrollbar sb-y" class:inset={showX} bind:this={trackYEl}>
		<div class="thumb" role="slider" aria-label="Scroll vertically" aria-orientation="vertical"
		     aria-valuemin="0" aria-valuemax="100" aria-valuenow={Math.round(progY * 100)} tabindex="-1"
		     style="top: {progY * (1 - thumbFracY) * 100}%; height: {thumbFracY * 100}%;"
		     on:pointerdown={(e) => dragThumb(false, trackYEl, e)}></div>
	</div>
	{/if}
</div>

<style>
	.outer {
		overflow: hidden;
		position: relative;
	}

	.inner {
		position: absolute;

		top:  0;
		left: 0;

		transform:  translate(calc(var(--scroll-x) * -1px), calc(var(--scroll-y) * -1px));
		transition: transform 0.1s ease-out;
	}

	/* Overlay layer pinned to the viewport — sits above the panned content but
	   below the scrollbars, and is transparent to the wheel/drag (pointer-events:
	   none) so scrolling still works through it. */
	.foreground {
		position: absolute;
		inset: 0;
		overflow: hidden;
		pointer-events: none;
		z-index: 1;
	}

	.scrollbar {
		position: absolute;
		background: rgba(0, 0, 0, 0.12);
		border-radius: 999px;
		z-index: 2;
	}
	.sb-x { left: 6px; right: 6px; bottom: 6px; height: 8px; }
	.sb-y { top: 6px; bottom: 6px; right: 6px; width: 8px; }
	/* When both bars show, keep the cross axis clear of the other bar + corner. */
	.sb-x.inset { right: 18px; }
	.sb-y.inset { bottom: 18px; }

	.thumb {
		position: absolute;
		background: rgba(0, 0, 0, 0.4);
		border-radius: 999px;
		cursor: grab;
		touch-action: none;
		transition: background 0.15s ease;
	}
	.sb-x .thumb { top: 0; height: 100%; min-width: 16px; }
	.sb-y .thumb { left: 0; width: 100%; min-height: 16px; }
	.thumb:hover  { background: rgba(0, 0, 0, 0.6); }
	.thumb:active { background: rgba(0, 0, 0, 0.75); cursor: grabbing; }
</style>
