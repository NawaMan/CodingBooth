<!--
  Tab — one panel of a <Tabs>.

  Wrap arbitrary markup (a code block, an image, prose); the panel registers itself
  and its strip label with the parent Tabs over context — in document order — and
  shows only when it is the selected tab. See Tabs.svelte for usage and the full API.

  The `label` (and optional `icon`) travel up to the strip the container draws; the
  content stays here. In `text` mode there is no strip to click, so every panel is
  shown in flow with its label as a small heading (the Steps "text shows all" rule).

  Props:
    label    — the button text in the strip. Falls back to "Tab N" if empty, so a
               tab is never an unlabelled, unclickable blank.
    icon     — a glyph shown before the label (emoji or a character).
    disabled — a tab that can't be selected (greyed in the strip, skipped by the
               keyboard). Its panel never shows.
    style    — extra inline CSS appended to the panel.
-->
<script lang="ts">
	import { getContext } from 'svelte';
	import type { Writable } from 'svelte/store';
	import { TABS_CONTEXT } from '$lib/utils/tabsCore';
	import type { TabMeta } from '$lib/utils/tabsCore';

	type TabsCtx = {
		register: (meta: TabMeta) => number;
		current: Writable<number>;
		textMode: boolean;
	};

	/** The button text in the strip. */
	export let label: string = '';
	/** A glyph shown before the label. */
	export let icon: string = '';
	/** A tab that can't be selected — greyed, keyboard-skipped, panel hidden. */
	export let disabled: boolean = false;
	/** Extra inline CSS appended to the panel. */
	export let style: string = '';
	/** DOM id for the root element. */
	export let id: string = '';
	/** Extra class(es) for the root element. NOTE: a slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS (global.css / roles.css / a
	    :global(...) block) or a utility class. See AGENTS.md. */
	let klass: string = '';
	export { klass as class };

	const ctx = getContext<TabsCtx>(TABS_CONTEXT);

	// Runs during init, so panels get sequential indices matching DOM order — the
	// same order the strip buttons are drawn in. A tab with no label is still a real
	// tab; it borrows a "Tab N" name so its button is never a blank the presenter
	// can't aim at.
	const index = ctx ? ctx.register({ label, icon, disabled }) : 0;
	const resolvedLabel = label || `Tab ${index + 1}`;

	// The current-index store (absent when a Tab is used outside a Tabs). Standalone,
	// or in text mode, a panel simply always shows; otherwise it shows on its turn.
	// `$current` is safe even when `current` is undefined — the same standalone
	// pattern TimelineItem relies on.
	const current = ctx?.current;
	$: active = !ctx || ctx.textMode ? true : $current === index;
</script>

{#if ctx && ctx.textMode}
	<!-- text: in flow, label as a heading, always visible. -->
	<section class="panel text {klass}" id={id || undefined} style={style}>
		{#if resolvedLabel}
			<div class="panel-label">
				{#if icon}<span class="panel-icon">{icon}</span>{/if}{resolvedLabel}
			</div>
		{/if}
		<slot />
	</section>
{:else}
	<!-- presentation: panels are grid-stacked (the container is as tall as the
	     tallest, so switching never jumps the strip); inactive ones keep their box
	     (visibility, so they still size the stack) but are hidden and inert. The
	     tabpanel is a region, not a focus stop — the tabs are the interactive parts. -->
	<!-- svelte-ignore a11y_no_noninteractive_element_to_interactive_role -->
	<section
		class="panel {klass}"
		class:active
		id={id || undefined}
		role="tabpanel"
		aria-label={resolvedLabel}
		aria-hidden={!active}
		inert={!active || undefined}
		style={style}
	>
		<slot />
	</section>
{/if}

<style>
	.panel {
		box-sizing: border-box;
		min-width: 0;
	}

	/* Presentation: every panel shares one grid cell, so the stack is as tall as the
	   tallest panel and the active one never resizes the container as tabs switch.
	   visibility (not display) keeps an inactive panel's box, which is what holds that
	   height steady. The grid itself is declared on the container (see Tabs). */
	.panel:not(.text) {
		grid-area: 1 / 1;
		opacity: 0;
		visibility: hidden;
		pointer-events: none;
		transition: opacity var(--tabs-dur, 0.18s) ease;
	}
	.panel.active {
		opacity: 1;
		visibility: visible;
		pointer-events: auto;
	}

	/* Text: normal flow, all panels shown, each under its label. */
	.panel.text + :global(.panel.text) {
		margin-top: 1.4em;
	}
	.panel-label {
		font-size: 0.82em;
		font-weight: 700;
		letter-spacing: 0.03em;
		text-transform: uppercase;
		color: var(--tabs-active-fg, #c0f1ff);
		border-bottom: 2px solid color-mix(in srgb, var(--tabs-indicator, #2980b9) 60%, transparent);
		padding-bottom: 0.3em;
		margin-bottom: 0.6em;
	}
	.panel-icon {
		margin-right: 0.4em;
	}

	@media (prefers-reduced-motion: reduce) {
		.panel:not(.text) {
			transition: none;
		}
	}
</style>
