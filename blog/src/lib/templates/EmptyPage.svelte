<!--
  EmptyPage — a full-canvas slide with no header chrome.

  TitlePage and ContentPage own a header band; EmptyPage does not. The default
  slot is the entire canvas (padding only), so Blocks, Draw diagrams, or any
  free-form layout start at the edges. Use it when the slide *is* the layout,
  not a titled document.

  Usage:

    <script>
      import EmptyPage from '$lib/templates/EmptyPage.svelte';
      import Block from '$lib/components/Block.svelte';
    </script>

    <EmptyPage>
      <Block name="hero" x={200} y={300} width={600} height={200}>…</Block>
    </EmptyPage>

  Not the same as WebPage / VideoPage: those fill the canvas with one media
  surface. EmptyPage is the blank stage for authored content.
-->
<script lang="ts">
	/** Inline style for the page root, applied last so it wins. */
	export let style: string = '';
	/** DOM id for the page root. */
	export let id: string = '';
	/** Extra class(es) for the page root. */
	let klass: string = '';
	export { klass as class };
</script>

<div class="empty-page {klass}" id={id || undefined} style={style || undefined}>
	<slot />
</div>

<style>
	.empty-page {
		position: relative;
		width: 100%;
		height: 100%;
		box-sizing: border-box;
	}
</style>
