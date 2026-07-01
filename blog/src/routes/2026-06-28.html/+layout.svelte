<!--
  Blog article (Text artifact): "Onboard Quick, Onboard Right" (2026-06-28).
  One long scrollable page; wraps the content in the shared TextPage shell.
-->
<script lang="ts">
	import TextPage from '$lib/components/TextPage.svelte';
	import ViewCount from '$lib/components/ViewCount.svelte';
	import FirebaseComments from '$lib/components/FirebaseComments.svelte';
</script>

<TextPage
	title="Onboard Quick, Onboard Right"
	description="Setting up a project fast is only half the job — setting it up right is the other half. Why onboarding shouldn't rely on luck or constant vigilance, and how a booth gets you in both quick and right."
	type="article"
>
	<slot />
	<ViewCount />
	<FirebaseComments />
</TextPage>
