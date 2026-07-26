<!-- OverviewPage fixture: a small deck with one hidden appendix in the middle.
     setViewTransitions(true) so a tile click pages through SvelteKit's goto (the
     inert stub) rather than assigning window.location, which jsdom cannot do. The
     grid's own behaviour is identical either way — deckNav picks the strategy. -->
<script lang="ts">
	import { setViewTransitions } from '$lib/presentation';
	import OverviewPage from '../src/lib/components/OverviewPage.svelte';
	import type { Page } from '$lib/utils/navigate';

	setViewTransitions(true);

	export let currentPath = 'intro.html';
	export let deck = 'slides';
	export let pages: Array<Page> = [
		{ path: 'title.html', title: 'Title' },
		{ path: 'intro.html', title: 'Intro' },
		{ path: 'appendix-gc.html', title: 'Appendix — GC', hidden: true },
		{ path: 'outro.html', title: 'Outro' }
	];
</script>

<OverviewPage {pages} {currentPath} {deck} width={1920} height={1080} />
