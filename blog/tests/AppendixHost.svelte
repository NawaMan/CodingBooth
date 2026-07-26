<!--
  Host for AppendixPage: publishes a deck (setPages) the way a presentation's
  +layout.svelte does, so the template can resolve its return address against the
  real slide list, work out which appendix RUN it is in, and fall back to the deck's
  first visible slide.

  The default deck holds a two-slide appendix (one chapter) called from `caller.html`.
-->
<script lang="ts">
	import AppendixPage from '$lib/templates/AppendixPage.svelte';
	import { setPages } from '$lib/presentation';
	import type { Page } from '$lib/utils/navigate';

	export let pages: Array<Page> = [
		{ path: 'title.html',    title: 'Title' },
		{ path: 'caller.html',   title: 'Caller' },
		{ path: 'detail.html',   title: 'Detail 1', hidden: true },
		{ path: 'detail-2.html', title: 'Detail 2', hidden: true },
		{ path: 'thanks.html',   title: 'Thanks' }
	];
	export let title = 'Appendix';
	/** Opt into the animated detour (drops in from above, lifts away on the way out). */
	export let transition = false;

	setPages(pages);
</script>

<AppendixPage {title} {transition}>
	<p data-testid="body">The long version.</p>
</AppendixPage>
