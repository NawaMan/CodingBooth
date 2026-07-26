<!-- Host for Sprite path="name" tests: a named Curve and a Sprite that rides
     it by reference — same geometry as DrawSpritePathHost so the sampling
     assertions carry over, but the CURVE owns the points and its handles are
     the only editor. Includes a rider with an unknown name, which must render
     nothing (never a glyph stranded at a fallback pose). -->
<script lang="ts">
	import Curve from '../src/lib/draw/Curve.svelte';
	import Draw from '../src/lib/draw/Draw.svelte';
	import Sprite from '../src/lib/draw/Sprite.svelte';
</script>

<Draw title="Sprite ref host">
	<Curve name="road" from={[100, 900]} to={[1800, 200]} c1={[500, 100]} c2={[1400, 1000]} />
	<Sprite path="road" animate={3} ease="linear" size={80}>RIDER</Sprite>
	<Sprite path="ghost-road" animate={3} size={80}>LOST</Sprite>
</Draw>
