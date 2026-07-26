<!-- Annotate fixture. The ink overlay is a canvas-level singleton that SlideDeck normally
     mounts, so the host just stands in for the deck: it supplies the canvas size, and the
     test drives the stores and the pointer directly. The ink PATH is set by the test
     (SlideDeck's job in real life). The top toolbar (with the ANNOTATE toggle) moved to
     <SlideToolbar>, so it is NOT part of this fixture — see SlideToolbarHost. -->
<script lang="ts">
	import Annotate from '../src/lib/components/Annotate.svelte';

	export let canvasWidth = 1920;
	export let canvasHeight = 1080;
	export let inkColors: (string | null)[] = [null, '#E5484D', '#3FA9F5'];
	export let snapPen = true;
</script>

<Annotate {canvasWidth} {canvasHeight} {inkColors} {snapPen} />
