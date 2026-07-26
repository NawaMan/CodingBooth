<!-- Connector fixture: two named Blocks and an arrow between them. The test
     moves a Block (the same thing a ADJUST-mode drag does) and asserts the
     arrow re-routes to follow it. -->
<script lang="ts">
	import Block from '../src/lib/components/Block.svelte';
	import Connector from '../src/lib/components/Connector.svelte';

	export let dbX = 500;
	export let dbY = 100;
	export let showDb = true;
	export let route: 'straight' | 'ortho' | 'curve' = 'straight';
</script>

<Block name="api" x={100} y={100} width={200} height={100}>API</Block>
{#if showDb}
	<Block name="db" x={dbX} y={dbY} width={200} height={100}>DB</Block>
{/if}

<Connector from="api" to="db" {route} gap={0} thickness={4} arrow="none" label="query" />
