<!--
  ControlBar — the bottom-centre control bar, the mirror of the top PRESENT tool bar.

  Where <SlideToolbar> gathers the AUTHORING tools (PRESENT / ANNOTATE / ADJUST / DISPLAY),
  this gathers the NAVIGATION controls that used to be scattered inside the scaled slide: the
  Table of Contents (was top-left) and the FIRST/PREV/CONTINUE/NEXT/LAST pager (was re-mounted
  bottom-left by every page template). SlideDeck mounts it in the same viewport-fixed overlay, so
  it sticks to the WINDOW's bottom edge at a constant size no matter how the slide is scaled or
  panned.

  Like the tool bar it is a SHELL: SlideDeck supplies the contents as snippets (`tocItem`,
  `navGroup`) and owns their logic.

  It AUTO-HIDES downward — the exact mirror of the tool bar's upward tuck at the top: tucked so
  only a peek strip shows at the bottom of the window, seating flush on the edge on hover or when
  keyboard focus reaches a control inside (it never floats fully clear of the edge). PIN latches
  it fully out (and the top tool bar with it — one shared preference) until the speaker unpins
  and returns both to auto-hide.

  `browser &&` because these are live controls: prerendering would ship dead chrome and bake it
  into the static HTML of every deck built on a dev machine (matches <SlideToolbar> / <Annotate>).
-->
<script lang="ts">
	import { browser } from '$app/environment';
	import { onMount, type Snippet } from 'svelte';
	import { animBarSlot, hostedAnim } from '$lib/stores/localChrome';
	import { controlBarPinned } from '$lib/stores/chromePin';
	import { chromeArmed } from '$lib/stores/chromeArm';
	import { overviewOpen } from '$lib/stores/overviewOpen';

	interface Props {
		/** The Table of Contents flyout (SlideDeck supplies <TableOfContent bar />). */
		tocItem?: Snippet;
		/** The deck's ONE pager (SlideDeck supplies <NavigationBar deckLevel />). */
		navGroup?: Snippet;
	}

	let { tocItem, navGroup }: Props = $props();

	// The portal target for a deck-level AnimationBar (see stores/localChrome + utils/portal).
	// A plain <AnimationBar> in the live slide moves its `.anim-bar` node in here, so the
	// central animation control rides the bottom bar instead of floating in the canvas.
	let animSlot: HTMLElement | undefined = $state();
	onMount(() => {
		if (animSlot) animBarSlot.set(animSlot);
		return () => animBarSlot.set(null);
	});

	// Reveal the animation segment (its divider + slot) only while a hosted bar has a LIVE
	// animation, so a slide with none shows no dangling divider. The slot element itself is
	// always mounted (the portal needs a stable target); only the divider is gated.
	let hasAnim = $derived($hostedAnim.size > 0);
</script>

{#if browser}
	<div
		class="ctrl-bar no-print"
		class:pinned={$controlBarPinned}
		class:armed={$chromeArmed}
		class:overview-open={$overviewOpen}
		role="group"
		aria-label="Slide controls"
		aria-hidden={$overviewOpen ? 'true' : undefined}
	>
		<!-- PIN — latch THIS bar fully out of its auto-hide tuck. Independent of the top tool
		     bar's pin (see stores/chromePin). Icon-only (pushpin SVG); aria-label + title
		     carry the name. Filled when on. -->
		<button
			type="button"
			class="ctrl-pin"
			class:on={$controlBarPinned}
			aria-pressed={$controlBarPinned}
			aria-label={$controlBarPinned ? 'PIN on' : 'PIN off'}
			title={$controlBarPinned
				? 'PIN — this bar stays visible (click to auto-hide again)'
				: 'PIN — keep this bar visible'}
			onclick={() => controlBarPinned.update((v) => !v)}
		>
			<svg class="pin-icon" viewBox="0 0 24 24" width="1em" height="1em" aria-hidden="true" focusable="false">
				<!-- Classic pushpin (Material-style): head + shaft + needle. currentColor tracks the tab. -->
				<path
					fill="currentColor"
					d="M16 9V4h1c.55 0 1-.45 1-1s-.45-1-1-1H7c-.55 0-1 .45-1 1s.45 1 1 1h1v5c0 1.66-1.34 3-3 3v2h5.97v7l1 1 1-1v-7H19v-2c-1.66 0-3-1.34-3-3z"
				/>
			</svg>
		</button>

		<span class="ctrl-bar-sep" aria-hidden="true"></span>

		<!-- TABLE OF CONTENTS — the searchable slide list, its flyout opening UPWARD out of the bar. -->
		{@render tocItem?.()}

		<span class="ctrl-bar-sep" aria-hidden="true"></span>

		<!-- NAV — the deck's single FIRST / PREV / CONTINUE / NEXT / LAST pager. -->
		{@render navGroup?.()}

		<!-- ANIMATE — a deck-level AnimationBar portals its scrubber in here. The divider is
		     shown only while a hosted bar has a live animation; the slot is always present so
		     the portal has a stable target to land in. -->
		{#if hasAnim}
			<span class="ctrl-bar-sep" aria-hidden="true"></span>
		{/if}
		<div class="ctrl-anim" class:has-anim={hasAnim} bind:this={animSlot}></div>
	</div>
{/if}

<style>
	/* ── The bottom-centre control bar ──────────────────────────────────────────────
	   One horizontal pill, attached to the WINDOW's bottom edge and centred — the mirror of
	   the top tool bar. Its parent (SlideDeck's .overlay) is position:fixed at z-index 50, so
	   the bar stays put over any pan/zoom.

	   THEMING — shared with <SlideToolbar> so the two bars restyle TOGETHER by default, yet can
	   be peeled APART. Each surface reads its own `--ctrl-bar-*` override FIRST, then falls back
	   to the tool bar's `--annot-*` token, then to the hardcoded dark default:
	     • set `--annot-toggle-bg` / `--annot-bar-edge` / `--annot-toggle-fg` / `--annot-bar-hover`
	       → restyles BOTH bars at once;
	     • set `--ctrl-bar-bg` / `--ctrl-bar-edge` / `--ctrl-bar-fg` / `--ctrl-bar-hover`
	       → restyles only THIS bar. */
	.ctrl-bar {
		position: absolute;
		bottom: 0;
		left: 50%;
		/* Auto-hide, like the tool bar's upward tuck: at rest the bar tucks DOWN so a peek strip
		   shows at the window's bottom edge, and hover / focus seats it flush on that edge. Tucked
		   a touch LESS than the tool bar's -72% so a bit more of it shows at rest (~40% peek). */
		transform: translateX(-50%) translateY(85%);
		transition: transform 160ms ease;
		display: flex;
		align-items: center;
		/* Thickness lever: the bar scales from this one font-size, matching <SlideToolbar>. */
		font-size: calc(var(--base-font, 16px) * 0.5);
		padding: 5px 0.2em;
		/* Attached to the window's bottom edge (mirror of the tool bar at the top): full border
		   and rounded corners on top, none on the edge it sits against, shadow cast upward. */
		border: 3px solid var(--ctrl-bar-edge, var(--annot-bar-edge, rgba(255, 255, 255, 0.35)));
		border-bottom: none;
		border-radius: 10px 10px 0 0;
		background: var(--ctrl-bar-bg, var(--annot-toggle-bg, rgba(20, 22, 26, 0.92)));
		box-shadow: 0 -3px 14px rgba(0, 0, 0, 0.4);

		/* Dress the CtrlBtn controls (TOC trigger, pager) like the tool bar's word buttons, from
		   the SAME shared tokens — so theming the tool bar carries here. */
		--ctrl-bg: transparent;
		--ctrl-fg: var(--ctrl-bar-fg, var(--annot-toggle-fg, #f0a33e));
		--ctrl-hover-bg: var(--ctrl-bar-hover, var(--annot-bar-hover, rgba(255, 255, 255, 0.1)));
		--ctrl-selected-bg: var(--ctrl-bar-hover, var(--annot-bar-hover, rgba(255, 255, 255, 0.14)));
		--ctrl-strong-bg: var(--ctrl-bar-fg, var(--annot-toggle-fg, #f0a33e));
		--on-accent: var(--ctrl-bar-fg, var(--annot-toggle-fg, #f0a33e));
	}

	/* Revealed on hover / focus: it rises to sit FLUSH on the bottom edge — attached, never
	   floating fully clear of the window's lip. `.pinned` is the sticky latch (see
	   stores/chromePin): the bar stays fully out until the speaker unpins. `.armed` is the
	   temporary keyboard raise (Alt+.). */
	.ctrl-bar:hover,
	.ctrl-bar:focus-within,
	.ctrl-bar.pinned,
	.ctrl-bar.armed {
		transform: translateX(-50%) translateY(0);
	}
	.ctrl-bar.armed {
		box-shadow:
			0 -3px 14px rgba(0, 0, 0, 0.4),
			0 0 0 2px color-mix(in srgb, var(--ctrl-bar-fg, var(--annot-toggle-fg, #F0A33E)) 55%, transparent);
	}

	/* OVERVIEW owns the screen — hide the control bar completely (mirror of SlideToolbar). */
	.ctrl-bar.overview-open,
	.ctrl-bar.overview-open:hover,
	.ctrl-bar.overview-open:focus-within,
	.ctrl-bar.overview-open.pinned,
	.ctrl-bar.overview-open.armed {
		transform: translateX(-50%) translateY(120%);
		opacity: 0;
		visibility: hidden;
		pointer-events: none;
	}

	/* PIN — icon toggle matching the tool bar's pin look, dressed for this bar's shared
	   `--ctrl-bar-*` / `--annot-*` tokens so both PINs read as the same control. */
	.ctrl-pin {
		cursor: pointer;
		font: inherit;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		padding: 0.25em 0.45em;
		margin: 0.2em 0.1em;
		min-width: 1.7em;
		border: 1px solid transparent;
		border-radius: 999px;
		background: transparent;
		color: var(--ctrl-bar-fg, var(--annot-toggle-fg, #f0a33e));
		opacity: 0.62;
		transition: opacity 120ms ease, background 120ms ease;
	}
	.ctrl-pin:hover {
		opacity: 1;
		background: var(--ctrl-bar-hover, var(--annot-bar-hover, rgba(255, 255, 255, 0.1)));
	}
	.ctrl-pin.on {
		opacity: 1;
		background: var(--ctrl-bar-fg, var(--annot-pen, #f0a33e));
		color: var(--annot-bar-on-fg, #1a1206);
		border-color: transparent;
	}
	.ctrl-pin .pin-icon {
		display: block;
		width: 1.15em;
		height: 1.15em;
	}

	/* The bar owns visibility through its own tuck, so its slotted controls must NOT also
	   independently ghost via the overlay's fadeChrome rule — they ride the bar at full
	   strength. (The tool bar's slotted buttons aren't gp-chrome for the same reason.) */
	.ctrl-bar :global(.gp-chrome) {
		opacity: 1 !important;
	}

	/* Slotted controls sit in the flex row rather than at their old canvas-absolute anchor.
	   Each control carries its own in-bar styling (TableOfContent `bar`, NavigationBar
	   `deckLevel`); this just guarantees they flow inline here. */
	.ctrl-bar :global(.toc),
	.ctrl-bar :global(.nav) {
		position: static;
	}

	/* Sit the pager's buttons dead-centre in the row. As a plain block <div> the pager
	   lays its buttons out as inline-blocks on the line-box BASELINE, which rides a couple
	   of pixels below the TOC trigger (whose .toc host is a flex column that centres its
	   button exactly). Making the pager a centred flex row anchors both the same way, so
	   TABLE OF CONTENTS and FIRST/PREV/… share one baseline. */
	.ctrl-bar :global(.nav) {
		display: flex;
		align-items: center;
	}

	/* One uniform word-button row: the pager labels are typed in caps (FIRST / PREV / …)
	   but the TOC trigger's label is Title Case, so side by side they read as two different
	   fonts. Force every trigger/pager button in the bar to uppercase so the row is one
	   consistent typeface. The DOM text stays as authored (e.g. "Table of Contents"), so the
	   accessible name is unaffected; and the TOC flyout lists slide titles as plain <a>/<li>,
	   not buttons, so those keep their real casing. */
	.ctrl-bar :global(button) {
		text-transform: uppercase;
	}

	/* The portal landing zone for a deck-level AnimationBar's scrubber. Empty (and so
	   zero-width) on a slide with no hosted animation; a flex row so the moved-in
	   `.anim-bar` sits centred on the same baseline as the TOC / pager. The bar carries
	   its own `.hosted` styling (AnimationBar's scoped CSS), so this only owns placement. */
	.ctrl-anim {
		display: flex;
		align-items: center;
	}

	/* Thin vertical divider between the bar's groups (TOC | nav). */
	.ctrl-bar-sep {
		width: 1px;
		align-self: stretch;
		margin: 0.35em 0.15em;
		background: var(--ctrl-bar-edge, var(--annot-bar-edge, rgba(255, 255, 255, 0.16)));
	}
</style>
