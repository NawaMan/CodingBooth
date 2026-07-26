<!--
  QuickCode — the small inline "code snippet" box used across slides.

  A lightweight, dark monospace block for short hand-written snippets. Prefer the
  `code` prop: pass the raw snippet as a string and it is syntax-highlighted by
  Shiki (the shared singleton highlighter in $lib/utils/highlight), which — unlike
  Monaco's Code/CodeBox — survives this deck's client-side navigation + View
  Transitions. It renders as plain text immediately, then swaps in the highlighted
  HTML once the highlighter is ready.

    <QuickCode lang="svelte" code={`<Note>
      <p>Remember to explain X.</p>
    </Note>`} />

  `lang` is a Shiki language id (default `svelte`; `javascript`, `python`, `go`,
  `bash` and `css` are also available — see highlight.ts). For real, full-featured
  code (folding, minimap) use Code / CodeBox (Monaco) instead.

  Legacy: when no `code` is given it renders its slot verbatim (pre-escaped HTML
  with <br/> and &nbsp;), so older call sites keep working unchanged.

  The `style` prop appends extra CSS to the box (e.g. `style="margin-top: 0.5em;"`).
-->
<script lang="ts">
	import { onMount } from 'svelte';
	import { highlightToHtml } from '$lib/utils/highlight';

	/** Raw snippet source. When set, it is syntax-highlighted; when omitted the slot is used. */
	export let code: string | undefined = undefined;
	/** Shiki language id for `code`. Defaults to svelte (most slides show component markup). */
	export let lang: string = 'svelte';
	/** Extra inline CSS appended to the box (e.g. spacing tweaks per slide). */
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
		if (code === undefined) return;
		let alive = true;
		highlightToHtml(code, lang)
			.then((out) => { if (alive) html = out; })
			.catch(() => { /* keep the plain fallback */ });
		return () => { alive = false; };
	});
</script>

<div class="quick-code {klass}" id={id || undefined} {style}>
	{#if code !== undefined}
		{#if html}
			{@html html}
		{:else}
			<pre class="plain"><code>{code}</code></pre>
		{/if}
	{:else}
		<slot />
	{/if}
</div>

<style>
	.quick-code {
		font-family: 'Fira Code', monospace;
		font-size: 0.85em;
		background: var(--quickcode-bg, #111111);
		color: var(--quickcode-fg, inherit);
		padding: 0.5em 1em;
		border-radius: 5px;
		line-height: 1.8em;
	}

	/* Plain fallback (shown until Shiki resolves, and if highlighting fails). */
	.plain {
		margin: 0;
		font: inherit;
		white-space: pre;
		overflow-x: auto;
	}
	.plain code { font-family: inherit; }

	/* Shiki output: keep its token colours but drop its own background/margins so the
	   box styling above shows through and the sizing is inherited. */
	.quick-code :global(pre.shiki) {
		margin: 0;
		font: inherit;
		white-space: pre;
		overflow-x: auto;
		background-color: transparent !important;
	}
	.quick-code :global(pre.shiki code) { font-family: inherit; }
</style>
