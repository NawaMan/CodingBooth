<!--
  ProgressBar — a thin "how far through the deck" bar.

  Drops along the bottom of a deck and fills as you page: slide 3 of 6 → the bar is
  half full. It reads getProgress() (the presentation API), so it needs no props to
  know where it is — the deck's slide list and the live route tell it. It counts
  VISIBLE slides only, so a hidden appendix neither inflates the total nor shows a bar
  (on an appendix `present` is false and the bar renders nothing).

  Purely declarative — no onMount, no browser API beyond the $page store every deck
  already reads — so it prerenders with the slide.

  Usage — in a deck's +layout.svelte, after setPages(pages):

    <SlideDeck ...><slot /></SlideDeck>
    <ProgressBar class="gp-chrome no-print" />

  The `gp-chrome no-print` tags are the deck's convention for "chrome": they retire the
  bar from a PNG capture and a printout, the same way the nav bar and TOC bow out.

  Colours come from roles.css (--progress-fill / --progress-track) and the thickness
  from --progress-height, so a theme reskins it by moving those tokens.

  Props:
    class — extra class(es) on the root (e.g. `gp-chrome no-print`). A slide's own
            scoped style won't reach it; use global CSS. See AGENTS.md.
    id    — DOM id for the root.
    style — extra inline CSS appended to the root.
-->
<script lang="ts">
	import { getProgress } from '$lib/presentation';

	/** DOM id for the root element. */
	export let id: string = '';
	/** Extra inline CSS appended to the bar. */
	export let style: string = '';
	/** Extra class(es) for the root element. A slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS. See AGENTS.md. */
	let klass: string = '';
	export { klass as class };

	const progress = getProgress();
</script>

{#if $progress.present && $progress.total > 0}
	<div
		class="progress-bar {klass}"
		id={id || undefined}
		role="progressbar"
		aria-valuemin="0"
		aria-valuemax={$progress.total}
		aria-valuenow={$progress.position}
		aria-label="Slide {$progress.position} of {$progress.total}"
		style={style || undefined}
	>
		<div class="fill" style="width: {($progress.fraction * 100).toFixed(3)}%"></div>
	</div>
{/if}

<style>
	.progress-bar {
		position: fixed;
		left: 0;
		bottom: 0;
		width: 100%;
		height: var(--progress-height, 6px);
		background: var(--progress-track, color-mix(in srgb, var(--progress-fill, #2980b9) 20%, transparent));
		z-index: 40;
		pointer-events: none;
	}
	.fill {
		height: 100%;
		background: var(--progress-fill, #2980b9);
		transition: width 240ms ease;
	}
</style>
