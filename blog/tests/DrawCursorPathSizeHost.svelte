<!-- Cursor `path`-mode per-waypoint size fixture: the second waypoint
     overrides the glyph box to 80, independent of the shared `size` prop
     (40) the first waypoint uses. -->
<script lang="ts">
	import Draw from '../src/lib/draw/Draw.svelte';
	import Cursor from '../src/lib/draw/Cursor.svelte';
</script>

<Draw title="Cursor path size host">
	<Cursor name="pointer" path={[[100, 100], { at: [400, 100], size: 80, click: true }]} animate={1} size={40} />
</Draw>
