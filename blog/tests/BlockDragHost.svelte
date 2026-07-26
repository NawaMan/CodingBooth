<!--
  DOM-test host for Block's move drag — one Block at a known box, so a test can
  grab its body, stream a pointer move (with or without Shift), and read the
  landed left/top. Defaults to bounds="none" so a drag isn't silently clamped to
  the canvas; a test that wants clamping passes bounds="canvas".
-->
<script lang="ts">
	import Block from '$lib/components/Block.svelte';

	export let x = 100;
	export let y = 100;
	export let width = 400;
	export let height = 300;
	export let bounds: 'canvas' | 'none' = 'none';
</script>

<Block name="a" {x} {y} {width} {height} {bounds}>A</Block>
