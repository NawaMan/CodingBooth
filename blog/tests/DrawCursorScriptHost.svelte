<!-- Cursor `script` fixture: a warpTo, then an `around` orbiting a named
     Block (proving script commands resolve names through blockAnchors just
     like `path` waypoints do, including the Connector "unresolved name
     drops everything" rule). Block spans 650..750 x 300..400, centre
     (700, 350); the warpTo lands directly above it at [700, 250], so the
     orbit's entry angle is a clean -90°. -->
<script lang="ts">
	import Block from '../src/lib/components/Block.svelte';
	import Draw from '../src/lib/draw/Draw.svelte';
	import Cursor from '../src/lib/draw/Cursor.svelte';

	export let dialX = 650;
	export let dialY = 300;
	export let showDial = true;
</script>

{#if showDial}
	<Block name="dial" x={dialX} y={dialY} width={100} height={100}>Dial</Block>
{/if}

<Draw title="Cursor script host">
	<Cursor
		name="pointer"
		script={[
			{ kind: 'warpTo', at: [700, 250] },
			{ kind: 'around', at: 'dial', rx: 100, ry: 50, times: 1, period: 1.6, click: true }
		]}
		size={40}
	/>
</Draw>
