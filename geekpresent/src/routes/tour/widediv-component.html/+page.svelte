<!--
  Example: WideDiv component
  File: src/routes/slides/widediv-component.html/+page.svelte
-->
<script>
	import ContentPage from '$lib/templates/ContentPage.svelte';
	import WideDiv     from '$lib/components/WideDiv.svelte';
</script>

<ContentPage title="WideDiv" subtitle="Horizontally scrollable container (scroll with the mouse wheel)">
	<p>Hover the strip below and scroll your mouse wheel to pan it left and right:</p>
	<WideDiv outerWidth="900" innerWidth="1900" height="170">
		<div style="display: flex; gap: 1em; padding: 1em;">
			{#each Array.from({ length: 12 }) as _, i}
				<div style="min-width: 150px; height: 120px; display: flex; align-items: center; justify-content: center; border-radius: 8px; font-weight: bold; color: #000; background: hsl({i * 30}, 70%, 72%);">
					{i + 1}
				</div>
			{/each}
		</div>
	</WideDiv>
	<p style="margin-top: 0.6em; opacity: 0.8;">
		Props: <code>outerWidth</code>, <code>innerWidth</code>, <code>height</code> (pixels),
		<code>scrollable</code>.
	</p>
</ContentPage>
