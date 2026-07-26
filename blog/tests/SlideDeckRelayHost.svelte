<script lang="ts">
	// Host for the cross-window relay test. It exists for ONE reason: to turn view
	// transitions on before SlideDeck mounts, because deckNav.navigate() only routes
	// through `goto` (which the $app/navigation stub records) when a deck opts into
	// client-side paging — otherwise it assigns window.location.href, which jsdom
	// cannot observe. Same deck, same relay, just a navigation the test can see.
	import { setViewTransitions } from '$lib/presentation';
	import SlideDeck from '$lib/components/SlideDeck.svelte';

	export let pages: { path: string; title: string }[] = [];

	setViewTransitions(true);
</script>

<SlideDeck {pages} />
