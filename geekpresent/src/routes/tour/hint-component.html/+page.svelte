<!--
  Example: Hint component
  File: src/routes/slides/hint-component.html/+page.svelte
-->
<script>
	import ContentPage from '$lib/templates/ContentPage.svelte';
	import QuickCode   from '$lib/components/QuickCode.svelte';
	import Hint        from '$lib/components/Hint.svelte';
</script>

<ContentPage title="Hint" subtitle="A subtle prompt pinned to the bottom of a slide">
	<p>
		<b>Hint</b> shows faint, bold text at the bottom of the slide &mdash; handy for
		cues like &ldquo;click to expand&rdquo; or &ldquo;scroll right&rdquo;.
		Look at the bottom of this slide. &darr;
	</p>
	<QuickCode style="margin-top: 0.5em;">
		&lt;Hint text="Look below &mdash; this is a hint" /&gt;
	</QuickCode>
	<p style="margin-top: 0.6em; opacity: 0.8;">
		Props: <code>text</code>, <code>isVisible</code> (default <code>true</code>).
	</p>
</ContentPage>

<Hint text="Look below — this is a hint" />
