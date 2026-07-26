<!-- Host for the Polyline ADJUST editor: a single smooth, named Polyline in a
     Draw, so its selection, per-waypoint handles and Copy tag have something
     to drive (the Draw provides the selection/Copy toolbar). -->
<script lang="ts">
	import Draw from '../src/lib/draw/Draw.svelte';
	import Polyline from '../src/lib/draw/Polyline.svelte';
</script>

<Draw title="Polyline edit host">
	<Polyline name="route" points={[[100, 900], [500, 500], [900, 900]]} smooth />
</Draw>
