<!--
  CssSnippet — a tiny, SPA-safe code block for short hand-written snippets.

  Renders the code immediately as a plain styled <pre>, then swaps in Shiki-
  highlighted HTML once the shared highlighter is ready (see $lib/utils/highlight).
  Shiki is a plain ESM module with one shared highlighter, so — unlike Monaco's
  Code/CodeBox — it survives this deck's client-side navigation + View Transitions.

  Pass the code as a string prop (so braces don't collide with Svelte's `{…}`):
    <CssSnippet code={`@view-transition { navigation: auto; }`} />
-->
<script lang="ts">
	import { onMount } from 'svelte';
	import { highlightToHtml } from '$lib/utils/highlight';

	export let code = '';
	/** Shiki language id. Defaults to css (what this deck shows). */
	export let lang = 'css';
	/** Fixed column width so it sits predictably beside a demo. */
	export let width = '820px';
	/** Inline style for the root element, applied last so it wins. */
	export let style: string = '';
	/** DOM id for the root element. */
	export let id: string = '';
	/** Extra class(es) for the root element. NOTE: a slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS (global.css / roles.css / a
	    :global(...) block) or a utility class. See AGENTS.md. */
	let klass: string = '';
	export { klass as class };

	let html = '';

	onMount(() => {
		let alive = true;
		highlightToHtml(code, lang)
			.then((out) => { if (alive) html = out; })
			.catch(() => { /* keep the plain fallback */ });
		return () => { alive = false; };
	});
</script>

<div class="css-snippet {klass}" id={id || undefined} style="width: {width}; {style}">
	{#if html}
		{@html html}
	{:else}
		<pre class="plain"><code>{code}</code></pre>
	{/if}
</div>

<style>
	.css-snippet {
		box-sizing: border-box;
		margin: 0;
		max-width: 100%;
		padding: 1.1em 1.3em;
		background: var(--code-title-bg, #111111);
		border: 1.5px solid var(--code-title-border, #333333);
		border-radius: 10px;
		overflow: auto;
		box-shadow: 0 8px 30px rgba(0, 0, 0, 0.45);
		/* Fixed px (in canvas coords) so it scales with the slide, like the demos. */
		font-family: 'Fira Code', monospace;
		font-size: 19px;
		line-height: 1.65;
	}

	/* Plain fallback (shown until Shiki resolves, and if highlighting fails). */
	.plain {
		margin: 0;
		font: inherit;
		white-space: pre;
		color: var(--surface-fg, #C7F5D4);
	}
	.plain code { font-family: inherit; }

	/* Shiki output: keep its token colours but drop its own background/margins so the
	   box styling above shows through and the sizing is inherited. */
	.css-snippet :global(pre.shiki) {
		margin: 0;
		font: inherit;
		white-space: pre;
		background-color: transparent !important;
	}
	.css-snippet :global(pre.shiki code) { font-family: inherit; }
</style>
