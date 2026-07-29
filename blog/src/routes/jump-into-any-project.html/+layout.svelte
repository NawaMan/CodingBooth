<!--
  Blog article (Text artifact): "Jump Into Any Project with a Single Command" — UNPUBLISHED DRAFT.
  Reachable at its exact URL, but unlisted and noindexed until blog-publish runs.
-->
<script lang="ts">
	import TextPage from '$lib/components/TextPage.svelte';
	import ViewCount from '$lib/components/ViewCount.svelte';
	import FirebaseComments from '$lib/components/FirebaseComments.svelte';
</script>

<TextPage
	title="Jump Into Any Project with a Single Command"
	description="Getting a project ready to run shouldn't mean hours of fighting system dependencies. Grab a pre-configured workspace, run one booth command, and start building — no toolchains installed on your host, no version conflicts, no root-owned files."
	type="article"
	noindex
>
	<slot />
	<ViewCount />
	<FirebaseComments />
</TextPage>
