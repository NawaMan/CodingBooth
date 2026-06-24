<!--
  Landing shell (route group "(home)").

  This layout applies only to the site root `/` — the route group keeps the
  Text shell off the presentations (slides/, geeklight/, …) and the other Text artifact
  (text.html/), which bring their own layouts. The root `/` is the project's
  index/home page, built as a Text artifact (one long page that grows down) so
  it shares the look and machinery of text.html via the shared TextPage shell.
-->
<script lang="ts">
	import TextPage from '$lib/components/TextPage.svelte';
</script>

<!-- The landing page is the project's highest-SEO surface: give it a descriptive
     title and description (the rest of the social/canonical tags are derived). -->
<TextPage
	title="GeekPresent — presentation slides & long-form texts in HTML, CSS and Svelte"
	description="GeekPresent turns HTML, CSS and Svelte into presentation slides and long-form texts — each slide a route, each component yours, all in a portable static site."
>
	<slot />
</TextPage>
