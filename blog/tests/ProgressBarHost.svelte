<!--
  Host for ProgressBar: publishes a deck (setPages) the way a presentation's
  +layout.svelte does, so the bar can resolve WHERE it is against the real slide
  list. The default deck is three visible slides plus `stub.html` — which is where
  the $app/stores stub says we are (tests/stubs), so with no setPageUrl the bar
  reports the LAST slide.
-->
<script lang="ts">
	import ProgressBar from '$lib/components/ProgressBar.svelte';
	import { setPages } from '$lib/presentation';
	import type { Page } from '$lib/utils/navigate';

	export let pages: Array<Page> = [
		{ path: 'a.html', title: 'A' },
		{ path: 'b.html', title: 'B' },
		{ path: 'c.html', title: 'C' },
		{ path: 'stub.html', title: 'Stub' }
	];

	setPages(pages);
</script>

<ProgressBar class="gp-chrome" />
