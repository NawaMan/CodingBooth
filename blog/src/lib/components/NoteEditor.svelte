<!--
  NoteEditor — the presenter console's NOTE EDIT panel. PresenterView mounts it
  over the notes panel (the same --gp-* geometry Note.svelte's .note.presenter
  reads), so the speaker edits the note where they read it.

  It edits the SOURCE between the slide's <Note> and </Note> — HTML and Svelte
  as written, `data-highlight` and all — dedented for the textarea and re-indented
  on SAVE by the dev server (note/noteSourceCore via devSavePlugin). Vite then
  reloads the slide in both windows, so the rendered note updates itself.

  Keys: Ctrl/Cmd+S saves, Esc cancels (asking first when there are unsaved
  changes). Every key typed here stops at the panel, so the console's own
  shortcuts (T, C, →, Space …) never fire from inside the editor.
-->
<script lang="ts">
	import { createEventDispatcher, onMount, onDestroy } from 'svelte';
	import { loadNote, saveNote } from '$lib/stores/noteEdit';

	/** The slide being edited — its pathname, e.g. `/slides/intro.html`. */
	export let route: string;
	/** Inline style for the root element, applied last so it wins. */
	export let style: string = '';
	/** DOM id for the root element. */
	export let id: string = '';
	/** Extra class(es) for the root element. */
	let klass: string = '';
	export { klass as class };

	const dispatch = createEventDispatcher<{ close: void; saved: { file?: string } }>();

	let status: 'loading' | 'ready' | 'saving' | 'failed' = 'loading';
	let text = '';
	let original = '';
	let print = '';
	let file = '';
	let error = '';
	let area: HTMLTextAreaElement;

	$: dirty = text !== original;

	onMount(async () => {
		const r = await loadNote(route);
		if (!r.ok) {
			status = 'failed';
			error = r.error ?? 'could not load the note';
			return;
		}
		text = original = r.text ?? '';
		print = r.fingerprint ?? '';
		file = r.file ?? '';
		status = 'ready';
		queueMicrotask(() => area?.focus());
	});

	// Paging away is a full page load: say so before an edit is lost to it.
	function onBeforeUnload(e: BeforeUnloadEvent) {
		if (dirty) e.preventDefault();
	}
	onMount(() => window.addEventListener('beforeunload', onBeforeUnload));
	onDestroy(() => {
		if (typeof window !== 'undefined') window.removeEventListener('beforeunload', onBeforeUnload);
	});

	async function save() {
		if (status !== 'ready') return;
		if (!dirty) {
			dispatch('close');
			return;
		}
		status = 'saving';
		error = '';
		const r = await saveNote(route, text, print);
		if (!r.ok) {
			status = 'ready';
			error = r.error ?? 'save failed';
			return;
		}
		original = text;
		dispatch('saved', { file: r.file });
		dispatch('close');
	}

	function cancel() {
		if (dirty && !confirm('Discard your changes to this note?')) return;
		dispatch('close');
	}

	function onKeydown(e: KeyboardEvent) {
		e.stopPropagation();
		if ((e.ctrlKey || e.metaKey) && !e.altKey && e.key.toLowerCase() === 's') {
			e.preventDefault();
			save();
		} else if (e.key === 'Escape') {
			e.preventDefault();
			cancel();
		}
	}
</script>

<!-- svelte-ignore a11y-no-noninteractive-element-interactions -->
<section
	class="note-editor no-print {klass}"
	id={id || undefined}
	aria-label="Edit speaker note"
	style={style || undefined}
	on:keydown={onKeydown}
>
	<header>
		<span class="title">EDIT NOTE</span>
		{#if file}<span class="file" title={file}>{file}</span>{/if}
		<span class="spacer"></span>
		<button type="button" class="save" on:click={save} disabled={status !== 'ready'} title="Save (Ctrl/Cmd+S)">
			{status === 'saving' ? 'SAVING…' : 'SAVE'}
		</button>
		<button type="button" on:click={cancel} title="Cancel (Esc)">CANCEL</button>
	</header>
	{#if error}<p class="error" role="alert">{error}</p>{/if}
	{#if status === 'loading'}
		<p class="hint">Loading…</p>
	{:else if status !== 'failed'}
		<textarea
			bind:this={area}
			bind:value={text}
			spellcheck="false"
			aria-label="Note source"
			disabled={status === 'saving'}
		></textarea>
		<p class="hint">The HTML between &lt;Note&gt; and &lt;/Note&gt;. One element per line is one checkable line.</p>
	{/if}
</section>

<style>
	.note-editor {
		position: fixed;
		top: var(--gp-inset, 20px);
		left: calc(var(--gp-split, 50vw) + var(--gp-gap, 16px) / 2);
		right: var(--gp-inset, 20px);
		bottom: calc(var(--gp-bar-h, 130px) + var(--gp-inset, 20px));
		z-index: 61; /* over the note panel (60) it replaces */
		display: flex;
		flex-direction: column;
		gap: 8px;
		padding: 14px 16px;
		box-sizing: border-box;
		color: #e6e6e6;
		background: #1f1f1f;
		border: 1.5px solid #f0a33e;
		border-radius: 10px;
		box-shadow: 0 6px 24px rgba(0, 0, 0, 0.35);
		font-family: ui-sans-serif, system-ui, Segoe UI, Helvetica, Arial, sans-serif;
	}
	header {
		display: flex;
		align-items: center;
		gap: 10px;
		min-width: 0;
	}
	.title {
		font-weight: 700;
		letter-spacing: 0.06em;
		color: #f0a33e;
	}
	.file {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-size: 0.85em;
		opacity: 0.6;
	}
	.spacer {
		flex: 1;
	}
	button {
		font: inherit;
		font-weight: 600;
		padding: 4px 14px;
		color: #e6e6e6;
		background: #333;
		border: 1px solid #555;
		border-radius: 6px;
		cursor: pointer;
	}
	button.save {
		color: #1f1f1f;
		background: #f0a33e;
		border-color: #f0a33e;
	}
	button:disabled {
		opacity: 0.5;
		cursor: default;
	}
	textarea {
		flex: 1;
		min-height: 0;
		resize: none;
		padding: 12px;
		color: inherit;
		background: #141414;
		border: 1px solid #444;
		border-radius: 6px;
		font: 1.05rem/1.5 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
		tab-size: 4;
	}
	.error {
		margin: 0;
		padding: 6px 10px;
		color: #ffd2d2;
		background: #5a1d1d;
		border-radius: 6px;
	}
	.hint {
		margin: 0;
		font-size: 0.85em;
		opacity: 0.6;
	}
</style>
