<!-- Host for the Line endpoint Shift-drag test: one horizontal, named Line in a
     Draw, so its endpoint handles have the <Draw> context (selection + Copy)
     they need. from/to are horizontal so a vertical Shift-drag of the `to`
     handle is the case the old ref-relative snap could not reach. -->
<script lang="ts">
	import Draw from '../src/lib/draw/Draw.svelte';
	import Line from '../src/lib/draw/Line.svelte';
</script>

<Draw title="Line shift-drag host">
	<Line name="seg" from={[100, 100]} to={[500, 100]} />
</Draw>
