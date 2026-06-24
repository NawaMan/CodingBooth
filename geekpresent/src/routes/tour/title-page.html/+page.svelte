<!--
  Example: How to use TitlePage template
  File: src/routes/slides/title-page.html/+page.svelte
-->
<script>
	import ContentPage from '$lib/templates/ContentPage.svelte';
	import CodeBox     from '$lib/components/CodeBox.svelte';
	import CtrlBtn     from '$lib/components/CtrlBtn.svelte';
	import QuickCode   from '$lib/components/QuickCode.svelte';
	import source      from './+page.svelte?raw';

	let showCode = false;

	const path = 'src/routes/slides/title-page.html/+page.svelte';
</script>

<ContentPage title="Using TitlePage" subtitle="The template for title and section divider slides">
	<p>TitlePage has three named slots:</p>
	<QuickCode>
		&lt;TitlePage&gt;<br/>
		&nbsp;&nbsp;&lt;span slot="<b>title</b>"&gt;Big Title&lt;/span&gt;<br/>
		&nbsp;&nbsp;&lt;span slot="<b>subtitle</b>"&gt;Subtitle&lt;/span&gt;<br/>
		&nbsp;&nbsp;&lt;span slot="<b>subsubtitle</b>"&gt;Your Name&lt;/span&gt;<br/>
		&lt;/TitlePage&gt;
	</QuickCode>
	<p>Navigation is handled automatically based on <b>pages.ts</b>.</p>
	<p>
		Prefer to read it in the editor? <CtrlBtn text="Show code" on:click={() => (showCode = true)} />
	</p>
</ContentPage>

<CodeBox code={source} language="html" title={path} bind:expanded={showCode} />
