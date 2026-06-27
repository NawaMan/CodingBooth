<script>
	import TitlePage  from '$lib/templates/TitlePage.svelte';
	import ViewSource from '$lib/components/ViewSource.svelte';
	import source     from './+page.svelte?raw';
</script>

<TitlePage>
	<span slot="title">Thanks for stopping by</span>
	<span slot="subtitle">See you in the next post</span>
	<span slot="subsubtitle">
		<a href="../" style="opacity: 0.85;">↑ back to the blog index</a> &nbsp;·&nbsp;
		<a href="https://codingbooth.io" style="opacity: 0.85;">codingbooth.io</a>
	</span>
</TitlePage>

<ViewSource {source} path="src/routes/welcome/thank-you.html/+page.svelte" />
