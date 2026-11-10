<!--
  Shell for the VOD Recorder window. The root layout loads global.css (body is
  flex-centred for slides); undo that here so the panel is an ordinary scrolling page.
-->
<script lang="ts">
	import { onMount } from 'svelte';

	onMount(() => {
		document.documentElement.classList.add('gp-recorder');
		document.body.classList.add('gp-recorder');
		return () => {
			document.documentElement.classList.remove('gp-recorder');
			document.body.classList.remove('gp-recorder');
		};
	});
</script>

<slot />

<style>
	:global(html.gp-recorder),
	:global(body.gp-recorder) {
		display: block !important;
		justify-content: unset !important;
		align-items: unset !important;
		width: 100%;
		min-height: 100%;
		height: auto !important;
		margin: 0 !important;
		padding: 0 !important;
		background: #181818 !important;
		overflow: auto !important;
	}
</style>
