<!--
  Blog article (Text artifact): "Ending 'It Works on My Machine' with CodingBooth" (2026-05-29).
  One long scrollable page; wraps the content in the shared TextPage shell.
-->
<script lang="ts">
	import TextPage from '$lib/components/TextPage.svelte';
	import ViewCount from '$lib/components/ViewCount.svelte';
	import Comments from '$lib/components/Comments.svelte';
</script>

<TextPage
	title={'Ending "It Works on My Machine" with CodingBooth'}
	description={'Why the "works on my machine" problem keeps happening — and how CodingBooth ends it by giving every project its own isolated, reproducible, shareable development environment.'}
	type="article"
>
	<slot />
	<ViewCount />
	<Comments />
</TextPage>
