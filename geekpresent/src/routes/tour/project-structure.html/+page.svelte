<!--
  Example: Content Page - Project Structure
  File: src/routes/slides/project-structure.html/+page.svelte
-->
<script>
	import ContentPage from '$lib/templates/ContentPage.svelte';
</script>

<ContentPage title="Project Structure" subtitle="Key files you need to know">
	<div style="line-height: 1.6em; font-family: 'Fira Code', monospace;">
		src/routes/<b>pages.ts</b> &mdash; Define your slide order here<br/>
		src/routes/slides/<b>my-slide.html/</b>+page.svelte &mdash; Each slide<br/>
		src/lib/templates/<b>TitlePage.svelte</b> &mdash; Title slide template<br/>
		src/lib/templates/<b>ContentPage.svelte</b> &mdash; Content slide template<br/>
		src/lib/components/ &mdash; Reusable UI components<br/>
		src/lib/styles/ &mdash; Global CSS styles
	</div>
</ContentPage>
