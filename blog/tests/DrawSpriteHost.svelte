<!-- Host for Sprite editing tests: a Draw surface with one flying Sprite
     (three stops, a rotation + easing flourish) so the ADJUST-mode ghosts,
     handles and keyframe panel have something to drive. -->
<script lang="ts">
	import Draw from '../src/lib/draw/Draw.svelte';
	import Sprite from '../src/lib/draw/Sprite.svelte';
</script>

<Draw title="Sprite host">
	<Sprite
		name="rocket"
		animate={2.5}
		fontScale={0.84}
		stops={[
			{ pct: 0, x: 100, y: 800, w: 56, h: 56, rot: 20, ease: 'ease-in' },
			{ pct: 50, x: 900, y: 400, w: 140, h: 135, rot: 26 },
			{ pct: 100, x: 1500, y: 430, w: 228, h: 219, rot: -45, ease: 'ease-out' }
		]}
	>ROCKET</Sprite>

	<!-- A LOCKED sprite (e.g. calculated stops): flies like any other, but must
	     grow zero ADJUST chrome and never register for selection/Copy. -->
	<Sprite
		name="locked"
		lock
		animate={2}
		stops={[
			{ pct: 0, x: 0, y: 0, w: 50, h: 50 },
			{ pct: 100, x: 500, y: 500, w: 50, h: 50 }
		]}
	>LOCKED</Sprite>

	<!-- Paused: flies with the same generated keyframes, but starts (and
	     stays) frozen at its base pose until `paused` flips off. -->
	<Sprite
		name="frozen"
		lock
		paused
		animate={2}
		stops={[
			{ pct: 0, x: 200, y: 200, w: 50, h: 50 },
			{ pct: 100, x: 700, y: 700, w: 50, h: 50 }
		]}
	>FROZEN</Sprite>
</Draw>
