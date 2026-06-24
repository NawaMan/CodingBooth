<!--
  Example: Available components overview
  File: src/routes/slides/components.html/+page.svelte
-->
<script>
	import ContentPage from '$lib/templates/ContentPage.svelte';
</script>

<ContentPage title="Components" subtitle="Reusable building blocks">
	<div>
		<b>Templates</b>
		<ul>
			<li><b>TitlePage</b> &mdash; title / subtitle / subsubtitle slots</li>
			<li><b>ContentPage</b> &mdash; title + subtitle props, default slot for content</li>
		</ul>
		<b>UI Components</b>
		<ul>
			<li><b>Box</b> &mdash; expandable overlay with animation (for images, code, etc.)</li>
			<li><b>Note</b> &mdash; speaker notes (visible below the slide in SCALED mode)</li>
			<li><b>Hint</b> &mdash; hint text at the bottom of a slide</li>
			<li><b>Label</b> &mdash; hoverable highlighted text</li>
			<li><b>YouTube</b> &mdash; YouTube thumbnail with QR code link</li>
			<li><b>WideDiv</b> &mdash; horizontally scrollable container</li>
			<li><b>Code</b> &mdash; Monaco editor for any language (read-only)</li>
			<li><b>JavaCode</b> &mdash; Monaco editor specialised for Java</li>
			<li><b>CodeBox</b> &mdash; Code inside an expandable Box</li>
			<li><b>JavaCodeBox</b> &mdash; JavaCode inside an expandable Box</li>
		</ul>
	</div>
</ContentPage>
