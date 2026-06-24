<!--
  Example: Conclusion / Thank You page
  File: src/routes/slides/thank-you.html/+page.svelte
-->
<script>
	import TitlePage from '$lib/templates/TitlePage.svelte';
</script>

<TitlePage>
	<span slot="title">Thank You!</span>
	<span slot="subtitle">Now go build your presentation</span>
	<span slot="subsubtitle">Copy these examples into src/routes/slides/<br/>
		<a href="../" style="opacity: 0.85;">↑ back to the home page</a></span>
</TitlePage>
