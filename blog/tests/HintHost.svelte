<script lang="ts">
	import Hint from '../src/lib/components/Hint.svelte';

	export let text = 'A hint';
	export let movable = true;
	export let dismissible = true;
	export let isVisible = true;
</script>

<Hint {text} {movable} {dismissible} {isVisible} />
