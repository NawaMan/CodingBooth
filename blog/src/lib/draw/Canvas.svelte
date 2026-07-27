<!--
  Canvas — an imperative JS/TS drawing surface on the shared keyframe playhead.

  Where Line/Curve/Arc/Sprite emit CSS @keyframes, a canvas is raw pixels: you
  get a 2D context and a draw(ctx, frame) callback. The trick that keeps it on
  the SAME timeline as everything else is that Canvas owns ONE hidden CSS
  @keyframes "clock" — a real, finite animation. So an enclosing <AnimationBar>
  or <AnimationScene> discovers it via getAnimations() with no special-casing,
  includes it in the envelope, and scrubs it by writing its currentTime. Canvas
  runs its own requestAnimationFrame loop that reads that clock every frame and
  calls your draw() with the current time/progress — so pause, scrub, restart,
  and scroll-driven playback all "just work", in lockstep with sibling shapes.

  Pick only what you need:
    • duration           → finite, SCRUBBABLE clock; joins the AnimationBar.
    • keyframes + duration→ also hands draw() interpolated value tracks (0–100
                            pct + ease, like LineStop) so you think in stops.
    • loop               → ambient free-run (passes dt); the bar ignores it
                            (infinite animations aren't seekable) — for idle
                            backgrounds, not timeline beats.
    • neither            → static: draw once (progress 0).

  Placement: wrap in <Block x y width height> for canvas-px position/size, or
  give Canvas its own width/height; with neither it fills its parent box.

      <Block x={200} y={300} width={800} height={480}>
        <Canvas duration={4} draw={(ctx, { progress, width, height }) => {
          ctx.clearRect(0, 0, width, height);
          ctx.fillRect(progress * width, height / 2, 40, 40);
        }} />
      </Block>

  Scrub-safety: draw as a PURE function of `frame` (progress/t/values), NOT of
  accumulated `dt` — then a backward scrub reproduces earlier frames exactly,
  the same discipline that makes the CSS shapes scrubbable. `dt` is there for
  loop-mode physics where determinism doesn't matter.

  SSR: the canvas pixels are inherently client-only (guarded by `browser`), but
  the hidden clock is declarative CSS, so it PRERENDERS — the AnimationBar finds
  the timeline the instant JS boots, without waiting for an onMount injection.
-->
<script module lang="ts">
	// Per-instance clock id, so several canvases on one page get distinct
	// @keyframes names. Module-scoped counter — matches server/client order.
	let COUNTER = 0;
</script>

<script lang="ts">
	import { onDestroy } from 'svelte';
	import { browser } from '$app/environment';
	import {
		clamp,
		interpAt,
		type CanvasFrame,
		type CanvasPointerEvent,
		type CanvasStop
	} from './canvasCore';

	interface Props {
		/** The drawing callback, run each frame with a pre-scaled 2D context and a
		 *  {@link CanvasFrame} snapshot of the playhead. Draw in canvas px. */
		draw: (ctx: CanvasRenderingContext2D, frame: CanvasFrame) => void;
		/** Seconds for one pass of the clock. Set → finite, scrubbable, joins the
		 *  AnimationBar envelope. Unset (and no `loop`) → static, drawn once. */
		duration?: number;
		/** Ambient free-run instead of a finite clock: `true` loops forever (period
		 *  = `duration` or 1s), or a number sets the loop period in seconds. Not
		 *  seekable — the AnimationBar ignores infinite animations by design. */
		loop?: boolean | number;
		/** Optional value tracks: `[{ pct, ease?, ...numbers }]` (pct 0–100). When
		 *  set, `frame.values` carries every track interpolated at the playhead —
		 *  same stop vocabulary as the path shapes, tweened in JS. Needs a clock
		 *  (`duration` or `loop`) to have a moving pct. */
		keyframes?: CanvasStop[];
		/** Logical drawing size in canvas px. Omit either to measure the parent box
		 *  (e.g. the wrapping Block) with a ResizeObserver. */
		width?: number;
		height?: number;
		/** Clear the whole surface before each draw (default true). Turn off to
		 *  accumulate trails yourself. */
		autoClear?: boolean;
		/** Fill color painted before each draw (after clear). Omit for transparent. */
		background?: string;
		/** Backing-store scale; defaults to devicePixelRatio for crisp output. */
		pixelRatio?: number;
		/** Extra classes / inline style for the wrapper. NOTE: a slide's own scoped
		 *  styles will NOT match a class named here — use global CSS (global.css /
		 *  roles.css / a :global(...) block) or a utility class. See AGENTS.md. */
		class?: string;
		style?: string;
		/** DOM id for the root element. */
		id?: string;

		// --- Interaction. Any handler here makes the surface pointer-interactive
		// (otherwise the canvas is pointer-events:none, so it never blocks clicks
		// meant for content behind it). Each callback gets a CanvasPointerEvent with
		// the pointer in canvas px and a redraw() to repaint after state changes. */
		/** Pointer pressed on the surface. */
		onpointerdown?: (e: CanvasPointerEvent) => void;
		/** Pointer moved over the surface (for hover hit-testing). */
		onpointermove?: (e: CanvasPointerEvent) => void;
		/** Pointer released on the surface. */
		onpointerup?: (e: CanvasPointerEvent) => void;
		/** A click (down+up on the surface). */
		onclick?: (e: CanvasPointerEvent) => void;
		/** A double-click. */
		ondblclick?: (e: CanvasPointerEvent) => void;
		/** Cursor shown while over the surface when interactive (default 'default';
		 *  set 'pointer' for clickable canvases). */
		cursor?: string;
	}

	let {
		draw,
		duration,
		loop,
		keyframes,
		width,
		height,
		autoClear = true,
		background,
		pixelRatio,
		class: klass = '',
		style = '',
		id = '',
		onpointerdown,
		onpointermove,
		onpointerup,
		onclick,
		ondblclick,
		cursor = 'default'
	}: Props = $props();

	// The surface eats pointer input only when the author wired a handler, so a
	// decorative canvas never blocks clicks to whatever sits behind it.
	const interactive = $derived(
		!!(onpointerdown || onpointermove || onpointerup || onclick || ondblclick)
	);

	const clockId = `gp-canvas-clock-${++COUNTER}`;

	// Finite (scrubbable) clock only when a duration is set and we're NOT looping.
	const finiteSecs = $derived(loop || !duration || duration <= 0 ? 0 : duration);
	const loopSecs = $derived(loop ? (typeof loop === 'number' && loop > 0 ? loop : duration && duration > 0 ? duration : 1) : 0);

	let wrapper = $state<HTMLDivElement>();
	let canvasEl = $state<HTMLCanvasElement>();
	let clockEl = $state<HTMLSpanElement>();

	let raf = 0;
	let startMs = 0; // wall-clock origin for loop mode
	let lastT = 0; // previous frame time (s) — for dt
	let lastDrawnT = Number.NaN; // last time we actually painted (dirty check)
	let frameNo = 0;
	let dpr = 1;
	let logicalW = 0;
	let logicalH = 0;
	let sizeDirty = true;
	let warned = false;
	let lastFrame: CanvasFrame | null = null; // most recent painted snapshot, for hit-testing

	// Recompute the backing store when the box or dpr changes. Keeps the CSS box
	// at logical px (SlideDeck's transform scales it) and the backing store at
	// px*dpr for crisp output; ctx is scaled so the callback draws in logical px.
	function measure() {
		if (!browser || !canvasEl || !wrapper) return;
		dpr = pixelRatio && pixelRatio > 0 ? pixelRatio : (window.devicePixelRatio || 1);
		const w = width && width > 0 ? width : Math.round(wrapper.clientWidth) || 1;
		const h = height && height > 0 ? height : Math.round(wrapper.clientHeight) || 1;
		if (w !== logicalW || h !== logicalH || canvasEl.width !== Math.round(w * dpr)) {
			logicalW = w;
			logicalH = h;
			canvasEl.style.width = `${w}px`;
			canvasEl.style.height = `${h}px`;
			canvasEl.width = Math.round(w * dpr);
			canvasEl.height = Math.round(h * dpr);
			sizeDirty = true;
		}
	}

	// Read the playhead. Finite: the clock animation's currentTime (what the bar
	// scrubs). Loop: wall-clock since start, wrapped by period. Static: frozen 0.
	function readTime(nowMs: number): { t: number; progress: number } {
		if (finiteSecs > 0) {
			const anim = clockEl?.getAnimations?.()[0];
			const ct = anim && typeof anim.currentTime === 'number' ? anim.currentTime : 0;
			const t = clamp(ct / 1000, 0, finiteSecs);
			return { t, progress: finiteSecs > 0 ? t / finiteSecs : 0 };
		}
		if (loopSecs > 0) {
			if (!startMs) startMs = nowMs;
			const t = (nowMs - startMs) / 1000;
			return { t, progress: (t / loopSecs) % 1 };
		}
		return { t: 0, progress: 0 };
	}

	function paint(t: number, progress: number, dt: number) {
		const ctx = canvasEl?.getContext('2d');
		if (!ctx) return;
		ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
		if (autoClear) ctx.clearRect(0, 0, logicalW, logicalH);
		if (background) {
			ctx.fillStyle = background;
			ctx.fillRect(0, 0, logicalW, logicalH);
		}
		const frame: CanvasFrame = {
			width: logicalW,
			height: logicalH,
			t,
			progress,
			pct: progress * 100,
			dt,
			values: keyframes && keyframes.length ? interpAt(keyframes, progress * 100) : {},
			frame: frameNo++
		};
		lastFrame = frame;
		try {
			draw(ctx, frame);
		} catch (err) {
			if (!warned) {
				warned = true;
				console.error('[Canvas] draw() threw — stopping redraws for this frame:', err);
			}
		}
	}

	function tick(nowMs: number) {
		raf = 0;
		if (!browser || !canvasEl) return;
		if (sizeDirty) measure();
		const { t, progress } = readTime(nowMs);
		const dt = t - lastT;
		lastT = t;
		// Redraw when looping (always advancing), when the finite/static playhead
		// moved (autoplay OR a scrub sets a new currentTime), or when the box just
		// resized. Otherwise idle — cheap poll, like AnimationBar's own loop.
		if (loopSecs > 0 || sizeDirty || t !== lastDrawnT || Number.isNaN(lastDrawnT)) {
			paint(t, progress, dt);
			lastDrawnT = t;
			sizeDirty = false;
		}
		schedule();
	}

	function schedule() {
		if (!raf && browser) raf = requestAnimationFrame(tick);
	}

	// Force a repaint of the current playhead (draw() is otherwise idle when the
	// clock isn't moving) — the hook an interaction hands back as `redraw()`.
	function forceRedraw() {
		lastDrawnT = Number.NaN;
		schedule();
	}

	// The frame handed to interaction callbacks: the last painted snapshot, or a
	// fresh frame-0 snapshot if the pointer arrives before the first paint.
	function currentFrame(): CanvasFrame {
		if (lastFrame) return lastFrame;
		return {
			width: logicalW,
			height: logicalH,
			t: 0,
			progress: 0,
			pct: 0,
			dt: 0,
			values: keyframes && keyframes.length ? interpAt(keyframes, 0) : {},
			frame: frameNo
		};
	}

	// Map a DOM pointer to canvas px. Dividing by the canvas's LIVE on-screen size
	// (getBoundingClientRect) makes the mapping correct through SlideDeck's scaling
	// transform in every display mode — the same trick Block's drag math uses.
	function toCanvasEvent(ev: MouseEvent): CanvasPointerEvent {
		const rect = canvasEl!.getBoundingClientRect();
		const x = rect.width ? ((ev.clientX - rect.left) / rect.width) * logicalW : 0;
		const y = rect.height ? ((ev.clientY - rect.top) / rect.height) * logicalH : 0;
		return { x, y, frame: currentFrame(), originalEvent: ev, redraw: forceRedraw };
	}

	// One dispatcher per event: guard on the handler existing so a canvas that
	// only wants clicks doesn't repaint on every pointermove.
	const onDown = (e: PointerEvent) => onpointerdown && (onpointerdown(toCanvasEvent(e)), forceRedraw());
	const onMove = (e: PointerEvent) => onpointermove && (onpointermove(toCanvasEvent(e)), forceRedraw());
	const onUp = (e: PointerEvent) => onpointerup && (onpointerup(toCanvasEvent(e)), forceRedraw());
	const onClick = (e: MouseEvent) => onclick && (onclick(toCanvasEvent(e)), forceRedraw());
	const onDblClick = (e: MouseEvent) => ondblclick && (ondblclick(toCanvasEvent(e)), forceRedraw());

	// Boot once the canvas is in the DOM; re-measure on box changes.
	$effect(() => {
		if (!browser || !canvasEl || !wrapper) return;
		measure();
		const ro = new ResizeObserver(() => {
			sizeDirty = true;
			schedule();
		});
		ro.observe(wrapper);
		// A finite clock's Animation object can appear a frame after paint (same
		// caveat AnimationBar handles) — the poll loop tolerates a null clock.
		startMs = 0;
		lastDrawnT = Number.NaN;
		schedule();
		return () => ro.disconnect();
	});

	// Redraw immediately when inputs that don't change the playhead change
	// (new draw fn, keyframes, colors) so edits show without waiting for motion.
	$effect(() => {
		void draw;
		void keyframes;
		void background;
		void autoClear;
		lastDrawnT = Number.NaN;
		schedule();
	});

	onDestroy(() => {
		if (raf) cancelAnimationFrame(raf);
		raf = 0;
	});
</script>

<div id={id || undefined} class="gp-canvas {klass}" bind:this={wrapper} {style}>
	<canvas
		bind:this={canvasEl}
		class="gp-canvas-surface"
		style="pointer-events:{interactive ? 'auto' : 'none'};{interactive ? `cursor:${cursor};` : ''}"
		onpointerdown={onDown}
		onpointermove={onMove}
		onpointerup={onUp}
		onclick={onClick}
		ondblclick={onDblClick}
	></canvas>

	{#if finiteSecs > 0}
		<!-- The hidden keyframe CLOCK. A real, finite CSS animation (linear, fill
		     both) so AnimationBar/AnimationScene auto-discover and scrub it. It's
		     declarative, so it prerenders — the bar sees the timeline at once. The
		     span is 0×0 and transparent; only its TIMING matters, never its paint. -->
		{@html `<style>@keyframes ${clockId}{from{opacity:0}to{opacity:1}}</style>`}
		<span
			class="gp-canvas-clock"
			bind:this={clockEl}
			aria-hidden="true"
			style="animation:{clockId} {finiteSecs}s linear both"
		></span>
	{/if}
</div>

<style>
	.gp-canvas {
		position: relative;
		width: 100%;
		height: 100%;
	}
	.gp-canvas-surface {
		display: block;
	}
	/* Zero-footprint, invisible clock: present and animating (so getAnimations
	   reports it), but paints nothing and never intercepts pointer input. */
	.gp-canvas-clock {
		position: absolute;
		left: 0;
		top: 0;
		width: 0;
		height: 0;
		overflow: hidden;
		opacity: 0;
		pointer-events: none;
	}
</style>
