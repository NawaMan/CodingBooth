<!--
  Example: Label component
  File: src/routes/slides/label-component.html/+page.svelte
-->
<script>
	import ContentPage from '$lib/templates/ContentPage.svelte';
	import QuickCode   from '$lib/components/QuickCode.svelte';
	import Label       from '$lib/components/Label.svelte';

	let hovered = false;
</script>

<ContentPage title="Label" subtitle="Hoverable highlighted inline text">
	<div style="line-height: 1.7em;">
		<p>
			Wrap any inline term in a <Label>Label</Label> to highlight it.
			Hover over <Label bind:isHovered={hovered}>this term</Label> &mdash; the cursor
			becomes a help pointer{#if hovered} <b>&mdash; hovering now!</b>{/if}.
		</p>
		<QuickCode style="margin-top: 0.5em;">
			&lt;Label&gt;important term&lt;/Label&gt;
		</QuickCode>
		<p style="margin-top: 0.6em; opacity: 0.8;">
			Props: <code>style</code>, <code>isHovered</code> (bindable). Dispatches
			<code>mouseover</code> / <code>mouseout</code> events.
		</p>
	</div>
</ContentPage>
