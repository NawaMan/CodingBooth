<!--
  Blog index shell (route group "(home)").

  This layout applies only to the site root `/`, which is served at
  codingbooth.io/blog/. The route group keeps the Text shell off the post decks
  (welcome/, …), which bring their own SlideDeck layout. The root `/` is the
  blog's index page, built as a Text artifact (one long page that grows down) so
  it shares the look and machinery of the shared TextPage shell.
-->
<script lang="ts">
	import TextPage from '$lib/components/TextPage.svelte';
</script>

<!-- The index is the blog's highest-SEO surface: give it a descriptive title
     and description (the rest of the social/canonical tags are derived). -->
<TextPage
	title="The CodingBooth Blog — deep dives into reproducible dev environments"
	description="The CodingBooth blog — feature deep-dives, hands-on examples, and project news for CodingBooth: reproducible, isolated development environments in a Docker container that runs as you."
>
	<slot />
</TextPage>
