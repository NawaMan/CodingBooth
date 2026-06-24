<!--
  SizeMode — the display-mode control (top-right chrome).

  A TOC-style dropdown that switches between FITTED (fit to window) and SCALED
  (an exact zoom factor). The menu offers the same factor through two lenses —
  a SCALE % group and a RESOLUTION group — plus a custom %. SlideDeck mounts this
  in its screen-fixed overlay, so it stays reachable while a SCALED slide is
  panned/zoomed. Reads/writes the displayMode + displayFactor stores.
-->
<script lang="ts">
	import CtrlBtn from './CtrlBtn.svelte';
	import { displayMode, displayFactor, clampFactor, MIN_FACTOR, MAX_FACTOR } from '$lib/stores/displayMode';
	import { browser } from '$app/environment';
	import { onMount, onDestroy } from 'svelte';

	/** This deck's canvas, so resolutions/dimensions are computed correctly
	    (a portrait deck reads its own sizes; the friendly names assume 1920x1080). */
	export let width  = 1920;
	export let height = 1080;

	let open = false;
	let rootRef: HTMLElement;
	let customPct = '';

	// Scale presets (as factors). Dimensions are always computed from THIS canvas;
	// the friendly name shows only when it matches the standard 1920x1080 canvas.
	const SCALE_PRESETS = [2, 1.5, 1.25, 1, 0.75, 0.5, 0.25];
	// Well-known 16:9 output resolutions, expressed as factors of 1920x1080.
	const RES_PRESETS = [
		{ factor: 1600 / 1920, name: 'HD+'  },
		{ factor: 1280 / 1920, name: '720p' },
		{ factor:  960 / 1920, name: 'qHD'  },
		{ factor:  854 / 1920, name: '480p' },
		{ factor:  640 / 1920, name: 'nHD'  },
	];
	const isStdLandscape = width === 1920 && height === 1080;

	const pct = (f: number) => `${Math.round(f * 100)}%`;
	const dim = (f: number) => `${Math.round(width * f)}×${Math.round(height * f)}`;
	const near = (a: number, b: number) => Math.abs(a - b) < 0.005;
	const knownName = (f: number) => (near(f, 2) ? '4K' : near(f, 1) ? '1:1' : '');

	$: isFitted = $displayMode === 'FITTED';
	$: factor   = $displayFactor;
	$: label    = isFitted ? 'FITTED' : pct(factor);

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

	function onKeydown(e: KeyboardEvent) {
		if (e.key === 'Escape') open = false;
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
		if (browser) {
			window.removeEventListener('keydown', onKeydown);
			document.removeEventListener('click', onClickOutside);
		}
	});
</script>

<div class="mode no-print" class:expanded={open} bind:this={rootRef}>
	<CtrlBtn chrome text={label} hoverText={`Display: ${label}`} on:click={() => (open = !open)} isSelected={open} />

	{#if open}
	<div class="menu">
		<button type="button" class="row" class:current={isFitted} on:click={chooseFitted}>
			<span class="k">FITTED</span><span class="v">fit to window</span>
		</button>

		<div class="sep">SCALE</div>
		{#each SCALE_PRESETS as f}
			<button type="button" class="row" class:current={!isFitted && near(factor, f)} on:click={() => chooseFactor(f)}>
				<span class="k">{pct(f)}</span>
				<span class="v">{dim(f)}{#if isStdLandscape && knownName(f)} · {knownName(f)}{/if}</span>
			</button>
		{/each}

		{#if isStdLandscape}
		<div class="sep">RESOLUTION</div>
		{#each RES_PRESETS as r}
			<button type="button" class="row" class:current={!isFitted && near(factor, r.factor)} on:click={() => chooseFactor(r.factor)}>
				<span class="k">{dim(r.factor)}</span><span class="v">{pct(r.factor)} · {r.name}</span>
			</button>
		{/each}
		{/if}

		<div class="sep">CUSTOM</div>
		<form class="row custom" on:submit|preventDefault={applyCustom}>
			<input
				type="number"
				min={Math.round(MIN_FACTOR * 100)}
				max={Math.round(MAX_FACTOR * 100)}
				step="1"
				placeholder="%"
				bind:value={customPct}
			/>
			<button type="submit">Set</button>
		</form>
	</div>
	{/if}
</div>

<style>
	.mode {
		/* functional — anchored to the screen-fixed overlay's top-right, inset a
		   little from the very edge so the button isn't jammed under the browser UI. */
		position: absolute;
		/* Anchored by SlideDeck to the frame's top-right corner (clamped to the
		   viewport); see --ctrl-top/--ctrl-right there. Falls back to a fixed inset. */
		top: var(--ctrl-top, 12px);
		right: var(--ctrl-right, 16px);
		margin-right: 0;
	}

	.menu {
		position: absolute;
		top: 100%;
		right: 0;
		min-width: 12em;
		max-height: 80vh;
		overflow-y: auto;
		border: 1.5px solid var(--toc-border, #CCCCCC);
		border-radius: 3px;
		background-color: var(--toc-bg, #EEEEEE);
		color: var(--toc-fg, #111111);
		font-size: 0.7em;
	}
	.menu .sep {
		padding: 0.3em 0.6em 0.1em;
		font-weight: bold;
		opacity: 0.55;
		letter-spacing: 0.05em;
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
	.menu .row:hover {
		background-color: var(--toc-row-hover-bg, #DDDDDD);
	}
	.menu .row.current {
		background-color: var(--ctrl-selected-bg, #00B356);
		color: var(--on-accent, #FFFFFF);
	}
	.menu .row .v {
		opacity: 0.7;
	}
	.menu .row.current .v {
		opacity: 0.9;
	}
	.menu .custom {
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
