<!--
  ViewSource — a "show me the source" control for a slide (or Text).

  Drop it on a page to add a small corner button that pops the page's own source
  up in a CodeBox, titled with its file path. The deck is the documentation, so
  this lets a viewer read exactly the text that produced the slide they're on.

  Usage (per page — the ?raw import and path can't be auto-derived here, so each
  page passes its own):

    <script>
      import ViewSource from '$lib/components/ViewSource.svelte';
      import source     from './+page.svelte?raw';   // Vite hands back the file's bytes
    </script>

    <ViewSource {source} path="src/routes/slides/title.html/+page.svelte" />

  Monaco has no native `svelte` mode, so the source is highlighted as `html`
  (the closest built-in); the displayed text itself is exact.
-->
<script lang="ts">
	import CtrlBtn from '$lib/components/CtrlBtn.svelte';
	import CodeBox from '$lib/components/CodeBox.svelte';

	/** The page source, typically `import source from './+page.svelte?raw'`. */
	export let source: string;
	/** The path shown in the CodeBox title bar. */
	export let path: string = '';
	/** Monaco language for highlighting. Svelte files read best as `html`. */
	export let language: string = 'html';
	/** Button label. */
	export let text: string = '</> Source';

	let expanded = false;
</script>

<div class="view-source">
	<CtrlBtn {text} hoverText="View source" isSelected={expanded} on:click={() => (expanded = true)} />
</div>

<CodeBox code={source} {language} title={path} bind:expanded />

<style>
	/* Bottom-right corner — the one piece of chrome not already taken (ToC is
	   top-left, the display-mode control top-right, the nav bar bottom-left). */
	.view-source {
		position: absolute;
		bottom: 0px;
		right: 5px;
	}
</style>
