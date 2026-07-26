<!--
  DOM-test host for Block's `z` (stacking order): two overlapping named Blocks.
  Front / Back on one order it against the other, which is the whole point of the
  feature — so the two must render together (a lone Block has no siblings to
  order against, exactly like Connector's two-Block host).
-->
<script lang="ts">
	import Block from '$lib/components/Block.svelte';

	export let aZ = 0;
	export let bZ = 2;
</script>

<Block name="a" x={100} y={100} width={400} height={300} z={aZ}>A</Block>
<Block name="b" x={300} y={200} width={400} height={300} z={bZ}>B</Block>
