<!-- Host for Sprite PATH-mode tests: one sprite riding a cubic bézier, so the
     sampling (position + tangent), the curve-handle editor and the literal
     path serialization have something to drive. Small `samples` keeps the
     generated keyframes easy to assert against. -->
<script lang="ts">
	import Draw from '../src/lib/draw/Draw.svelte';
	import Sprite from '../src/lib/draw/Sprite.svelte';
</script>

<Draw title="Sprite path host">
	<Sprite
		name="flier"
		path={{ kind: 'cubic', from: [100, 900], c1: [500, 100], c2: [1400, 1000], to: [1800, 200] }}
		animate={3}
		delay={1.5}
		size={80}
	>FLIER</Sprite>
</Draw>
