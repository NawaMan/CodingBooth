<!--
  Example: How to use ContentPage template
  File: src/routes/slides/content-page.html/+page.svelte
-->
<script>
	import ContentPage from '$lib/templates/ContentPage.svelte';
	import CodeBox     from '$lib/components/CodeBox.svelte';
	import CtrlBtn     from '$lib/components/CtrlBtn.svelte';
	import QuickCode   from '$lib/components/QuickCode.svelte';
	import source      from './+page.svelte?raw';

	let showCode = false;

	const path = 'src/routes/slides/content-page.html/+page.svelte';
</script>

<ContentPage title="Using ContentPage" subtitle="The template for most of your slides">
	<p>ContentPage takes <b>title</b> and <b>subtitle</b> props, with a default slot for content:</p>
	<QuickCode>
		&lt;ContentPage title="My Title" subtitle="Optional"&gt;<br/>
		&nbsp;&nbsp;&lt;p&gt;Any HTML or Svelte components here.&lt;/p&gt;<br/>
		&nbsp;&nbsp;&lt;ul&gt;&lt;li&gt;Bullet points&lt;/li&gt;&lt;/ul&gt;<br/>
		&lt;/ContentPage&gt;
	</QuickCode>
	<p>The content area is styled with justified text, straight from the template default &mdash; no per-slide font tuning.</p>
	<p>
		Prefer to read it in the editor? <CtrlBtn text="Show code" on:click={() => (showCode = true)} />
	</p>
</ContentPage>

<CodeBox code={source} language="html" title={path} bind:expanded={showCode} />
