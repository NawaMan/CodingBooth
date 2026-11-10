<!--
  LivePointer — a mouse pointer the PAGE draws, for screen recorders that leave the real
  one out (GNOME's built-in screencast; a tab captured through getDisplayMedia, which is
  what the deck's own ● REC does). Whatever records the screen records this.

  A canvas-level singleton like Spotlight and Annotate: SlideDeck mounts it, no slide
  places it. It shows while `livePointer` is on (stores/livePointer: the sticky
  `?pointer` / ?pointer=off, ☰ → POINTER, Alt+. → I, or the deck's `pointer` prop), and
  while it does, the real cursor is hidden page-wide so only one pointer is seen.

  Not draw/Cursor: that is SCRIPTED and rides the animation timeline. This follows the
  real mouse and has no script. It borrows Cursor's glyphs, but has its own brighter
  `--live-pointer-*` role tokens: a video is often watched small and compressed, where
  Cursor's warm orange reads as dull.

  WINDOW-fixed, not in the canvas: it sits where the mouse is in the window, at a size in
  screen px that does not change with the slide's zoom. A press flashes a ripple, so a
  viewer of the video can see the click too.

  `.no-print`, so CAPTURE and PRINT leave it out — a PNG of a slide has no cursor — while a
  screen recorder, which reads pixels and not classes, still sees it.

  Limit: over an <iframe> (YouTube, WebSite) the page receives no mouse events, so the
  glyph stops at the iframe's edge until the mouse comes back.
-->
<script lang="ts">
	import { onDestroy } from 'svelte';
	import { browser } from '$app/environment';
	import { livePointer } from '$lib/stores/livePointer';
	import {
		DEFAULT_POINTER_SIZE,
		normalizeShape,
		normalizeSize,
		pointerOffset,
		type PointerShape
	} from '$lib/pointer/livePointerCore';

	interface Props {
		/** Glyph preset — `arrow` (default) / `dot` / `ring`, as `Cursor`'s. */
		shape?: PointerShape;
		/** Glyph size in screen px. */
		size?: number;
		/** Inline style for the root element, applied last so it wins. */
		style?: string;
		/** DOM id for the root element. */
		id?: string;
		/** Extra class(es) for the root element. */
		class?: string;
	}

	let { shape = 'arrow', size = DEFAULT_POINTER_SIZE, style = '', id = '', class: klass = '' }: Props = $props();

	const glyph = $derived(normalizeShape(shape));
	const px = $derived(normalizeSize(size));
	const offset = $derived(pointerOffset(glyph, px));

	let x = $state(0);
	let y = $state(0);
	/** False until the mouse has moved here, and again once it leaves the window. */
	let seen = $state(false);
	let ripples: { id: number; x: number; y: number }[] = $state([]);
	let nextRipple = 0;

	function onMove(e: PointerEvent) {
		x = e.clientX;
		y = e.clientY;
		seen = true;
	}

	function onDown(e: PointerEvent) {
		onMove(e);
		const r = { id: nextRipple++, x: e.clientX, y: e.clientY };
		ripples = [...ripples, r];
		// A timer, not `animationend`: under prefers-reduced-motion there is no animation.
		setTimeout(() => {
			ripples = ripples.filter((q) => q.id !== r.id);
		}, 700);
	}

	function onLeave() {
		seen = false;
	}

	let listening = false;

	function listen(on: boolean) {
		if (!browser || on === listening) return;
		listening = on;
		const root = document.documentElement;
		const opts = { capture: true, passive: true } as const;
		if (on) {
			root.classList.add('gp-live-pointer');
			window.addEventListener('pointermove', onMove, opts);
			window.addEventListener('pointerdown', onDown, opts);
			root.addEventListener('mouseleave', onLeave);
		} else {
			root.classList.remove('gp-live-pointer');
			window.removeEventListener('pointermove', onMove, opts);
			window.removeEventListener('pointerdown', onDown, opts);
			root.removeEventListener('mouseleave', onLeave);
			seen = false;
			ripples = [];
		}
	}

	$effect(() => {
		listen($livePointer);
	});

	onDestroy(() => listen(false));
</script>

{#if $livePointer}
	<div
		class="live-pointer no-print {klass}"
		id={id || undefined}
		aria-hidden="true"
		style={style || undefined}
	>
		{#each ripples as r (r.id)}
			<span class="live-ripple" style="left:{r.x}px; top:{r.y}px; --live-ripple-size:{px}px;"
			></span>
		{/each}
		{#if seen}
			<span
				class="live-glyph"
				style="width:{px}px; height:{px}px; transform: translate3d({x + offset[0]}px, {y +
					offset[1]}px, 0);"
			>
				{#if glyph === 'dot'}
					<svg viewBox="0 0 24 24" width="100%" height="100%">
						<circle
							cx="12"
							cy="12"
							r="8"
							fill="var(--live-pointer-fill, #ffd23f)"
							stroke="var(--live-pointer-outline, rgba(0, 0, 0, 0.8))"
							stroke-width="1.4"
						/>
					</svg>
				{:else if glyph === 'ring'}
					<svg viewBox="0 0 24 24" width="100%" height="100%">
						<circle
							cx="12"
							cy="12"
							r="8"
							fill="none"
							stroke="var(--live-pointer-fill, #ffd23f)"
							stroke-width="2.5"
						/>
					</svg>
				{:else}
					<svg viewBox="0 0 24 24" width="100%" height="100%">
						<path
							d="M3 3 L10.07 19.97 L12.58 12.58 L19.97 10.07 Z"
							fill="var(--live-pointer-fill, #ffd23f)"
							stroke="var(--live-pointer-outline, rgba(0, 0, 0, 0.8))"
							stroke-width="1.4"
							stroke-linejoin="round"
						/>
					</svg>
				{/if}
			</span>
		{/if}
	</div>
{/if}

<style>
	/* One pointer on screen, not two: the real cursor goes while the drawn one is shown.
	   `!important` because every control (a resize grip, a link, the pen's crosshair) sets
	   its own cursor, and each of those would otherwise bring the real one back. */
	:global(html.gp-live-pointer),
	:global(html.gp-live-pointer *) {
		cursor: none !important;
	}

	/* Above everything — the replay shield (2147483647) included, since it comes earlier in
	   the document — and never in the way of a click. */
	.live-pointer {
		position: fixed;
		inset: 0;
		z-index: 2147483647;
		pointer-events: none;
		overflow: hidden;
	}

	.live-glyph {
		position: absolute;
		left: 0;
		top: 0;
		will-change: transform;
		/* A bright halo so it reads over a dark slide, and a dark shadow under it so it
		   still reads over a light one. */
		filter: drop-shadow(0 0 4px var(--live-pointer-glow, rgba(255, 210, 63, 0.75)))
			drop-shadow(0 1px 2px rgba(0, 0, 0, 0.6));
	}

	.live-glyph svg {
		display: block;
	}

	.live-ripple {
		position: absolute;
		width: calc(var(--live-ripple-size, 40px) * 1.4);
		height: calc(var(--live-ripple-size, 40px) * 1.4);
		margin-left: calc(var(--live-ripple-size, 40px) * -0.7);
		margin-top: calc(var(--live-ripple-size, 40px) * -0.7);
		border: 3px solid var(--live-pointer-ripple, #ffd23f);
		border-radius: 50%;
		box-sizing: border-box;
		opacity: 0;
		animation: live-ripple-pulse 0.6s ease-out;
	}

	@keyframes live-ripple-pulse {
		0% {
			opacity: 0.9;
			transform: scale(0.35);
		}
		100% {
			opacity: 0;
			transform: scale(1.6);
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.live-ripple {
			animation: none;
		}
	}
</style>
