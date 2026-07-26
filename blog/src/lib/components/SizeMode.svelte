<!--
  SizeMode — the display-mode (zoom) control.

  A TOC-style dropdown that switches between FITTED (fit to window) and SCALED
  (an exact zoom factor). The menu offers the same factor through two lenses —
  a SCALE % group and a RESOLUTION group — plus a custom %. It renders two ways:
  standalone it pins to the window's top-right corner; with `inline` it folds into
  <SlideToolbar>'s top bar as the DISPLAY segment. Either way it stays reachable while
  a SCALED slide is panned/zoomed. Reads/writes the displayMode + displayFactor stores.

  Keyboard: Alt+. then z (or a click) opens the menu; ↑/↓ (and Home/End) walk the
  preset rows; Enter activates the focused row; **c** jumps to the CUSTOM % field;
  Esc closes. The z mnemonic goes through `displayMenuRequest` the same way t
  opens the TOC.
-->
<script lang="ts">
	import CtrlBtn from './CtrlBtn.svelte';
	import { displayMode, displayFactor, clampFactor, MIN_FACTOR, MAX_FACTOR } from '$lib/stores/displayMode';
	import { displayMenuRequest } from '$lib/stores/chromeArm';
	import { isChromeTypingTarget } from '$lib/chrome/chromeArmCore';
	import {
		SCALE_PRESETS,
		RES_PRESETS,
		sizeMenuChoices,
		currentChoiceIndex,
		stepChoiceIndex,
		nearFactor,
		type SizeMenuChoice
	} from '$lib/chrome/sizeModeCore';
	import { browser } from '$app/environment';
	import { onMount, onDestroy, tick } from 'svelte';

	/** This deck's canvas, so resolutions/dimensions are computed correctly
	    (a portrait deck reads its own sizes; the friendly names assume 1920x1080). */
	export let width  = 1920;
	export let height = 1080;
	/** Sit in a flex row (folded into SlideToolbar) rather than pinning to the window's
	    top-right corner. The menu still drops beneath the control either way. */
	export let inline = false;

	let open = false;
	let rootRef: HTMLElement;
	let menuRef: HTMLElement | undefined;
	let customInput: HTMLInputElement | undefined;
	let customPct = '';
	/** Index into `choices` for the keyboard focus ring. */
	let focusIdx = 0;

	const isStdLandscape = width === 1920 && height === 1080;
	$: choices = sizeMenuChoices(isStdLandscape);

	const pct = (f: number) => `${Math.round(f * 100)}%`;
	const dim = (f: number) => `${Math.round(width * f)}×${Math.round(height * f)}`;
	const knownName = (f: number) => (nearFactor(f, 2) ? '4K' : nearFactor(f, 1) ? '1:1' : '');

	$: isFitted = $displayMode === 'FITTED';
	$: factor   = $displayFactor;
	$: label    = isFitted ? 'FITTED' : pct(factor);
	// Inline tool-bar: Z (zoom) is not in "FITTED" / "100%", so keep a trailing chip —
	// "FITTED (Z)" / "100% (Z)" — unlike PRESENT/ANNOTATE/ADJUST which underline in-word.
	// hoverText must match text so CtrlBtn's hover swap does not drop the key chip.
	$: barLabel = inline ? `${label} (Z)` : label;

	function chooseFitted() {
		displayMode.set('FITTED');
		open = false;
	}
	function chooseFactor(f: number) {
		displayFactor.set(clampFactor(f));
		displayMode.set('SCALED');
		open = false;
	}
	function applyCustom() {
		const v = parseFloat(customPct);
		if (Number.isFinite(v) && v > 0) chooseFactor(v / 100);
	}
	function activate(c: SizeMenuChoice) {
		if (c.kind === 'fitted') chooseFitted();
		else chooseFactor(c.factor);
	}

	function focusRow(i: number) {
		focusIdx = stepChoiceIndex(i, 0, choices.length);
		const id = choices[focusIdx]?.id;
		if (!id || !menuRef) return;
		const el = menuRef.querySelector<HTMLElement>(`[data-choice="${id}"]`);
		el?.focus();
		// jsdom has no layout / scrollIntoView — guard so tests don't reject.
		el?.scrollIntoView?.({ block: 'nearest' });
	}

	/** Jump to the CUSTOM % box (menu mnemonic **c**). Select existing text for overwrite. */
	function focusCustom() {
		if (!customInput) return;
		customInput.focus();
		customInput.select?.();
		customInput.scrollIntoView?.({ block: 'nearest' });
	}

	async function openMenu(next: boolean) {
		open = next;
		if (!next) return;
		focusIdx = currentChoiceIndex(choices, isFitted, factor);
		// Two ticks: first paints `{#if open}`, second binds `menuRef` before we focus.
		await tick();
		await tick();
		focusRow(focusIdx);
	}

	// Alt+. then z — chrome arm asks us to toggle the menu (local open state).
	const unsubDisplayReq = displayMenuRequest.subscribe((n) => {
		if (n > 0) openMenu(!open);
	});

	function onKeydown(e: KeyboardEvent) {
		if (!open) return;

		// Inside the custom % field, leave arrows/digits to the input; Esc still closes.
		if (isChromeTypingTarget(e.target)) {
			if (e.key === 'Escape') {
				e.preventDefault();
				open = false;
			}
			return;
		}

		// **c** → CUSTOM % field (no modifiers; browser chords win).
		if (
			!e.ctrlKey &&
			!e.metaKey &&
			!e.altKey &&
			(e.key === 'c' || e.key === 'C' || e.code === 'KeyC')
		) {
			e.preventDefault();
			focusCustom();
			return;
		}

		switch (e.key) {
			case 'Escape':
				e.preventDefault();
				open = false;
				return;
			case 'ArrowDown':
				e.preventDefault();
				focusRow(stepChoiceIndex(focusIdx, 1, choices.length));
				return;
			case 'ArrowUp':
				e.preventDefault();
				focusRow(stepChoiceIndex(focusIdx, -1, choices.length));
				return;
			case 'Home':
				e.preventDefault();
				focusRow(0);
				return;
			case 'End':
				e.preventDefault();
				focusRow(choices.length - 1);
				return;
			default:
				return;
		}
	}
	function onClickOutside(e: MouseEvent) {
		if (rootRef && !rootRef.contains(e.target as Node)) open = false;
	}
	onMount(() => {
		if (browser) {
			window.addEventListener('keydown', onKeydown);
			document.addEventListener('click', onClickOutside);
		}
	});
	onDestroy(() => {
		unsubDisplayReq();
		if (browser) {
			window.removeEventListener('keydown', onKeydown);
			document.removeEventListener('click', onClickOutside);
		}
	});
</script>

<div class="mode gp-chrome no-print" class:expanded={open} class:inline bind:this={rootRef}>
	<!-- The ADJUST toggle used to live here; it moved into SlideDeck's content layer
	     so slide blocks can render on top of it (see SlideDeck `.layout-ctrl`). -->
	<CtrlBtn
		chrome
		text={barLabel}
		hoverText={barLabel}
		on:click={() => openMenu(!open)}
		isSelected={open}
	/>

	{#if open}
	<div class="menu" role="menu" aria-label="Display zoom" bind:this={menuRef}>
		<button
			type="button"
			class="row"
			class:current={isFitted}
			role="menuitem"
			data-choice="fitted"
			tabindex="-1"
			on:click={chooseFitted}
		>
			<span class="k">FITTED</span><span class="v">fit to window</span>
		</button>

		<div class="sep">SCALE</div>
		{#each SCALE_PRESETS as f}
			<button
				type="button"
				class="row"
				class:current={!isFitted && nearFactor(factor, f)}
				role="menuitem"
				data-choice={`s-${f}`}
				tabindex="-1"
				on:click={() => chooseFactor(f)}
			>
				<span class="k">{pct(f)}</span>
				<span class="v">{dim(f)}{#if isStdLandscape && knownName(f)} · {knownName(f)}{/if}</span>
			</button>
		{/each}

		{#if isStdLandscape}
		<div class="sep">RESOLUTION</div>
		{#each RES_PRESETS as r}
			<button
				type="button"
				class="row"
				class:current={!isFitted && nearFactor(factor, r.factor)}
				role="menuitem"
				data-choice={`r-${r.name}`}
				tabindex="-1"
				on:click={() => chooseFactor(r.factor)}
			>
				<span class="k">{dim(r.factor)}</span><span class="v">{pct(r.factor)} · {r.name}</span>
			</button>
		{/each}
		{/if}

		<!-- C is the jump key into the % field while the menu is open. -->
		<div class="sep"><span class="tool-mn">C</span>USTOM</div>
		<form class="row custom" on:submit|preventDefault={applyCustom}>
			<input
				type="number"
				min={Math.round(MIN_FACTOR * 100)}
				max={Math.round(MAX_FACTOR * 100)}
				step="1"
				placeholder="%"
				aria-label="Custom zoom percent"
				bind:this={customInput}
				bind:value={customPct}
			/>
			<button type="submit">Set</button>
		</form>
	</div>
	{/if}
</div>

<style>
	.mode {
		/* DISPLAY is a WINDOW control: it lives in the screen-fixed overlay and pins to
		   the VIEWPORT's top-right corner, a fixed inset from the window edge, so it is
		   always in reach however the slide is scaled or panned. (It used to anchor to
		   the slide FRAME's corner via --ctrl-top/--ctrl-right; SlideDeck no longer sets
		   those, so a simple fixed inset is the whole story now.) */
		position: absolute;
		top: 14px;
		right: 16px;
		margin-right: 0;
		/* Sized independently of the slide's fit transform (it's not on the slide), and
		   a touch larger than the in-slide chrome so this always-present control reads
		   clearly. 1em is the overlay's inherited --base-font. */
		font-size: 1.2em;
	}

	/* Folded into SlideToolbar: drop the fixed corner inset and join the flex row instead.
	   position:relative (not static) so the dropdown `.menu` still anchors to THIS control
	   rather than to the toolbar's right edge, and font-size:inherit so it matches the bar. */
	.mode.inline {
		position: relative;
		top: auto;
		right: auto;
		margin-right: 0;
		font-size: inherit;
		display: flex;
		align-items: center;
	}

	/* Dress DISPLAY like the bar's word toggles when folded in — CtrlBtn's default `chrome`
	   look is grey and recessed, but here it sits among PRESENT / ANNOTATE / ADJUST and must
	   read as one of them: amber text, transparent, muted at rest, a filled amber pill while
	   its menu is open (matching `.annot-tab.on`). :global reaches CtrlBtn's own <button>; the
	   `.mode.inline` prefix keeps it from touching the corner (standalone) DISPLAY. */
	.mode.inline :global(button.chrome) {
		font-size: inherit;
		font-weight: bold;
		letter-spacing: 0.04em;
		padding: 0.25em 0.7em;
		margin: 0.2em 0.1em;
		border-radius: 999px;
		background: transparent;
		color: var(--annot-toggle-fg, #F0A33E);
		opacity: 0.62;
		transition: opacity 120ms ease, background 120ms ease;
	}
	.mode.inline :global(button.chrome:hover:not(:disabled)) {
		opacity: 1;
		color: var(--annot-toggle-fg, #F0A33E);
		background: var(--annot-bar-hover, rgba(255, 255, 255, 0.1));
		border-color: transparent;
	}
	.mode.inline :global(button.chrome.selected) {
		opacity: 1;
		background: var(--annot-pen, #F0A33E);
		color: var(--annot-bar-on-fg, #1A1206);
		border-color: transparent;
	}

	.menu {
		position: absolute;
		top: 100%;
		right: 0;
		min-width: 16.8em;   /* ~40% wider than the former 12em, so the two columns breathe */
		max-height: 80vh;
		overflow-y: auto;
		border: 1.5px solid var(--toc-border, #CCCCCC);
		border-radius: 3px;
		background-color: var(--toc-bg, #EEEEEE);
		color: var(--toc-fg, #111111);
		font-size: 0.7em;
		z-index: 2;
	}
	.menu .sep {
		padding: 0.3em 0.6em 0.1em;
		font-weight: bold;
		opacity: 0.55;
		letter-spacing: 0.05em;
	}
	/* Same underline cue as the tool bar / ☰ mnemonics (CUSTOM ← c). */
	.menu .sep :global(.tool-mn) {
		text-decoration: underline;
		text-underline-offset: 0.18em;
		text-decoration-thickness: 1px;
	}
	.menu .row {
		display: flex;
		justify-content: space-between;
		gap: 1.2em;
		width: 100%;
		padding: 0.25em 0.6em;
		border: 0;
		background: transparent;
		color: inherit;
		font: inherit;
		text-align: left;
		cursor: pointer;
	}
	.menu .row:hover,
	.menu .row:focus-visible {
		background-color: var(--toc-row-hover-bg, #DDDDDD);
		outline: none;
	}
	.menu .row.current {
		background-color: var(--ctrl-selected-bg, #00B356);
		color: var(--on-accent, #FFFFFF);
	}
	.menu .row.current:hover,
	.menu .row.current:focus-visible {
		/* Keep the selected row green under keyboard focus; brighten slightly. */
		filter: brightness(1.06);
	}
	.menu .row .v {
		opacity: 0.7;
	}
	.menu .row.current .v {
		opacity: 0.9;
	}
	.menu .custom {
		/* The other rows use space-between (label left, value right); the CUSTOM row
		   is an input + Set button, so keep them grouped at the left instead — else
		   Set is pushed to the menu's right edge and clipped. */
		justify-content: flex-start;
		gap: 0.4em;
	}
	.menu .custom input {
		width: 4em;
		font: inherit;
	}
	.menu .custom button {
		cursor: pointer;
		font: inherit;
	}
</style>
