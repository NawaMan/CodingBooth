<!--
  Tabs — switch between panels in one slide (the classic "same thing in N ways":
  a snippet in JavaScript / Python / Go, before/after, three variants of a diagram).

  The container half of a Tabs / Tab pair, the same shape as Carousel / CarouselItem
  and Timeline / TimelineItem: authors nest <Tab>s in document order and the Tabs
  coordinates them over context. Each Tab carries its own `label` (and optional
  `icon`); those travel up to the strip Tabs draws, while the content stays in the
  Tab. One panel shows at a time.

    <script>
      import Tabs from '$lib/components/Tabs.svelte';
      import Tab  from '$lib/components/Tab.svelte';
    </script>

    <Tabs>
      <Tab label="JavaScript"><CodeBox …/></Tab>
      <Tab label="Python"><CodeBox …/></Tab>
      <Tab label="Go" icon="🐹"><CodeBox …/></Tab>
    </Tabs>

  It hugs its content in normal flow; wrap it in a <Block> to pin and size the whole
  group on a slide (Block fills its content, so the panel area stretches to the box).

  Keyboard: the strip is the ARIA tablist, so a presenter can Tab into it and use
  ←/→ (or ↑/↓), Home/End to move — selection follows focus, skipping disabled tabs
  and wrapping at the ends. It claims those keys ONLY while a tab is focused, and in
  the bubble phase, so the deck's arrow-key paging resumes the instant focus leaves
  — the same scoped ownership Columns' resize handle takes. Clicking a tab is the
  primary affordance; the widget claims no deck-global key, so it never contends with
  a Steps / Video / Terminal Space build on the same slide.

  Layout: the panels are grid-stacked, so the container is as tall as the TALLEST
  panel and switching a tab never resizes it — the strip stays put. In `text` mode
  (a reading artifact, no canvas, nothing to click) the strip is dropped and every
  panel is shown in flow under its own label.

  Props:
    start      — the initially selected tab (0-based, default 0). Clamped, and
                 nudged off a disabled tab to the first enabled one.
    align      — the strip's alignment: 'start' (default) | 'center' | 'end' |
                 'stretch' (tabs share the width evenly). Unknown → 'start'.
    transition — 'fade' (default, a soft crossfade) or 'none' (instant cut).
    label      — aria-label for the tablist region (default 'Tabs').
    style      — extra inline CSS appended to the group.

  Imperative API (bind:this): goTo(i), next(), prev().
-->
<script lang="ts">
	import { setContext, tick } from 'svelte';
	import { writable } from 'svelte/store';
	import { getMode } from '$lib/presentation';
	import {
		TABS_CONTEXT,
		alignClass,
		firstEnabled,
		initialIndex,
		lastEnabled,
		stepEnabled
	} from '$lib/utils/tabsCore';
	import type { TabMeta } from '$lib/utils/tabsCore';

	/** The initially selected tab (0-based). Clamped; nudged off a disabled tab. */
	export let start = 0;
	/** Strip alignment: 'start' | 'center' | 'end' | 'stretch'. Unknown → 'start'. */
	export let align = 'start';
	/** 'fade' (soft crossfade) or 'none' (instant cut). */
	export let transition: 'fade' | 'none' = 'fade';
	/** aria-label for the tablist region. */
	export let label = 'Tabs';
	/** Extra inline CSS appended to the group. */
	export let style = '';
	/** DOM id for the root element. */
	export let id: string = '';
	/** Extra class(es) for the root element. NOTE: a slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS (global.css / roles.css / a
	    :global(...) block) or a utility class. See AGENTS.md. */
	let klass: string = '';
	export { klass as class };

	// A Text artifact has no canvas and nothing to click: show every panel in flow.
	const textMode = getMode() === 'text';

	// Tabs register their label here, in document order (like Carousel's count, but
	// carrying the strip's button data). The strip's {#each} reads this store AFTER
	// <slot/> in the template, so a server render sees the registrations — the same
	// ordering Carousel's dot row relies on.
	const tabs = writable<TabMeta[]>([]);
	const current = writable(start);

	function register(meta: TabMeta): number {
		let index = 0;
		tabs.update((list) => {
			index = list.length;
			return [...list, meta];
		});
		return index;
	}

	setContext(TABS_CONTEXT, { register, current, textMode });

	// Resolve the initial selection once the tabs have registered: `start` clamped,
	// off a disabled tab. Runs reactively so it also settles if the set changes.
	$: current.set(initialIndex($tabs, start));

	/** Select a tab (ignored if it's disabled or out of range). */
	export function goTo(i: number) {
		if (i < 0 || i >= $tabs.length || $tabs[i]?.disabled) return;
		current.set(i);
	}
	/** Move to the next enabled tab (wraps). */
	export function next() {
		current.set(stepEnabled($tabs, $current, +1));
	}
	/** Move to the previous enabled tab (wraps). */
	export function prev() {
		current.set(stepEnabled($tabs, $current, -1));
	}

	$: alignCls = alignClass(align);
	$: durVar = transition === 'none' ? '--tabs-dur: 0s;' : '';

	// Roving strip: the active tab is the one tab-stop; the rest are reachable only by
	// the arrow keys. buttons[] lets a keyboard move also move focus.
	let buttons: HTMLButtonElement[] = [];

	function select(i: number) {
		if ($tabs[i]?.disabled) return;
		current.set(i);
	}

	async function focusTab(i: number) {
		await tick();
		buttons[i]?.focus();
	}

	function onStripKeydown(e: KeyboardEvent) {
		let target: number;
		if (e.key === 'ArrowRight' || e.key === 'ArrowDown') target = stepEnabled($tabs, $current, +1);
		else if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') target = stepEnabled($tabs, $current, -1);
		else if (e.key === 'Home') target = firstEnabled($tabs);
		else if (e.key === 'End') target = lastEnabled($tabs);
		else return;

		// NavigationBar claims the arrows on `window` in the BUBBLE phase, so stopping
		// the event at a FOCUSED tab is enough to take them back — and only while
		// focused, which is exactly when the presenter means to move between tabs.
		e.preventDefault();
		e.stopPropagation();
		current.set(target);
		focusTab(target);
	}
</script>

<div
	class="tabs align-{alignCls} {klass}"
	class:text={textMode}
	id={id || undefined}
	style="{durVar} {style}"
>
	<!-- Panels come FIRST in the DOM so the strip's {#each $tabs} below reads a
	     populated store during SSR (registration happens as these render). The strip
	     is floated back to the top visually with `order: -1`. -->
	<div class="panels">
		<slot />
	</div>

	{#if !textMode}
		<div class="strip" role="tablist" aria-label={label}>
			{#each $tabs as tab, i (i)}
				<button
					class="tab"
					class:active={$current === i}
					type="button"
					role="tab"
					aria-selected={$current === i}
					disabled={tab.disabled}
					tabindex={$current === i ? 0 : -1}
					bind:this={buttons[i]}
					on:click={() => select(i)}
					on:keydown={onStripKeydown}
				>
					{#if tab.icon}<span class="tab-icon">{tab.icon}</span>{/if}<span class="tab-label"
						>{tab.label || `Tab ${i + 1}`}</span
					>
				</button>
			{/each}
		</div>
	{/if}
</div>

<style>
	.tabs {
		display: flex;
		flex-direction: column;
		box-sizing: border-box;
		min-width: 0;
	}

	/* The strip sits above the panels visually, though it follows them in the DOM (so
	   SSR can read the registered tabs). It carries the baseline rule the tabs sit on. */
	.strip {
		order: -1;
		display: flex;
		flex-wrap: wrap;
		gap: 0.2em;
		border-bottom: 2px solid color-mix(in srgb, var(--tabs-rule, #c0f1ff) 22%, transparent);
		margin-bottom: 1em;
	}
	.align-center .strip {
		justify-content: center;
	}
	.align-end .strip {
		justify-content: flex-end;
	}
	.align-stretch .tab {
		flex: 1 1 0;
	}

	.tab {
		position: relative;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		gap: 0.4em;
		font: inherit;
		font-weight: 600;
		line-height: 1.2;
		color: var(--tabs-fg, #c0f1ff);
		background: none;
		border: 0;
		padding: 0.5em 1.1em;
		margin-bottom: -2px; /* overlap the strip's rule so the indicator meets it */
		border-radius: 8px 8px 0 0;
		cursor: pointer;
		/* The active indicator: an accent underline drawn as a bottom border that only
		   the active tab reveals, so the tab's colour need not be known to the rule. */
		border-bottom: 2px solid transparent;
		opacity: 0.6;
		transition: opacity 0.15s ease, color 0.15s ease, background-color 0.15s ease;
	}
	.tab:hover:not(:disabled):not(.active) {
		opacity: 0.85;
		background: color-mix(in srgb, var(--tabs-hover-bg, #c0f1ff) 8%, transparent);
	}
	.tab.active {
		opacity: 1;
		color: var(--tabs-active-fg, #c0f1ff);
		border-bottom-color: var(--tabs-indicator, #2980b9);
	}
	.tab:disabled {
		opacity: 0.3;
		cursor: default;
	}
	.tab:focus {
		outline: none;
	}
	.tab:focus-visible {
		outline: 2px solid color-mix(in srgb, var(--tabs-indicator, #2980b9) 55%, transparent);
		outline-offset: 2px;
	}
	.tab-icon {
		line-height: 1;
	}

	/* The panel area: one grid cell every panel stacks into, so the box is as tall as
	   the tallest panel and a switch never jumps it (see Tab.svelte). */
	.panels {
		display: grid;
		min-width: 0;
	}
	/* Text mode: no strip, panels flow normally — drop the grid stack. */
	.tabs.text .panels {
		display: block;
	}
</style>
