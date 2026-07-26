<!-- Cursor `startOn` fixture: a plain two-point path (no Block dependency —
     the trigger behaviour is orthogonal to how targets resolve), gated on a
     named trigger pulse instead of autoplaying on mount. -->
<script lang="ts">
	import Draw from '../src/lib/draw/Draw.svelte';
	import Cursor from '../src/lib/draw/Cursor.svelte';
</script>

<Draw title="Cursor trigger host">
	<Cursor
		name="pointer"
		startOn="go"
		path={[[100, 100], { at: [500, 300], click: true }]}
		animate={1.5}
		size={40}
	/>
</Draw>
