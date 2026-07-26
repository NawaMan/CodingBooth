<!--
  Highlight — draw attention to a component two ways.

  WRAP mode (declarative, in your face). Put the target inside; the glow uses
  `drop-shadow`, so it follows the content's real alpha shape (a transparent PNG
  or a bare text span glows around its pixels, not a bounding rectangle):

      <Highlight from="bottom-left">
          <img src={diagram} alt="…" />
      </Highlight>

  REMOTE mode (retrospective). Don't restructure existing markup — give the thing
  an id and point at it from anywhere. Pass `target` (a CSS selector or an element)
  and self-close; the glow is applied to the real element and the arrow floats over
  it, re-measured on resize/scroll/zoom:

      <span id="hero">…</span>
      <Highlight target="#hero" from="left" />

  `from` is the side the arrow COMES FROM and points inward — the four sides plus
  the four diagonals. A gentle pulse (glow breathes, arrow bobs toward the target)
  is on by default and honours prefers-reduced-motion; `pulse={false}` for a static
  cue. `show={false}` removes the cue but keeps the content — for reveal-on-cue.
-->
<script context="module" lang="ts">
	export type HighlightFrom =
		| 'top' | 'bottom' | 'left' | 'right'
		| 'top-left' | 'top-right' | 'bottom-left' | 'bottom-right';

	// Per-direction placement of the arrow box. The arrow's TIP sits at the box
	// CENTRE (see the SVG path), so rotation never shifts the tip — we just park
	// the box centre on the target's edge/corner and nudge it `gap` outward.
	//   anchor: which edge/corner of the frame the box pins to
	//   tx/ty : translate to centre the box on that point, then push it out by gap
	//   rot   : rotate the right-pointing arrow so its tip aims at the target
	const GEOM: Record<HighlightFrom, { anchor: string; tx: string; ty: string; rot: number }> = {
		'top':          { anchor: 'left:50%;top:0;',    tx: '-50%',                          ty: 'calc(-50% - var(--hl-gap))',     rot: 90 },
		'bottom':       { anchor: 'left:50%;bottom:0;', tx: '-50%',                          ty: 'calc(50% + var(--hl-gap))',      rot: -90 },
		'left':         { anchor: 'left:0;top:50%;',    tx: 'calc(-50% - var(--hl-gap))',    ty: '-50%',                           rot: 0 },
		'right':        { anchor: 'right:0;top:50%;',   tx: 'calc(50% + var(--hl-gap))',     ty: '-50%',                           rot: 180 },
		'top-left':     { anchor: 'left:0;top:0;',      tx: 'calc(-50% - var(--hl-gap))',    ty: 'calc(-50% - var(--hl-gap))',     rot: 45 },
		'top-right':    { anchor: 'right:0;top:0;',     tx: 'calc(50% + var(--hl-gap))',     ty: 'calc(-50% - var(--hl-gap))',     rot: 135 },
		'bottom-left':  { anchor: 'left:0;bottom:0;',   tx: 'calc(-50% - var(--hl-gap))',    ty: 'calc(50% + var(--hl-gap))',      rot: -45 },
		'bottom-right': { anchor: 'right:0;bottom:0;',  tx: 'calc(50% + var(--hl-gap))',     ty: 'calc(50% + var(--hl-gap))',      rot: -135 },
	};
</script>

<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { browser } from '$app/environment';

	/** Side the arrow comes from and points inward. */
	export let from: HighlightFrom = 'bottom';
	/** Glow + arrow colour. Any CSS colour. */
	export let color = 'red';
	/** Glow blur radius, in canvas px. */
	export let glow = 30;
	/** Glow alpha (0–1). The cue is meant to be semi-transparent. */
	export let opacity = 0.6;
	/** Distance from the arrow tip to the target, in canvas px. */
	export let gap = 16;
	/** Arrow box size, in canvas px (the visible arrow is ~40% of this). */
	export let arrowSize = 150;
	/** Show the arrow. Glow can stand alone if you turn this off. */
	export let arrow = true;
	/** Gentle attention animation; honours prefers-reduced-motion. */
	export let pulse = true;
	/** One pulse cycle, in seconds. */
	export let duration = 1.8;
	/** Master toggle — off keeps the content but drops the cue (reveal on cue). */
	export let show = true;
	/** REMOTE mode: a CSS selector or an element to highlight in place. When set,
	    the slot is ignored — the glow lands on the real element and the arrow
	    floats over it. Leave null to use WRAP mode (slot). */
	export let target: string | Element | null = null;
	/** Click handler for the ARROW. Setting it makes only the arrow glyph a hit
	    target (cursor + keyboard-activatable); leave null for a passive cue. */
	export let onClick: ((event: MouseEvent | KeyboardEvent) => void) | null = null;
	/** Accessible label announced for the arrow when it is clickable. */
	export let label = 'Highlight';

	/** Inline style for the root element, applied last so it wins. */
	export let style: string = '';
	/** DOM id for the root element. */
	export let id: string = '';
	/** Extra class(es) for the root element. NOTE: a slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS (global.css / roles.css / a
	    :global(...) block) or a utility class. See AGENTS.md. */
	let klass: string = '';
	export { klass as class };

	// Imperative show/hide for a parent holding `bind:this`. `show` is also a
	// bindable prop, so `bind:show` works too — these just save a round-trip.
	/** Flip the cue on/off. */
	export function toggle() { show = !show; }
	/** Force the cue on. */
	export function reveal() { show = true; }
	/** Force the cue off. */
	export function hide() { show = false; }

	function fireClick(event: MouseEvent | KeyboardEvent) {
		if (!onClick) return;
		if (event instanceof KeyboardEvent) {
			if (event.key !== 'Enter' && event.key !== ' ') return;
			event.preventDefault(); // stop Space from scrolling
		}
		onClick(event);
	}

	const REMEASURE_EVENTS = ['resize', 'scroll', 'wheel', 'keydown'] as const;

	$: geom = GEOM[from] ?? GEOM.bottom;
	$: remote = target != null;
	$: glowColorCss = `color-mix(in srgb, ${color} ${opacity * 100}%, transparent)`;

	// ── Remote mode plumbing ───────────────────────────────────────────────
	let rootEl: HTMLElement;                 // 0×0 anchor; frame is positioned in its space
	let measured: { left: number; top: number; width: number; height: number } | null = null;
	let glowedEl: HTMLElement | null = null; // the element we styled, so we can restore it
	let observedEl: Element | null = null;
	let mounted = false;
	let raf = 0;
	let ro: ResizeObserver | null = null;

	function resolveTarget(): HTMLElement | null {
		if (!browser || target == null) return null;
		if (typeof target === 'string') return document.querySelector<HTMLElement>(target);
		return target as HTMLElement;
	}

	function applyGlow(el: HTMLElement) {
		if (glowedEl && glowedEl !== el) clearGlow();
		glowedEl = el;
		el.style.setProperty('--hl-glow', `${glow}px`);
		el.style.setProperty('--hl-glow-color', glowColorCss);
		el.style.setProperty('--hl-dur', `${duration}s`);
		el.classList.add('gp-hl-glow');
		el.classList.toggle('gp-hl-pulse', pulse);
	}

	function clearGlow() {
		if (!glowedEl) return;
		glowedEl.classList.remove('gp-hl-glow', 'gp-hl-pulse');
		glowedEl.style.removeProperty('--hl-glow');
		glowedEl.style.removeProperty('--hl-glow-color');
		glowedEl.style.removeProperty('--hl-dur');
		glowedEl = null;
	}

	function measure() {
		raf = 0;
		const el = resolveTarget();
		if (!el || !rootEl) { measured = null; return; }
		const tr = el.getBoundingClientRect();
		// Convert screen px → canvas px. The whole canvas is CSS-scaled, so one
		// canvas unit renders as `scale` screen px; offsetWidth is already in
		// canvas units, so rect.width / offsetWidth recovers that scale.
		const scale = el.offsetWidth ? tr.width / el.offsetWidth : 1;
		const rr = rootEl.getBoundingClientRect();
		measured = {
			left: (tr.left - rr.left) / scale,
			top: (tr.top - rr.top) / scale,
			width: el.offsetWidth,
			height: el.offsetHeight,
		};
	}

	function scheduleMeasure() {
		if (!browser || raf) return;
		raf = requestAnimationFrame(measure);
	}

	let retries = 0;
	function sync() {
		if (!remote) { clearGlow(); measured = null; return; }
		const el = resolveTarget();
		// A sibling target may not be in the DOM on the first tick; retry a few frames.
		if (!el) {
			if (retries++ < 5) requestAnimationFrame(sync);
			return;
		}
		retries = 0;
		if (ro && el !== observedEl) {
			if (observedEl) ro.unobserve(observedEl);
			ro.observe(el);
			observedEl = el;
		}
		if (show) applyGlow(el); else clearGlow();
		scheduleMeasure();
	}

	// Re-sync whenever any input that affects the remote cue changes.
	$: if (mounted) {
		void [target, show, color, glow, opacity, gap, arrowSize, from, arrow, pulse, duration];
		sync();
	}

	onMount(() => {
		mounted = true;
		if (!browser) return;
		ro = new ResizeObserver(scheduleMeasure);
		// resize/scroll cover window + pan; wheel/keydown catch zoom and display-mode
		// changes that scale the canvas via transform (which a ResizeObserver misses).
		for (const ev of REMEASURE_EVENTS) window.addEventListener(ev, scheduleMeasure, true);
		sync();
	});

	onDestroy(() => {
		if (!browser) return;
		if (raf) cancelAnimationFrame(raf);
		for (const ev of REMEASURE_EVENTS) window.removeEventListener(ev, scheduleMeasure, true);
		ro?.disconnect();
		clearGlow();
	});
</script>

{#if remote}
	<!-- REMOTE: glow is on the real element; this 0×0 anchor only hosts the arrow,
	     positioned over the measured target rect (in canvas px). -->
	<span
		class="hl hl-remote {klass}"
		id={id || undefined}
		bind:this={rootEl}
		style="--hl-color:{color}; --hl-gap:{gap}px; --hl-arrow:{arrowSize}px; --hl-dur:{duration}s; {style}"
	>
		{#if show && arrow && measured}
			<span
				class="frame"
				style="left:{measured.left}px; top:{measured.top}px; width:{measured.width}px; height:{measured.height}px;"
			>
				<span class="arrow" style="{geom.anchor} transform: translate({geom.tx}, {geom.ty});">
					<span class="arrow-rot" style="transform: rotate({geom.rot}deg);">
						<!-- svelte-ignore a11y-no-static-element-interactions a11y-click-events-have-key-events a11y-no-noninteractive-tabindex -->
						<svg
							class="arrow-svg"
							class:pulse
							class:clickable={onClick}
							viewBox="0 0 120 120"
							role={onClick ? 'button' : undefined}
							tabindex={onClick ? 0 : undefined}
							aria-label={onClick ? label : undefined}
							aria-hidden={onClick ? undefined : true}
							on:click={fireClick}
							on:keydown={fireClick}
						>
							<path d="M10 52 H44 V42 L60 60 L44 78 V68 H10 Z" fill="var(--hl-color)" />
						</svg>
					</span>
				</span>
			</span>
		{/if}
	</span>
{:else}
	<!-- WRAP: glow hugs the slotted content's real shape via drop-shadow. -->
	<span
		class="hl {klass}"
		id={id || undefined}
		style="--hl-color:{color}; --hl-opacity:{opacity}; --hl-glow:{glow}px; --hl-gap:{gap}px; --hl-arrow:{arrowSize}px; --hl-dur:{duration}s; {style}"
	>
		<span class="target" class:gp-hl-glow={show} class:gp-hl-pulse={show && pulse}>
			<slot />
		</span>

		{#if show && arrow}
			<span class="arrow" style="{geom.anchor} transform: translate({geom.tx}, {geom.ty});">
				<span class="arrow-rot" style="transform: rotate({geom.rot}deg);">
					<!-- svelte-ignore a11y-no-static-element-interactions a11y-click-events-have-key-events a11y-no-noninteractive-tabindex -->
					<svg
						class="arrow-svg"
						class:pulse
						class:clickable={onClick}
						viewBox="0 0 120 120"
						role={onClick ? 'button' : undefined}
						tabindex={onClick ? 0 : undefined}
						aria-label={onClick ? label : undefined}
						aria-hidden={onClick ? undefined : true}
						on:click={fireClick}
						on:keydown={fireClick}
					>
						<path d="M10 52 H44 V42 L60 60 L44 78 V68 H10 Z" fill="var(--hl-color)" />
					</svg>
				</span>
			</span>
		{/if}
	</span>
{/if}

<style>
	.hl {
		position: relative;
		display: inline-block;
	}
	/* The remote anchor takes no space and is the containing block for the frame. */
	.hl-remote {
		position: absolute;
		top: 0;
		left: 0;
		width: 0;
		height: 0;
	}
	.frame {
		position: absolute;
	}

	.target {
		display: inline-block;
	}

	/* Glow rules are GLOBAL so they also apply to a remote target element (which
	   lives outside this component). The element supplies --hl-glow / --hl-glow-color
	   via inline style (set in JS, WRAP mode sets them on .hl below). */
	:global(.gp-hl-glow) {
		filter: drop-shadow(0 0 var(--hl-glow, 30px) var(--hl-glow-color, rgba(255, 0, 0, 0.6)));
	}
	/* WRAP mode: derive --hl-glow-color from the colour + alpha props. */
	.hl {
		--hl-glow-color: color-mix(in srgb, var(--hl-color) calc(var(--hl-opacity) * 100%), transparent);
	}

	.arrow {
		position: absolute;
		width: var(--hl-arrow);
		height: var(--hl-arrow);
		pointer-events: none;
		/* transform (the translate that parks the box) is set inline per-direction */
	}
	.arrow-rot {
		/* block (not the span default of inline) — CSS transforms are IGNORED on
		   inline elements, so without this the per-direction rotate() is dropped
		   and every arrow points the SVG's default way (right). */
		display: block;
		width: 100%;
		height: 100%;
		/* rotate is set inline per-direction; tip is box-centred so origin = centre */
	}
	.arrow-svg {
		display: block;
		width: 100%;
		height: 100%;
		overflow: visible;
		/* a hair of shadow so the arrow reads over busy backgrounds */
		filter: drop-shadow(0 1px 1.5px rgba(0, 0, 0, 0.4));
	}
	/* When clickable, re-enable hit-testing on the painted glyph ONLY (pointer-events
	   is inherited, so .arrow's `none` reaches here; the path opts back in, and SVG
	   visiblePainted means the transparent half of the box stays click-through).
	   The click lands on the path and bubbles to the svg's on:click. */
	.arrow-svg.clickable path {
		pointer-events: auto;
		cursor: pointer;
	}
	.arrow-svg.clickable:focus-visible {
		outline: 2.5px solid var(--hl-color);
		outline-offset: 3px;
	}

	/* Keyframes are -global- so the global .gp-hl-glow rule can reference them too
	   (Svelte would otherwise scope/rename them and the global selector wouldn't match). */
	@media (prefers-reduced-motion: no-preference) {
		:global(.gp-hl-glow.gp-hl-pulse) {
			animation: gp-hl-glow-pulse var(--hl-dur, 1.8s) ease-in-out infinite;
		}
		.arrow-svg.pulse {
			animation: gp-hl-arrow-bob var(--hl-dur) ease-in-out infinite;
		}
	}

	@keyframes -global-gp-hl-glow-pulse {
		0%, 100% { filter: drop-shadow(0 0 calc(var(--hl-glow) * 0.5) var(--hl-glow-color)); }
		50%      { filter: drop-shadow(0 0 calc(var(--hl-glow) * 1.3) var(--hl-glow-color)); }
	}
	/* +x is toward the tip (the rotation aligns local +x with the target), so a
	   positive translateX bobs the arrow toward what it points at. */
	@keyframes -global-gp-hl-arrow-bob {
		0%, 100% { transform: translateX(0); }
		50%      { transform: translateX(calc(var(--hl-gap) * 0.6)); }
	}
</style>
