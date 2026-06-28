<!--
  Blog article (Text artifact): "The Four Promises of a Booth" (2026-06-18).
  One long scrollable page; wraps the content in the shared TextPage shell.
-->
<script lang="ts">
	import TextPage from '$lib/components/TextPage.svelte';
	import Comments from '$lib/components/Comments.svelte';
</script>

<TextPage
	title="The Four Promises of a Booth"
	description="A booth makes four promises to every project: strong isolation, exact repeatability, effortless shareability, and real usability. Together they end 'works on my machine'."
	type="article"
>
	<slot />
	<Comments />
</TextPage>
