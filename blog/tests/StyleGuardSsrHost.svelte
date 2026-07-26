<!--
  SSR fixture: a Block whose author `style` collides with the geometry the props
  own, next to one whose style is purely cosmetic. Prerendered HTML must show the
  props' box (never the style's), keep the cosmetics, and carry no ADJUST chrome.
-->
<script lang="ts">
	import Block from '../src/lib/components/Block.svelte';
</script>

<Block name="pinned" x={200} y={300} width={400} height={160} style="left: 40px; color: red">
	<p>SSR_PINNED_MARKER</p>
</Block>

<Block name="clean" x={10} y={20} width={100} height={50} style="border: 1px solid red">
	<p>SSR_CLEAN_MARKER</p>
</Block>
