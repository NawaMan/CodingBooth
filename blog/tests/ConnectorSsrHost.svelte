<!--
  SSR host for Connector: two named Blocks followed by connectors that find
  them by name. The ORDER is the point — Blocks register as their instance code
  runs, so a connector placed after them resolves during the server render.
-->
<script lang="ts">
	import Block from '$lib/components/Block.svelte';
	import Connector from '$lib/components/Connector.svelte';

	export let route: 'straight' | 'ortho' | 'curve' = 'straight';
	export let label: string | undefined = undefined;
	export let missing = false;
</script>

<Block name="api" x={100} y={100} width={200} height={100}>API</Block>
<Block name="db" x={500} y={100} width={200} height={100}>DB</Block>

<Connector from="api" to={missing ? 'nowhere' : 'db'} {route} {label} gap={0} thickness={4} />
