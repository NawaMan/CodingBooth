<!-- Host for Sprite polyline-path tests: one sprite zig-zagging a straight
     polyline of three equal legs, so the corner-snapping heading, the
     per-waypoint handle editor and the polyline literal serialization have
     something to drive. Geometry mirrors DrawSpritePathHost (start [100, 900],
     size 80) so the base-pose assertions carry over. -->
<script lang="ts">
	import Draw from '../src/lib/draw/Draw.svelte';
	import Sprite from '../src/lib/draw/Sprite.svelte';
</script>

<Draw title="Sprite polyline host">
	<Sprite
		name="zig"
		path={{ kind: 'polyline', points: [[100, 900], [500, 500], [900, 900], [1300, 500]] }}
		animate={3}
		size={80}
	>ZIG</Sprite>
</Draw>
