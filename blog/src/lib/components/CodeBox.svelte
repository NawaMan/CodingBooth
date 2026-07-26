<script lang="ts">
	// Code in a titled floating Box. Default read-only (Monaco).
	// Optional title-bar actions:
	//   - `edit`  — opens the unscaled source-edit window (ViewSource)
	//   - `save`  — legacy in-panel SAVE flash (usually unused; write-back lives in the popup)
	import { createEventDispatcher } from 'svelte';
	import Box  from '$lib/components/Box.svelte';
	import Code from '$lib/components/Code.svelte';

	export let code:          string;
	export let language:      string = 'java';
	export let title:         string = '';
	export let expanded:      boolean = false;
	export let revealedLines: Array<number> = [1];
	export let fontSize:      number = 20;
	/** When true (default), Monaco cannot be typed into. */
	export let readOnly:      boolean = true;
	/** Show an EDIT control in the title bar (opens the unscaled editor). */
	export let edit:          boolean = false;
	/** Show a SAVE control in the title bar. */
	export let save:          boolean = false;
	/** Transient verdict on the SAVE button (SAVE / SAVED / NONE / …). */
	export let saveLabel:     string = 'SAVE';
	/** Refusal look + tip (NOT ALLOWED, or a partial write on ADJUST). */
	export let saveRefused:   boolean = false;
	/** Tooltip under the flash when refused. */
	export let saveTip:       string = '';

	/** Inline style for the root element, applied last so it wins. */
	export let style: string = '';
	/** DOM id for the root element. */
	export let id: string = '';
	/** Extra class(es) for the root element. NOTE: a slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS (global.css / roles.css / a
	    :global(...) block) or a utility class. See AGENTS.md. */
	let klass: string = '';
	export { klass as class };

	const dispatch = createEventDispatcher<{ save: void; edit: void }>();

	// The box is 975px tall; the title bar (when present) takes 60px.
	$: hasActions = edit || save;
	$: editorHeight = title || hasActions ? '915px' : '975px';
	$: showTitle = !!(title || hasActions);

	// Bound so getValue / isDirty forward to Monaco (or the code prop before mount),
	// and so Box's outside-click check can recognize a click on the portaled panel.
	let codeRef:
		| {
				getValue: () => string;
				isDirty: () => boolean;
				markClean: () => void;
				containsPortaled: (target: EventTarget | null) => boolean;
		  }
		| undefined;

	/** Current buffer from the editor. */
	export function getValue(): string {
		return codeRef?.getValue() ?? code;
	}

	export function isDirty(): boolean {
		return codeRef?.isDirty() ?? false;
	}

	export function markClean(): void {
		codeRef?.markClean();
	}

	function onEditClick() {
		dispatch('edit');
	}

	function onSaveClick() {
		dispatch('save');
	}
</script>

<Box
	{style}
	{id}
	class={klass}
	bind:expanded={expanded}
	width={1500}
	height={975}
	containsExternal={(t) => codeRef?.containsPortaled(t) ?? false}
>
	{#if showTitle}
		<div class="code-title">
			<span class="code-title-text">{title}</span>
			<span class="code-title-actions">
				{#if edit}
					<button
						type="button"
						class="code-edit"
						aria-label="Edit source in a separate window"
						title="EDIT — open this file in an unscaled editor window"
						on:click|stopPropagation={onEditClick}
					>EDIT</button>
				{/if}
				{#if save}
					<span class="save-btn" class:refused={saveRefused}>
						<button
							type="button"
							class="code-save"
							aria-label="Save source to file"
							title="SAVE — write this buffer back to the source file"
							on:click|stopPropagation={onSaveClick}
						>SAVE</button>
						{#if saveLabel !== 'SAVE' || saveRefused}
							<span class="save-pop">
								{#if saveLabel !== 'SAVE'}
									<span class="save-flash">{saveLabel}</span>
								{/if}
								{#if saveRefused}
									<span class="save-tip" role="status">{saveTip}</span>
								{/if}
							</span>
						{/if}
					</span>
				{/if}
			</span>
		</div>
	{/if}
	<Code
		bind:this={codeRef}
		{code}
		{language}
		revealLines={revealedLines}
		width="1500px"
		height={editorHeight}
		{fontSize}
		{readOnly}
		{expanded}
	/>
</Box>

<style>
	.code-title {
		height: 60px;
		box-sizing: border-box;
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 0.8em;
		padding: 0 0.8em;
		font-family: 'Fira Code', monospace;
		font-weight: bold;
		color: var(--code-title-fg, #FFFFFF);
		background: var(--code-title-bg, #1E1E1E);
		border-bottom: 1.5px solid var(--code-title-border, #333333);
	}
	.code-title-text {
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.code-title-actions {
		flex: 0 0 auto;
		display: flex;
		align-items: center;
		gap: 0.45em;
	}

	.code-edit,
	.code-save {
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
	.code-edit:hover,
	.code-save:hover {
		background: rgba(255, 255, 255, 0.12);
	}

	.save-btn {
		position: relative;
		flex: 0 0 auto;
	}
	.save-pop {
		position: absolute;
		top: calc(100% + 6px);
		right: 0;
		z-index: 10;
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		gap: 4px;
		pointer-events: none;
	}
	.save-flash {
		white-space: nowrap;
		padding: 0.15em 0.6em;
		border-radius: 6px;
		font-size: 0.72em;
		font-weight: bold;
		background: var(--tooltip-bg, #000000);
		color: var(--annot-toggle-fg, #F0A33E);
		border: 1px solid var(--annot-bar-edge, rgba(255, 255, 255, 0.2));
	}
	.save-btn.refused .save-flash {
		color: var(--ctrl-forbidden-fg, #E5484D);
		border-color: var(--ctrl-forbidden-fg, #E5484D);
	}
	.save-tip {
		max-width: 22em;
		text-align: right;
		padding: 0.3em 0.7em;
		border-radius: 6px;
		font-size: 0.68em;
		font-weight: bold;
		background: var(--tooltip-bg, #000000);
		color: var(--tooltip-fg, #FFFFFF);
		border: 1px solid var(--ctrl-forbidden-fg, #E5484D);
	}
</style>
