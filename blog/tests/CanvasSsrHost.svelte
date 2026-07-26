<!-- SSR host for the Canvas prerender test. The canvas PIXELS are client-only,
     but the hidden finite @keyframes CLOCK is declarative, so it must appear in
     the server output — that's what lets AnimationBar find the timeline the
     instant JS boots. draw() is browser/$effect-gated, so it never runs here. -->
<script lang="ts">
	import { Canvas } from '../src/lib/draw';
</script>

<Canvas
	duration={5}
	draw={(ctx, { width, height }) => ctx.clearRect(0, 0, width, height)}
/>
