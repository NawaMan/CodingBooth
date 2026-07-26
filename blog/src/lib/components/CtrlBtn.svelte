<script lang="ts">
	import { onMount } from 'svelte';
	import { mnMarkup } from '$lib/chrome/mnemonicCore';

    export let text       = 'Btn';
    export let hoverText  = '';
	export let isSelected = false;
	export let isDisabled = false;
	export let isVisible  = true;
	/* Chrome buttons (nav bar, ToC, mode toggle) set this to recede into the
	   frame. In-page buttons leave it false and get the prominent, eye-catching
	   look by default — so a slide author doesn't have to opt in. */
	export let chrome     = false;
	/** Optional letter to underline in `text` / `hoverText` (chrome keyboard mnemonics). */
	export let mnemonic   = '';

	onMount(() => {
		if (!hoverText) {
			hoverText = text;
		}
	});

	// Contiguous HTML so the letter is not split from the rest of the word in the
	// a11y tree (see mnMarkup). Plain text when no mnemonic.
	$: textHtml = mnemonic ? mnMarkup(text, mnemonic) : '';
	$: hoverHtml = mnemonic ? mnMarkup(hoverText || text, mnemonic) : '';
</script>

<style>
    button {
		/* functional */
		cursor: pointer;

		/* cosmetic */
		/* A <button> ignores the inherited font-size by default, so it skipped the
		   canvas font-size lever and stayed tiny. Opt in so the control tracks its
		   context; 0.85em keeps it chrome-sized (~1.5x its old browser-default size
		   on the 1920x1080 canvas) and scales with any future portrait layout. */
		font-size: 0.85em;
		margin-left: 0.5em;
		text-justify: center;
		text-align: center;
		font-weight: bold;
		/* Keep the label on ONE line — a chrome button squeezed narrow (the tool bar's
		   "FITTED (Z)" chip, a pager's "PREV") must never wrap a key hint under the word. */
		white-space: nowrap;

		/* Default (in-page) look: prominent / eye-catching — a filled accent-blue
		   button with white text, so it reads clearly as a clickable affordance
		   unlike the muted chrome buttons. */
		padding: 0.15em 0.7em;
		background: var(--ctrl-strong-bg, #2980B9);
		color: var(--on-accent, #FFFFFF);
		border: 1.5px solid var(--ctrl-strong-border, #2980B9);
		border-radius: 6px;
	}

	button:hover:not(:disabled) {
		/* Brighten the fill on hover for feedback (applies to both looks). */
		filter: brightness(1.12);
	}

	/* Chrome look: nav bar / ToC / mode toggle — recede into the frame. */
	button.chrome {
		padding-left: 0.5em;
		padding-right: 0.5em;
		padding-top: 0;
		padding-bottom: 0;
		background: var(--ctrl-bg, #181818);
		color: var(--ctrl-fg, #333333);
		border: 0px;
		border-radius: 0;
	}

	button:hover:not(:disabled) {
		/* cosmetic */
		color: var(--on-accent, #FFFFFF);
		background-color: var(--ctrl-hover-bg, #2980B9);
		border-color: var(--ctrl-hover-bg, #2980B9);
	}
	button.selected {
		/* cosmetic */
		color: var(--on-accent, #FFFFFF);
		background-color: var(--ctrl-selected-bg, #00B356);
		border-color: var(--ctrl-selected-bg, #00B356);
	}
	button:active:not(:disabled) {
		/* cosmetic */
		box-shadow: 0 3px var(--ctrl-active-shadow, #0056B3);
		transform: translateY(4.5px);
	}
	button:disabled {
		/* functional */
		color: var(--ctrl-disabled-fg, #222222);
		cursor: default;
	}

	button .hover-text {
		display: none;
	}
	button:hover:not(button.hidden) .hover-text,
	button.selected:not(button.hidden) .hover-text {
		display: inline;
	}
	button:hover    .text,
	button.selected .text {
		display: none;
	}
	button.hidden {
		display: none;
	}
	/* Mnemonic underline — shared look with the ☰ menu's `.tool-mn`. */
	:global(.chrome-mn) {
		text-decoration: underline;
		text-underline-offset: 0.18em;
		text-decoration-thickness: 1px;
	}
</style>

<!-- When a mnemonic splits the label across a span, set aria-label to the full
     word so the accessible name stays "Table of Contents" (not a letter-split
     reading). Visual underline is decorative. -->
<button
	disabled={isDisabled}
	class:chrome={chrome}
	class:selected={isSelected}
	class:hidden={!isVisible}
	aria-label={mnemonic ? text : undefined}
	on:click>
	<span class="text" aria-hidden={mnemonic ? 'true' : undefined}>
		{#if mnemonic}
			{@html textHtml}
		{:else}
			{text}
		{/if}
	</span>
	<span class="hover-text" aria-hidden={mnemonic ? 'true' : undefined}>
		{#if mnemonic}
			{@html hoverHtml}
		{:else}
			{hoverText}
		{/if}
	</span>
</button>
