<!-- Host for `upright` mode: one sprite riding a polyline that runs RIGHTWARD
     then doubles back LEFTWARD, so the mirror must toggle. In upright mode the
     glyph stays level (rot = 0, no banking) and gets scaleX(-1) on the
     rightward stretch. A second sprite on the SAME path without `upright`
     (default orient banking) is the control — its rot varies and it never
     mirrors. `optOut` (default false) drops the upright flag so a test can
     assert the two sprites render identically when the flag is off. -->
<script lang="ts">
	import Draw from '../src/lib/draw/Draw.svelte';
	import Sprite from '../src/lib/draw/Sprite.svelte';

	// A shallow V: down-right to the elbow, then up-right — the x-direction
	// reverses at the elbow, so travel goes right→… no: both legs head rightward
	// in x. To force a left-going leg we go right, then LEFT-and-up.
	const route = { kind: 'polyline' as const, points: [[200, 500], [900, 900], [200, 300]] as [number, number][] };
	let { upright = true }: { upright?: boolean } = $props();
</script>

<Draw title="Sprite upright host">
	<Sprite name="rider" path={route} animate={3} size={80} {upright}>V</Sprite>
</Draw>
