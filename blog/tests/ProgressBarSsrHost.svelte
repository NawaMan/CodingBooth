<!--
  SSR host for ProgressBar. setPages() stands in for the deck's +layout.svelte, so the
  bar can locate itself; `stub.html` is where the $app/stores stub says we are (the last
  of these three visible slides), so a server render shows a full bar reading "3 of 3".
-->
<script lang="ts">
	import ProgressBar from '$lib/components/ProgressBar.svelte';
	import { setPages } from '$lib/presentation';
	import type { Page } from '$lib/utils/navigate';

	const pages: Array<Page> = [
		{ path: 'a.html', title: 'A' },
		{ path: 'b.html', title: 'B' },
		{ path: 'stub.html', title: 'Stub' }
	];
	setPages(pages);
</script>

<ProgressBar class="gp-chrome" />
