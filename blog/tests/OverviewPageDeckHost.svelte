<!-- OverviewPage AS THE DECK MOUNTS IT: with a TableOfContent beside it, in the
     same order SlideDeck renders them (ToC first, grid second).

     That order is the whole point of this fixture. Both components listen for
     Escape on `window`, and the ToC's onMount runs first, so its listener is
     called first. It used to preventDefault() EVERY Escape — open or shut — and
     the grid, which skipped an already-handled event, could then never close.

     Testing the grid alone hid that completely: with no ToC beside it, nothing
     was there to swallow the key. -->
<script lang="ts">
	import { setViewTransitions } from '$lib/presentation';
	import TableOfContent from '../src/lib/components/TableOfContent.svelte';
	import OverviewPage from '../src/lib/components/OverviewPage.svelte';
	import type { Page } from '$lib/utils/navigate';

	setViewTransitions(true);

	export let currentPath = 'intro.html';
	export let pages: Array<Page> = [
		{ path: 'title.html', title: 'Title' },
		{ path: 'intro.html', title: 'Intro' },
		{ path: 'outro.html', title: 'Outro' }
	];
</script>

<TableOfContent {pages} />
<OverviewPage {pages} {currentPath} width={1920} height={1080} />
