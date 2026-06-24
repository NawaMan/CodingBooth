<!--
  Example: Title Page

  To use this in your project, create a file at:
    src/routes/slides/title.html/+page.svelte

  And add a +layout.js next to it with:
    export const prerender = true;
    export const trailingSlash = "never";
-->
<script>
	import TitlePage  from '$lib/templates/TitlePage.svelte';
</script>

<TitlePage>
	<span slot="title">GeekPresent</span>
	<span slot="subtitle">How to Build Presentations</span>
	<span slot="subsubtitle">A quick guide to get you started<br/>
		<a href="../" style="opacity: 0.85;">↑ back to the home page</a></span>
</TitlePage>
