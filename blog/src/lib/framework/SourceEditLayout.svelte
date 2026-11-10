<!--
  Full-viewport shell for the source-edit popup. The root layout still loads
  global.css (body is flex-centred for slides); we override that here so Monaco
  owns the window at 1:1 with no letterbox and no scale transform.
-->
<script lang="ts">
	import { onMount } from 'svelte';

	onMount(() => {
		document.documentElement.classList.add('gp-source-edit');
		document.body.classList.add('gp-source-edit');
		return () => {
			document.documentElement.classList.remove('gp-source-edit');
			document.body.classList.remove('gp-source-edit');
		};
	});
</script>

<slot />

<style>
	:global(html.gp-source-edit),
	:global(body.gp-source-edit) {
		display: block !important;
		justify-content: unset !important;
		align-items: unset !important;
		width: 100%;
		height: 100%;
		margin: 0 !important;
		padding: 0 !important;
		background: #1e1e1e !important;
		overflow: hidden;
	}
</style>
