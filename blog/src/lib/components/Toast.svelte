<!--
  Toast — a transient on-slide message that can spotlight what it names.

  A short banner the speaker (or a build step) raises over the LIVE slide: it fades
  itself in, holds for `duration` ms, and fades out — and if it carries a `highlight`,
  it dims the slide around a named <Block> at the same moment, so "say it" and "point
  at it" become one call on one timeline.

    <Toast open={deployed} highlight="deploy" text="Deployed!" />

  It reuses what already points at components: `highlight="deploy"` resolves through the
  SAME blockAnchors registry a <Connector>/<Spotlight> reads, and the dim is
  spotlightCore's geometry — so the punch-out follows the box even as it is dragged in
  ADJUST mode, with no coordinate authored. The only new machinery is the message chrome
  and the auto-dismiss (utils/toastCore.ts, pure/total).

  REVEAL-style, SSR-inert. Like <Spotlight>, a Toast is a runtime, per-window cue the
  presenter drives, so it must ship NOTHING at prerender — no banner over the deck, no
  scrim over the slide. It renders nothing until it is both mounted (client-only) and
  `open`, then lights up. The fade in/out is pure CSS (a @keyframes, like the Spotlight
  pulse), not the Web Animations API, so it honours prefers-reduced-motion and never
  depends on a client-only animate() call.

  Props:
    text       — the message. Omit to use the default slot instead (Hint/Callout escape hatch).
    open       — the author's intent to show it now. false → inert. Flip it from a Steps
                 build, a button, or the presenter console.
    highlight  — name of a <Block> to spotlight; the slide dims around it. Omit for a
                 plain banner with no dim.
    duration   — ms to hold before auto-dismissing. 0 or negative → sticky (stays until
                 `open` goes false). Junk falls back to the default dwell.
    placement  — 'top' | 'center' | 'bottom' (default 'bottom'); where the banner sits.
    dim        — how dark the surround goes when highlighting, 0–1 (default 0.4).
    pad/radius — spotlight geometry passthrough (padding + corner radius of the punch-out).
    icon       — optional leading glyph.
    onclose    — called when the toast auto-dismisses itself (reset the build flag here).
-->
<script lang="ts">
	import { blockAnchors } from '$lib/stores/blockAnchors';
	import { spotlightRect } from '$lib/draw/spotlightCore';
	import { autoDismissMs, clampDim, toastPlacement } from '$lib/utils/toastCore';
	import type { Snippet } from 'svelte';

	interface Props {
		/** The message text; omit to use the default slot (children) instead. */
		text?: string;
		/** Show it now. false (the default) → renders nothing. */
		open?: boolean;
		/** Name of a Block to dim the slide around. Omit for a banner with no spotlight. */
		highlight?: string;
		/** ms to hold before dismissing itself; 0/negative → sticky. */
		duration?: number;
		/** Where the banner sits over the canvas. */
		placement?: 'top' | 'center' | 'bottom';
		/** How dark the surround goes when highlighting, 0–1. */
		dim?: number;
		/** Padding in canvas px between the Block and the punch-out. */
		pad?: number;
		/** Punch-out corner radius in canvas px. */
		radius?: number;
		/** Optional leading glyph. */
		icon?: string;
		canvasWidth?: number;
		canvasHeight?: number;
		/** Called when the toast auto-dismisses itself (not when `open` is set false). */
		onclose?: () => void;
		/** DOM id for the root layer. */
		id?: string;
		/** Extra class(es) for the root layer. NOTE: a slide's own <style> is scoped, so a
		    class defined there will NOT match — use global CSS or a :global(...) block. */
		class?: string;
		/** Extra inline CSS appended to the banner. */
		style?: string;
		/** Default slot content, used when `text` is omitted. */
		children?: Snippet;
	}

	let {
		text = '',
		open = false,
		highlight = '',
		duration = 2600,
		placement = 'bottom',
		dim = 0.4,
		pad = 14,
		radius = 16,
		icon = '',
		canvasWidth = 1920,
		canvasHeight = 1080,
		onclose,
		id = '',
		class: klass = '',
		style = '',
		children
	}: Props = $props();

	const EXIT_MS = 200; // matches the CSS exit fade below

	// Client-only mount gate: guarantees SSR-inert regardless of a statically-`open`
	// author, and is the "lights up on the client" half of the reveal convention.
	let mounted = $state(false);
	$effect(() => {
		mounted = true;
	});

	// Auto-dismiss. Re-armed each time `open` turns on; the cleanup clears a pending
	// timer AND resets the flag, so re-opening re-fires. Sticky (ms===0) never arms.
	let dismissed = $state(false);
	$effect(() => {
		if (!open) {
			dismissed = false;
			return;
		}
		dismissed = false;
		const ms = autoDismissMs(duration);
		if (ms <= 0) return; // sticky — stays until `open` goes false
		const t = setTimeout(() => {
			dismissed = true;
			onclose?.();
		}, ms);
		return () => clearTimeout(t);
	});

	// Whether the author wants it up right now.
	const wantUp = $derived(mounted && open && !dismissed);

	// Presence, kept one exit-cycle past `wantUp` so the CSS fade-out can play before
	// the node leaves the DOM (a bare {#if wantUp} would pop it away instantly).
	let shown = $state(false);
	let leaving = $state(false);
	$effect(() => {
		if (wantUp) {
			leaving = false;
			shown = true;
		} else if (shown) {
			leaving = true;
			const t = setTimeout(() => {
				shown = false;
				leaving = false;
			}, EXIT_MS);
			return () => clearTimeout(t);
		}
	});

	const place = $derived(toastPlacement(placement));
	const dimAlpha = $derived(clampDim(dim));

	// The spotlight box: the named anchor, grown by pad — or null (no name / not
	// registered / no highlight), in which case the banner shows with no dim.
	const box = $derived(highlight ? $blockAnchors.get(highlight) : undefined);
	const rect = $derived(box ? spotlightRect(box, pad, radius, canvasWidth, canvasHeight) : null);

	// Name-scoped, stable mask id — two decks on one page must not collide (Text artifacts).
	const maskId = $derived(`gp-toast-hole-${cssIdent(highlight)}`);
	function cssIdent(s: string): string {
		return s.replace(/[^a-zA-Z0-9_-]/g, '-') || 'x';
	}
</script>

{#if shown}
	<div
		class="gp-toast-layer gp-toast-layer--{place} {klass}"
		class:leaving
		id={id || undefined}
		style="width:{canvasWidth}px; height:{canvasHeight}px; pointer-events:none;"
	>
		{#if rect && dimAlpha > 0}
			<svg
				class="gp-toast-dim"
				viewBox="0 0 {canvasWidth} {canvasHeight}"
				style="width:{canvasWidth}px; height:{canvasHeight}px;"
				aria-hidden="true"
			>
				<defs>
					<!-- White keeps the scrim, black punches the box out of it. -->
					<mask id={maskId}>
						<rect x="0" y="0" width={canvasWidth} height={canvasHeight} fill="white" />
						<rect
							x={rect.x}
							y={rect.y}
							width={rect.width}
							height={rect.height}
							rx={rect.radius}
							ry={rect.radius}
							fill="black"
						/>
					</mask>
				</defs>
				<rect
					class="gp-toast-scrim"
					x="0"
					y="0"
					width={canvasWidth}
					height={canvasHeight}
					mask="url(#{maskId})"
					style="opacity:{dimAlpha};"
				/>
				<rect
					class="gp-toast-ring"
					x={rect.x}
					y={rect.y}
					width={rect.width}
					height={rect.height}
					rx={rect.radius}
					ry={rect.radius}
				/>
			</svg>
		{/if}
		<div class="gp-toast" role="status" {style}>
			{#if icon}
				<span class="gp-toast__icon" aria-hidden="true">{icon}</span>
			{/if}
			<span class="gp-toast__msg">
				{#if text}{text}{:else}{@render children?.()}{/if}
			</span>
		</div>
	</div>
{/if}

<style>
	.gp-toast-layer {
		position: absolute;
		left: 0;
		top: 0;
		display: flex;
		justify-content: center;
		/* A foreground cue: above the slide's blocks and the spotlight overlay, below
		   the deck chrome (later siblings). */
		z-index: 6;
		/* Keep the banner off the very edge of the canvas. */
		padding: 64px 48px;
		box-sizing: border-box;
	}
	.gp-toast-layer--top {
		align-items: flex-start;
	}
	.gp-toast-layer--center {
		align-items: center;
	}
	.gp-toast-layer--bottom {
		align-items: flex-end;
	}

	.gp-toast-dim {
		position: absolute;
		left: 0;
		top: 0;
		display: block;
		pointer-events: none;
	}
	.gp-toast-scrim {
		fill: var(--toast-scrim, #000000);
	}
	.gp-toast-ring {
		fill: none;
		stroke: var(--toast-ring, #f0a33e);
		stroke-width: var(--toast-ring-width, 3px);
		filter: drop-shadow(0 0 6px var(--toast-ring, #f0a33e));
	}

	.gp-toast {
		position: relative;
		display: inline-flex;
		align-items: center;
		gap: 0.6em;
		max-width: 80%;
		padding: 0.7em 1.2em;
		border-radius: 12px;
		background: var(--toast-bg, rgba(20, 22, 26, 0.94));
		color: var(--toast-fg, #d7dde5);
		border: 1px solid var(--toast-edge, rgba(255, 255, 255, 0.16));
		box-shadow: 0 10px 30px var(--toast-shadow, rgba(0, 0, 0, 0.45));
		font-size: 1.5em;
		line-height: 1.3;
	}
	.gp-toast__icon {
		flex: 0 0 auto;
		font-size: 1.1em;
		line-height: 1;
	}
	.gp-toast__msg :global(:first-child) {
		margin-top: 0;
	}
	.gp-toast__msg :global(:last-child) {
		margin-bottom: 0;
	}

	/* Fade the banner and the dim in on appear, out when leaving — pure CSS, so it
	   never touches the Web Animations API and drops cleanly under reduced-motion. The
	   dim rises from the edge the banner sits at; the scrim just cross-fades. */
	.gp-toast-layer .gp-toast,
	.gp-toast-layer .gp-toast-dim {
		animation: gp-toast-in 220ms ease both;
	}
	.gp-toast-layer--top .gp-toast {
		transform-origin: top center;
	}
	.gp-toast-layer.leaving .gp-toast,
	.gp-toast-layer.leaving .gp-toast-dim {
		animation: gp-toast-out 200ms ease forwards;
	}
	@keyframes gp-toast-in {
		from {
			opacity: 0;
			transform: translateY(12px);
		}
		to {
			opacity: 1;
			transform: translateY(0);
		}
	}
	@keyframes gp-toast-out {
		from {
			opacity: 1;
		}
		to {
			opacity: 0;
			transform: translateY(6px);
		}
	}
	@media (prefers-reduced-motion: reduce) {
		.gp-toast-layer .gp-toast,
		.gp-toast-layer .gp-toast-dim,
		.gp-toast-layer.leaving .gp-toast,
		.gp-toast-layer.leaving .gp-toast-dim {
			animation: none;
		}
	}
</style>
