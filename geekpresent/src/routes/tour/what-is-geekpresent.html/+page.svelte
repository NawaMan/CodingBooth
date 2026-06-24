<!--
  Example: Content Page - Introduction
  File: src/routes/slides/what-is-geekpresent.html/+page.svelte
-->
<script>
	import ContentPage from '$lib/templates/ContentPage.svelte';
</script>

<ContentPage title="What is GeekPresent?" subtitle="A SvelteKit-based presentation framework">
	<ul>
		<li><b>SvelteKit</b> static site &mdash; each slide is a route</li>
		<li><b>1920x1080</b> fixed canvas that scales to fit any screen</li>
		<li><b>Keyboard navigation</b> with arrow keys</li>
		<li><b>Table of Contents</b> sidebar (top-left button)</li>
		<li><b>Speaker notes</b> below the slide in SCALED mode (zoomed out)</li>
		<li>Deploys to <b>GitHub Pages</b> as a static site</li>
	</ul>
</ContentPage>
