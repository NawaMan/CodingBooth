<!--
  "Welcome to the CodingBooth Blog" — the first blog post, as a landscape
  1920x1080 deck. Each blog post is its own presentation (or Text) under
  src/routes/<slug>/; this one is the welcome mat. Copy this folder to start
  another post (see AGENTS.md → "Add a second presentation").
-->
<script lang="ts">
	import SlideDeck    from '$lib/components/SlideDeck.svelte';
	import { pages }    from './pages';
	import { setPages } from '$lib/presentation';

	// Publish this post's slide list to its slides (nav + ToC read it).
	setPages(pages);
</script>

<!--
  No per-post favicon override: we fall back to the site default
  (static/favicon.png, the CodingBooth icon), referenced relatively from app.html
  so it resolves correctly under the /blog/ subpath. An imported asset placed in
  <svelte:head> would emit a root-absolute /_app/... path that 404s under a subpath.
-->
<SlideDeck
	{pages}
	title="Welcome to the CodingBooth Blog"
	description="Welcome to the CodingBooth blog — short, focused deep dives into the bits and pieces that make CodingBooth tick."
	width={1920}
	height={1080}
	fill
>
	<slot />
</SlideDeck>
