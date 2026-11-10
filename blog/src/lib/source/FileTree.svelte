<!--
  The EDIT window's file tree: every editable file (src/routes + src/lib), folders
  collapsed until opened, with a filter box that swaps the tree for a flat list of
  matching paths. Opening the active file's folders follows the active tab, so the
  file being edited is always findable. Logic in fileTreeCore.ts.
-->
<script lang="ts">
	import { createEventDispatcher } from 'svelte';
	import { ancestorsOf, buildTree, filterFiles, visibleRows } from './fileTreeCore';

	export let files: string[] = [];
	export let active: string | null = null;

	const dispatch = createEventDispatcher<{ open: { file: string } }>();

	let query = '';
	let expanded = new Set<string>(['src', 'src/routes', 'src/lib']);
	let filterInput: HTMLInputElement;

	$: tree = buildTree(files);
	$: rows = visibleRows(tree, expanded);
	$: matches = filterFiles(files, query);
	$: revealActive(active);

	function revealActive(file: string | null) {
		if (!file) return;
		const missing = ancestorsOf(file).filter((a) => !expanded.has(a));
		if (missing.length) expanded = new Set([...expanded, ...missing]);
	}

	function toggle(path: string) {
		const next = new Set(expanded);
		if (next.has(path)) next.delete(path);
		else next.add(path);
		expanded = next;
	}

	/** Esc in a non-empty filter clears it instead of closing the window. */
	export function clearFilterIfFocused(): boolean {
		if (document.activeElement !== filterInput || !query) return false;
		query = '';
		return true;
	}
</script>

<nav class="tree" aria-label="Project files">
	<input
		bind:this={filterInput}
		bind:value={query}
		class="filter"
		type="search"
		placeholder="Filter files…"
		spellcheck="false"
	/>
	<ul class="rows">
		{#if query.trim()}
			{#each matches as file (file)}
				<li>
					<button
						type="button"
						class="row file"
						class:active={file === active}
						title={file}
						on:click={() => dispatch('open', { file })}>{file.replace(/^src\//, '')}</button
					>
				</li>
			{:else}
				<li class="none">No match.</li>
			{/each}
		{:else}
			{#each rows as { node, depth } (node.path + (node.dir ? '/' : ''))}
				<li>
					<button
						type="button"
						class="row"
						class:dir={node.dir}
						class:file={!node.dir}
						class:active={node.path === active}
						style="padding-left: {0.6 + depth * 0.9 + (node.dir ? 0 : 1)}em"
						title={node.path}
						aria-expanded={node.dir ? expanded.has(node.path) : undefined}
						on:click={() => (node.dir ? toggle(node.path) : dispatch('open', { file: node.path }))}
						>{#if node.dir}<span class="caret">{expanded.has(node.path) ? '▾' : '▸'}</span
							>{/if}{node.name}</button
					>
				</li>
			{/each}
		{/if}
	</ul>
</nav>

<style>
	.tree {
		display: flex;
		flex-direction: column;
		min-height: 0;
		height: 100%;
		background: #1b1b1c;
		border-right: 1px solid #333;
		font-size: 12.5px;
	}
	.filter {
		margin: 0.5em;
		padding: 0.35em 0.6em;
		border: 1px solid #444;
		border-radius: 4px;
		background: #252526;
		color: #ddd;
		font: inherit;
	}
	.rows {
		flex: 1 1 auto;
		min-height: 0;
		overflow: auto;
		margin: 0;
		padding: 0 0 1em;
		list-style: none;
	}
	.row {
		display: block;
		width: 100%;
		padding: 0.18em 0.6em;
		border: 0;
		background: none;
		color: #c8c8c8;
		font: inherit;
		text-align: left;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
		cursor: pointer;
	}
	.row:hover {
		background: rgba(255, 255, 255, 0.06);
	}
	.row.dir {
		color: #9fc4d6;
	}
	.row.active {
		background: rgba(240, 163, 62, 0.18);
		color: #fff;
	}
	.caret {
		display: inline-block;
		width: 1em;
		opacity: 0.7;
	}
	.none {
		padding: 0.4em 0.9em;
		opacity: 0.6;
	}
</style>
