<!--
  Note — a speaker note, rendered just below the slide in the canvas coordinate
  space (so it scales with the slide). Shown only in SCALED display mode: there
  the slide is at an exact factor and the note sits below it, visible when the
  slide is smaller than the viewport and reachable by scrolling otherwise. In
  FITTED mode the slide fills the window, so the note is hidden (no scroll).
-->
<script lang="ts">
	import { displayMode } from '$lib/stores/displayMode';
	$: visible = $displayMode === 'SCALED';
</script>

{#if visible}
<div class="note no-print">
	<slot></slot>
</div>
{/if}

<style>
.note {
	position: absolute;
	display: block;
	width: calc(100% - 30px);
	top: calc(100% + 30px);
	left: 0;
	padding: 15px;

	color: #000;
	background-color: beige;

	border: 1.5px solid #fff;
	border-radius: 7.5px;

	min-height: 225px;
	max-height: 225px;
	overflow-y: scroll;

	font-size: larger;
	font-family: ui-sans-serif, system-ui, Segoe UI, Helvetica, Apple Color Emoji, Arial, sans-serif, Segoe UI Emoji, Segoe UI Symbol;
}
</style>
