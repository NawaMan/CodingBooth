<!--
  Spotlight — the note-driven highlight overlay.

  Mounted ONCE per deck by SlideDeck (a canvas-level singleton, like the minimap),
  so no slide has to place it. It is inert until something sets the `highlightTarget`
  store: then it looks that name up in the SAME blockAnchors registry a <Connector>
  resolves against, dims the rest of the canvas, and rings the named Block's box —
  so the spotlight follows the box even as it is dragged in ADJUST mode, and needs
  not one coordinate authored.

  What SETS the store is usually a <Note> line carrying `data-highlight="db"`: as the
  speaker covers that line in the presenter console, it publishes the name over the
  same localStorage relay as `publishContinue`, the audience window's SlideDeck hears
  it and calls `setHighlight`, and this overlay lights the box on the live slide — a
  laser pointer the audience sees, drawn in canvas space, so the console's preview
  shows it too for free. A slide can also drive `setHighlight` directly (a button, a
  Steps build); the overlay does not care who set the store.

  Rendering mirrors a standalone <Connector>: one canvas-spanning <svg>, always
  `pointer-events: none` (inline, so it never eats a click even before CSS lands).
  The dim is a full-canvas <rect> with the target box punched out of it by an SVG
  <mask>; the ring is a stroked <rect> over the same box. When no name is set — or a
  name resolves to no anchor — it renders NOTHING, so it is SSR-inert (nothing is
  highlighted at prerender) and cannot ship a stray box.
-->
<script lang="ts">
	import { blockAnchors } from '$lib/stores/blockAnchors';
	import { highlightTarget } from '$lib/stores/highlightTarget';
	import { spotlightRect } from '$lib/draw/spotlightCore';

	interface Props {
		/** Padding in canvas px between the Block's edge and the ring. */
		pad?: number;
		/** Ring corner radius in canvas px (capped at half the shorter side). */
		radius?: number;
		/** How dark the rest of the canvas goes, 0–1 (0 = ring only, no dim). Kept
		 *  light so the surrounding slide stays readable — the ring carries the focus. */
		dim?: number;
		/** Gentle breathing pulse on the ring; honours prefers-reduced-motion. */
		pulse?: boolean;
		canvasWidth?: number;
		canvasHeight?: number;
	}

	let {
		pad = 14,
		radius = 16,
		dim = 0.3,
		pulse = true,
		canvasWidth = 1920,
		canvasHeight = 1080
	}: Props = $props();

	// The active box: the named anchor, or undefined (name unset / not registered).
	const box = $derived($highlightTarget ? $blockAnchors.get($highlightTarget) : undefined);
	const rect = $derived(box ? spotlightRect(box, pad, radius, canvasWidth, canvasHeight) : null);

	// A stable, name-scoped mask id so two decks on one page (Text artifacts) don't
	// collide, and the same name always yields the same id (no churn on re-render).
	const maskId = $derived(`gp-spotlight-hole-${cssIdent($highlightTarget ?? '')}`);
	function cssIdent(s: string): string {
		return s.replace(/[^a-zA-Z0-9_-]/g, '-') || 'x';
	}

	const dimAlpha = $derived(Math.min(1, Math.max(0, dim)));
</script>

{#if rect}
	<svg
		class="spotlight-surface"
		class:pulse
		viewBox="0 0 {canvasWidth} {canvasHeight}"
		style="width:{canvasWidth}px; height:{canvasHeight}px; pointer-events:none;"
		aria-hidden="true"
	>
		{#if dimAlpha > 0}
			<defs>
				<!-- White = keep the scrim, black = punch a hole. The box is the hole. -->
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
				class="spotlight-scrim"
				x="0"
				y="0"
				width={canvasWidth}
				height={canvasHeight}
				mask="url(#{maskId})"
				style="opacity:{dimAlpha};"
			/>
		{/if}
		<rect
			class="spotlight-ring"
			x={rect.x}
			y={rect.y}
			width={rect.width}
			height={rect.height}
			rx={rect.radius}
			ry={rect.radius}
		/>
	</svg>
{/if}

<style>
	.spotlight-surface {
		position: absolute;
		left: 0;
		top: 0;
		display: block;
		/* Above the slide's own blocks (a spotlight is a foreground cue), but the
		   deck's chrome and Notes are later siblings and stay above it. */
		z-index: 5;
	}
	.spotlight-scrim {
		fill: var(--spotlight-scrim, #000000);
	}
	.spotlight-ring {
		fill: none;
		stroke: var(--spotlight-ring, #F0A33E);
		stroke-width: var(--spotlight-ring-width, 4px);
		/* A soft outer glow so the ring reads on any backdrop, the same crisp-at-scale
		   trick Connector uses — drawn in the SVG, so it scales with the canvas. */
		filter: drop-shadow(0 0 8px var(--spotlight-glow, #F0A33E));
	}
	/* Breathe the ring: opacity + a hair of glow. Excluded automatically for readers
	   who ask for less motion. */
	.spotlight-surface.pulse .spotlight-ring {
		animation: gp-spotlight-pulse 1.8s ease-in-out infinite;
	}
	@keyframes gp-spotlight-pulse {
		0%,
		100% {
			opacity: 1;
		}
		50% {
			opacity: 0.55;
		}
	}
	@media (prefers-reduced-motion: reduce) {
		.spotlight-surface.pulse .spotlight-ring {
			animation: none;
		}
	}
</style>
