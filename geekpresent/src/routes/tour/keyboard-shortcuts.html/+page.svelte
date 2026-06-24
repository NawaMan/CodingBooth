<!--
  Example: Keyboard Shortcuts
  File: src/routes/slides/keyboard-shortcuts.html/+page.svelte
-->
<script>
	import ContentPage from '$lib/templates/ContentPage.svelte';
</script>

<ContentPage title="Keyboard Shortcuts" subtitle="Built-in key bindings">
	<div style="line-height: 2em;">
		<table style="width: 100%; border-collapse: collapse;">
			<tr style="border-bottom: 1px solid #444;">
				<td style="padding: 0.2em 1em;"><b>Arrow Left</b></td>
				<td>Previous slide</td>
			</tr>
			<tr style="border-bottom: 1px solid #444;">
				<td style="padding: 0.2em 1em;"><b>Arrow Right</b></td>
				<td>Next slide</td>
			</tr>
			<tr>
				<td style="padding: 0.2em 1em;"><b>Escape</b></td>
				<td>Close Table of Contents / Box</td>
			</tr>
		</table>
	</div>
</ContentPage>
