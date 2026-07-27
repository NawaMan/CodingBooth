<!--
  SourceView — the Monaco-free "</> Source" control.

  Use this INSTEAD OF ViewSource on any slide reached by a CLIENT-SIDE navigation:
  a View-Transition deck (setViewTransitions), or an AppendixPage/AppendixLink with
  `transition`. ViewSource pops a Monaco CodeBox, and Monaco's CDN AMD loader does
  not re-initialise across a `goto`, so it renders blank on every slide after the
  first one. (See the project memory "monaco-breaks-on-spa-nav".) Everything else —
  a deck that pages with full loads — can keep using ViewSource.

  Same control, same trigger placement (☰ SOURCE on a presentation; corner button
  on a Text), same Box: only the highlighter differs. Shiki is plain ESM behind a
  shared singleton highlighter ($lib/utils/highlight), so it survives navigation.
  Highlighting is lazy — done the first time the viewer is opened, with the plain
  source showing until (and if) it resolves.

  ☰ → EDIT (and the title-bar EDIT) opens the same unscaled `/_source-edit` popup
  as ViewSource — typing never happens in this scaled panel.

  Each page passes its own source via Vite's ?raw import; the file path shown in the
  title bar is derived from the current route unless `path` overrides it.

    <script>
      import SourceView from '$lib/components/SourceView.svelte';
      import source     from './+page.svelte?raw';
    </script>
    <SourceView {source} />
-->
<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { get } from 'svelte/store';
	import CtrlBtn from '$lib/components/CtrlBtn.svelte';
	import Box     from '$lib/components/Box.svelte';
	import { page } from '$app/stores';
	import { highlightToHtml } from '$lib/utils/highlight';
	import { getMode } from '$lib/presentation';
	import {
		registerPageSource,
		unregisterPageSource,
		pageSourceOpen
	} from '$lib/stores/pageSource';
	import { canSave } from '$lib/stores/adjustMode';
	import { openSourceEditor } from '$lib/stores/sourceEditWindow';

	/** The page source, typically `import source from './+page.svelte?raw'`. */
	export let source: string;
	/** Override the auto-derived path shown in the title bar. */
	export let path: string = '';
	/** Recede into the frame like the other chrome controls. Default on. */
	export let chrome: boolean = true;
	/** Inline style for the root element, applied last so it wins. */
	export let style: string = '';
	/** DOM id for the root element. */
	export let id: string = '';
	/** Extra class(es) for the root element. NOTE: a slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS (global.css / roles.css / a
	    :global(...) block) or a utility class. See AGENTS.md. */
	let klass: string = '';
	export { klass as class };

	// Presentations host the trigger in the tool bar's ☰; Texts keep the corner button.
	const cornerButton = getMode() === 'text';

	let expanded = false;
	let html = '';
	let requested = false;

	$: filePath = path || `src/routes${$page.route.id}/+page.svelte`;

	function openEdit() {
		if (typeof location === 'undefined') return;
		const win = openSourceEditor({
			route: location.pathname,
			path: filePath,
			source,
			language: 'html',
			canSave: get(canSave)
		});
		if (!win) {
			console.warn(
				'[SourceView] popup blocked — allow popups for this origin to edit source in a separate window'
			);
		}
	}

	// Keep the panel and the shared store in step (hamburger opens; Box closes).
	const unsubOpen = pageSourceOpen.subscribe((v) => {
		if (expanded !== v) expanded = v;
	});
	$: if (expanded !== $pageSourceOpen) pageSourceOpen.set(expanded);
	onDestroy(unsubOpen);

	// Highlight lazily the first time the viewer is opened; plain source shows until
	// (and if) it resolves.
	$: if (expanded && !requested) {
		requested = true;
		highlightToHtml(source, 'svelte').then((out) => (html = out)).catch(() => {});
	}

	onMount(() => {
		const owner = Symbol('source-view');
		registerPageSource(owner, openEdit);
		return () => unregisterPageSource(owner);
	});
</script>

<div class="view-source no-print {klass}" class:corner={cornerButton} id={id || undefined} style={style || undefined}>
	{#if cornerButton}
		<CtrlBtn {chrome} text="</> Source" hoverText="View this slide's source" isSelected={expanded} on:click={() => (expanded = true)} />
	{/if}
</div>

<!-- The panel is a SIBLING of the button, so it carries the print marker in its own right; the
     button's `no-print` does not reach it. (ViewSource has the same shape, and there it is
     load-bearing — see the note there.) -->
<Box bind:expanded width={1500} height={975} scrollable class="gp-chrome no-print">
	<div class="src">
		<div class="src-title">
			<span class="src-path">{filePath}</span>
			<button
				type="button"
				class="src-edit"
				aria-label="Edit source in a separate window"
				title="EDIT — open this file in an unscaled editor window"
				on:click|stopPropagation={openEdit}
			>EDIT</button>
		</div>
		{#if html}
			{@html html}
		{:else}
			<pre class="src-code"><code>{source}</code></pre>
		{/if}
	</div>
</Box>

<style>
	/* Bottom-right corner — only used on a Text, where there is no tool-bar ☰.
	   On a presentation the wrapper is a zero-size host for style/id/class. */
	.view-source.corner {
		position: absolute;
		bottom: 0px;
		right: 5px;
	}

	.src { width: 1500px; }
	.src-title {
		position: sticky;
		top: 0;
		z-index: 1;
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 0.8em;
		padding: 0.7em 1.1em;
		font-family: 'Fira Code', monospace;
		font-weight: bold;
		font-size: 18px;
		color: var(--code-title-fg, #FFFFFF);
		background: var(--code-title-bg, #1E1E1E);
		border-bottom: 1.5px solid var(--code-title-border, #333333);
	}
	.src-path {
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.src-edit {
		flex: 0 0 auto;
		appearance: none;
		border: 1px solid var(--code-title-border, #333333);
		border-radius: 6px;
		padding: 0.25em 0.75em;
		font: inherit;
		font-size: 0.85em;
		font-weight: bold;
		letter-spacing: 0.04em;
		cursor: pointer;
		color: var(--annot-toggle-fg, #F0A33E);
		background: rgba(255, 255, 255, 0.06);
	}
	.src-edit:hover {
		background: rgba(255, 255, 255, 0.12);
	}
	.src-code {
		margin: 0;
		padding: 1.1em 1.3em;
		overflow-x: auto;
		font-family: 'Fira Code', monospace;
		font-size: 18px;
		line-height: 1.6;
		color: var(--surface-fg, #C7F5D4);
		white-space: pre;
	}
	.src-code code { font-family: inherit; }

	/* Shiki output: keep token colours, drop its background, match our sizing. */
	.src :global(pre.shiki) {
		margin: 0;
		padding: 1.1em 1.3em;
		overflow-x: auto;
		font-family: 'Fira Code', monospace;
		font-size: 18px;
		line-height: 1.6;
		white-space: pre;
		background-color: transparent !important;
	}
	.src :global(pre.shiki code) { font-family: inherit; }
</style>
