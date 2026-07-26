<!-- Host for the teardown edge of select-to-front: a shape that can LEAVE while
     its chrome is hoisted into Draw's top layer. That is the one path where the
     chrome snippet outlives nothing else — Draw renders markup owned by a
     component that is being destroyed — so it gets its own host. -->
<script lang="ts">
	import Draw from '../src/lib/draw/Draw.svelte';
	import Line from '../src/lib/draw/Line.svelte';

	let { show = true }: { show?: boolean } = $props();
</script>

<Draw title="Hoist teardown host">
	<Line name="stay" from={[100, 100]} to={[500, 100]} />
	{#if show}
		<Line name="going" from={[100, 300]} to={[500, 300]} />
	{/if}
</Draw>
