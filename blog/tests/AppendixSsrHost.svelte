<!--
  SSR host for the appendix pair. `which` picks the side of the call being
  rendered: the APPENDIX itself (AppendixPage), or the CALLER's link into it
  (AppendixLink) — both of which have to survive the server render, since a hidden
  slide is discovered by the build's crawl through exactly that link.

  setPages() stands in for the presentation's +layout.svelte, so AppendixPage can
  resolve its deck fallback the way it does in the real deck.
-->
<script lang="ts">
	import AppendixPage from '$lib/templates/AppendixPage.svelte';
	import AppendixLink from '$lib/components/AppendixLink.svelte';
	import { setPages } from '$lib/presentation';
	import type { Page } from '$lib/utils/navigate';

	export let which: 'appendix' | 'link' = 'appendix';

	// `stub.html` is where the $app/stores stub says we are (see tests/stubs), so THAT
	// is the slide being rendered — and it must be the appendix itself (hidden), or the
	// template would rightly treat it as an ordinary slide of the deck and show no way
	// out. In the `link` case the same path is instead the CALLER, which is what
	// AppendixLink stamps as its return address.
	const pages: Array<Page> = [
		{ path: 'title.html', title: 'Title' },
		{ path: 'stub.html',  title: 'Appendix', hidden: true }
	];
	setPages(pages);
</script>

{#if which === 'appendix'}
	<AppendixPage title="How the GC marks" subtitle="The long version">
		<p>Tri-colour marking.</p>
	</AppendixPage>
{:else}
	<AppendixLink to="detail.html">how the GC actually marks</AppendixLink>
{/if}
