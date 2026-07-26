<!-- Host for Sprite path="name" riding a named Polyline: the <Polyline>
     publishes its live waypoints as a path source and the sprite rides them
     by reference. A Polyline draws NO editor of its own (unlike Line/Curve/
     Arc), so the rider must grow no chrome either — the tag is the single
     source of truth. -->
<script lang="ts">
	import Draw from '../src/lib/draw/Draw.svelte';
	import Polyline from '../src/lib/draw/Polyline.svelte';
	import Sprite from '../src/lib/draw/Sprite.svelte';
</script>

<Draw title="Sprite polyline ref host">
	<Polyline name="route" points={[[100, 900], [500, 500], [900, 900]]} smooth />
	<Sprite path="route" animate={3} size={80}>RIDER</Sprite>
</Draw>
