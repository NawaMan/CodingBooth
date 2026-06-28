<!-- Title page. -->
<script lang="ts">
	import NavigationBar from '$lib/components/NavigationBar.svelte';

	import { getPageNavigation }   from '$lib/utils/navigate';
	import { type PageNavigation } from '$lib/utils/navigate';
	import { getPages }            from '$lib/presentation';
	import { page }                from "$app/stores";

	const pages = getPages();
	let navigation: PageNavigation;

	$: {
		const currentPath = $page.url.pathname.split("/").pop() || null;
		navigation = getPageNavigation(pages, currentPath || "", "./");
	}
</script>

<div class="page">
	<h1 class="title"     ><slot name="title"       /></h1>
	<p class='subtitle'   ><slot name="subtitle"    /></p>
	<p class='subsubtitle'><slot name="subsubtitle" /></p>
</div>

<NavigationBar
	firstLink={navigation.first}
	prevLink={navigation.prev}
	nextLink={navigation.next}
	lastLink={navigation.last}
/>

<style>
	.page {
		/* cosmetic */
		width: 100%;
		padding: auto;
		margin: auto;
	}
	.page .title {
		padding: 0px;
		margin: 0px;
		text-align: center;
		font-size: 5em;
		font-family: 'Playfair Display Bold', 'Cormorant Garamond', serif;
		color: var(--page-title-fg, #F0A33E);
	}
	.page .subtitle {
		text-align: center;
		font-size: 3em;
	}
	.page .subsubtitle {
		text-align: center;
		font-size: 2em;
	}
</style>
