<!--
  The main presentation deck — landscape 1920x1080.

  All the canvas + scaling machinery lives in <SlideDeck>; this layout just picks
  the dimension and publishes the slide list. To make a portrait deck (e.g. a
  YouTube Short), copy this file and pass a portrait width/height instead — see
  src/routes/portrait/+layout.svelte.
-->
<script lang="ts">
	import SlideDeck    from '$lib/components/SlideDeck.svelte';
	import { pages }    from './pages';
	import { setPages } from '$lib/presentation';

	// Presentation-level favicon for the whole main deck — overrides the site
	// default (static/favicon.png) on every /slides/* page. The layout's head
	// renders at SSR (only the slide content is onMount-gated), so it lands in the
	// prerendered HTML. A single slide can still override this via its pages.ts entry.
	import favicon from '$lib/assets/codecat-zoom.png';

	// Publish this presentation's slide list to its slides (nav + ToC read it).
	// Must be set here, not in SlideDeck: the slotted slides read THIS layout's
	// context, not the shell's.
	setPages(pages);
</script>

<svelte:head>
	<link rel="icon" href={favicon} />
</svelte:head>

<SlideDeck
	{pages}
	title="GeekPresent"
	description="A guided tour of GeekPresent — build presentation decks from HTML, CSS and Svelte, one route per slide, with components you own."
	width={1920}
	height={1080}
	fill
>
	<slot />
</SlideDeck>
