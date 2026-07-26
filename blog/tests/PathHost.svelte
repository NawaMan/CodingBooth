<!-- Host pinning the canonical single-line <Path> tag Copy emits — the exact
     form the ADJUST "Save" endpoint matches literally (patchSource
     indexOf(oldTag)). The test selects each Path WITHOUT dragging and asserts
     its Copy output equals the known canonical string, so the serializer's
     format (attribute order, segment literals) can't silently drift. -->
<script lang="ts">
	import Draw from '../src/lib/draw/Draw.svelte';
	import Path from '../src/lib/draw/Path.svelte';
</script>

<Draw title="Path source round-trip">
	<Path
		name="flow"
		start={[200, 620]}
		segments={[
			{ to: [520, 620] },
			{ to: [820, 470], c1: [670, 620] },
			{ to: [1180, 470], bend: 0.5 },
			{ to: [1520, 620], c1: [1360, 470], c2: [1400, 620] }
		]}
		arrow="end"
		color="#2980b9"
		thickness={6}
		label="a straight line, a curve, an arc and a cubic chained into one arrow"
		labelText="one continuous stroke"
		labelAt={0.4}
		labelOffset={40}
	/>
	<Path
		name="wave"
		start={[220, 940]}
		segments={[
			{ to: [480, 940], bend: 0.6 },
			{ to: [740, 940], bend: -0.6 },
			{ to: [1000, 940], bend: 0.6 },
			{ to: [1260, 940], bend: -0.6 },
			{ to: [1520, 940], bend: 0.6 }
		]}
		color="#f39c12"
		thickness={5}
		label="a serpentine of alternating arcs drawing itself on as one stroke"
		draw={2.5}
	/>
</Draw>
