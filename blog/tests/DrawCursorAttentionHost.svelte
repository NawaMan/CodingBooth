<!-- Cursor `attention`/size fixture: warps in at a size OVERRIDE (60, not
     the default 40), then pulses in place — proving the pulse's "peak" and
     "settle" sizes both derive from the AMBIENT size the warp set, not the
     Cursor-level default. `shape` picks the glyph preset. -->
<script lang="ts">
	import Draw from '../src/lib/draw/Draw.svelte';
	import Cursor from '../src/lib/draw/Cursor.svelte';

	export let shape: 'arrow' | 'dot' | 'ring' = 'arrow';
</script>

<Draw title="Cursor attention host">
	<Cursor
		name="pointer"
		{shape}
		script={[
			{ kind: 'warpTo', at: [200, 200], size: 60 },
			{ kind: 'attention', times: 1, period: 0.6, scale: 1.5, click: true }
		]}
	/>
</Draw>
