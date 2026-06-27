<script>
	import TitlePage  from '$lib/templates/TitlePage.svelte';
	import ViewSource from '$lib/components/ViewSource.svelte';
	import source     from './+page.svelte?raw';
</script>

<TitlePage>
	<span slot="title">The CodingBooth Blog</span>
	<span slot="subtitle">Notes from inside the booth</span>
	<span slot="subsubtitle">Deep dives into the pieces that make CodingBooth tick<br/>
		<a href="../" style="opacity: 0.85;">↑ back to the blog index</a></span>
</TitlePage>

<ViewSource {source} path="src/routes/welcome/title.html/+page.svelte" />
