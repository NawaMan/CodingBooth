<!-- Cursor fixture: a named Block target (a fake button) and a Cursor whose
     flight ends on it, with a click ripple. The test moves/removes the Block
     (the same thing an ADJUST-mode drag / unmount does) and asserts the
     flight follows it, or drops entirely when the name is unresolved. -->
<script lang="ts">
	import Block from '../src/lib/components/Block.svelte';
	import Draw from '../src/lib/draw/Draw.svelte';
	import Cursor from '../src/lib/draw/Cursor.svelte';

	export let targetX = 500;
	export let targetY = 300;
	export let showTarget = true;
	/** 'two' = a two-leg flight from a fixed point onto the named target;
	 *  'one' = a static cursor sitting on the named target, no flight. */
	export let legs: 'two' | 'one' = 'two';
</script>

{#if showTarget}
	<Block name="target" x={targetX} y={targetY} width={200} height={100}>Target</Block>
{/if}

<Draw title="Cursor host">
	<Cursor
		name="pointer"
		path={legs === 'two'
			? [[100, 100], { at: 'target', click: true }]
			: [{ at: 'target', click: true }]}
		animate={1.5}
		delay={0.2}
		size={40}
	/>
</Draw>
