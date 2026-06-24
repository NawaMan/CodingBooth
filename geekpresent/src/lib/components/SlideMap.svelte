<!--
  SlideMap — a schematic minimap for SCALED mode.

  Shows only the outer frame (the whole slide, at the canvas aspect) and an inner
  rectangle marking the section currently on screen. It deliberately renders NO
  slide content — it is an orientation aid for panning a zoomed-in slide, nothing
  more. SlideDeck mounts it in the screen-fixed overlay and only when the scaled
  slide overflows the viewport. `rect` is fractions (0..1) of the scaled slide.
-->
<script lang="ts">
	export let width  = 1920;
	export let height = 1080;
	export let rect: { left: number; top: number; width: number; height: number } =
		{ left: 0, top: 0, width: 1, height: 1 };

	/** Outer box width in screen px; height follows the canvas aspect. */
	const MAP_W = 160;
	$: mapH = Math.round(MAP_W / (width / height));
</script>

<div class="map no-print" style="width:{MAP_W}px; height:{mapH}px;">
	<div
		class="view"
		style="left:{rect.left * 100}%; top:{rect.top * 100}%; width:{rect.width * 100}%; height:{rect.height * 100}%;"
	></div>
</div>

<style>
	.map {
		position: absolute;
		bottom: 12px;
		right: 12px;
		background: var(--map-bg, rgba(20, 24, 28, 0.85));
		border: 1.5px solid var(--frame-border, #CCCCCC);
		box-shadow: 0 2px 8px rgba(0, 0, 0, 0.4);
	}
	.map .view {
		position: absolute;
		box-sizing: border-box;
		border: 2px solid var(--map-view, #FF00AA);
		background: var(--map-view-fill, rgba(255, 0, 170, 0.12));
		/* Stay visible even when the visible slice is tiny (deep zoom-in). */
		min-width: 4px;
		min-height: 4px;
	}
</style>
