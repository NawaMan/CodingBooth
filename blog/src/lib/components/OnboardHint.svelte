<!--
  OnboardHint — "here's how to get around", for a viewer who is stuck on slide one.

  A deck pages with → / Space / ←, and both of its bars hide at the window's edges. A
  first-time viewer knows neither, so they sit on the title slide pressing Enter,
  clicking, scrolling — or doing nothing at all. This watches for that and, when it
  sees it, says how to move on: the keys, and where the bars are (with the two window
  edges glowing for a moment, so "the top or bottom edge" is something you can see).

  A canvas-level SINGLETON, like Spotlight and Annotate: SlideDeck mounts it, no slide
  places it, and the deck offers it with `<SlideDeck onboardHint>` (on by default).

  The rules are pure and tested in onboard/onboardCore.ts; the "already knows" flag is
  stores/onboard.ts, one per origin. In short:
    • It watches only on the first visible slide, and only for a viewer who has never
      left it, opened a bar, pressed a paging key or dismissed this hint.
    • It appears after `delayMs` of nothing useful — or AT ONCE on a stray input (Enter,
      ↑/↓, a click on the slide, a scroll): what a stuck viewer tries first.
    • A paging key, a bar, or "Got it" ends it for good. Leaving the slide ends it too —
      SlideDeck records that on arrival at any later slide.
    • `suppressed` (a live console, a kiosk, a recording, `?clean`, an embedded tile…)
      keeps it off any screen an audience might be watching.
    • `force` (SlideDeck sets it from `?onboard`) shows it at once, on any slide, whatever
      the viewer has done before — for trying it out or demoing it. It also clears the
      saved flag, so the next visit without `?onboard` starts as a new viewer. Once
      forced, only "Got it" or a paging key put it away: the viewer is not stuck, they
      asked for it.

  Window-fixed (not on the scaled canvas), so it reads at one size whatever the zoom,
  and SSR-inert: it renders nothing until mounted in a browser. Tagged
  `gp-chrome no-print`, so CAPTURE and printing leave it out.

  Props:
    offered     — the deck offers the hint at all.
    firstSlide  — we stand on the deck's first visible slide (with a second to go to).
    suppressed  — something owns the screen; stay silent.
    bars        — the deck shows its bars, so the hint may point at them.
    delayMs     — idle time before it appears (default 8000).
    force       — show it now, whatever the gates say (`?onboard`); `suppressed` still wins.
    themeClass  — the deck's theme class, so the hint picks up its role tokens even
                  though it sits outside the themed canvas.
    style / id / class — the usual root passthroughs.

  Colours: `--onboard-fg` / `--onboard-bg` / `--onboard-border` / `--onboard-accent`,
  each falling back to the Hint's `--hint-*` tokens.
-->
<script lang="ts">
	import { onMount } from 'svelte';
	import Kbd from '$lib/components/Kbd.svelte';
	import { onboardDone, markOnboarded } from '$lib/stores/onboard';
	import { classifyKey, onboardDelayMs, shouldWatch } from '$lib/onboard/onboardCore';
	import { isChromeTypingTarget } from '$lib/chrome/chromeArmCore';

	/** The deck offers the hint (`<SlideDeck onboardHint>`). */
	export let offered: boolean = true;
	/** We stand on the deck's first visible slide. */
	export let firstSlide: boolean = false;
	/** Something owns the screen (console, kiosk, recording, ?clean…): stay silent. */
	export let suppressed: boolean = false;
	/** The deck shows its bars, so the hint may point at them. */
	export let bars: boolean = true;
	/** Idle ms before the hint appears. */
	export let delayMs: number = 8000;
	/** Show it now, on any slide, to any viewer (`?onboard`). `suppressed` still wins. */
	export let force: boolean = false;
	/** The deck's theme class, so role tokens reach a hint outside the canvas. */
	export let themeClass: string = '';
	/** Inline style for the card, applied last so it wins. */
	export let style: string = '';
	/** DOM id for the card. */
	export let id: string = '';
	/** Extra class(es) for the card. */
	let klass: string = '';
	export { klass as class };

	let mounted = false;
	let shown = false;
	let timer: ReturnType<typeof setTimeout> | null = null;
	// A forced hint ignores the saved flag, so putting it away needs a flag of its own.
	let dismissed = false;

	$: forced = force && !dismissed;
	$: active =
		mounted && shouldWatch({ offered, done: $onboardDone, firstSlide, suppressed, force: forced });
	$: if (active && forced) show();
	else if (active) arm(onboardDelayMs(delayMs));
	else disarm();

	function arm(ms: number) {
		if (shown || timer) return;
		timer = setTimeout(show, ms);
	}

	function disarm() {
		if (timer) clearTimeout(timer);
		timer = null;
		shown = false;
	}

	function show() {
		if (timer) clearTimeout(timer);
		timer = null;
		shown = true;
	}

	// Things a stuck viewer clicks that are NOT stray: anything that does something of
	// its own (a link, a slide's button, a field), the bars, and this hint itself.
	function done() {
		dismissed = true;
		markOnboarded();
	}

	const INTERACTIVE =
		'a, button, input, textarea, select, label, [contenteditable], [role="button"], .overlay, .gp-chrome';

	function onKey(e: KeyboardEvent) {
		if (!active || isChromeTypingTarget(e.target)) return;
		const signal = classifyKey(e.key, { ctrl: e.ctrlKey, meta: e.metaKey, alt: e.altKey });
		if (signal === 'explore') done();
		else if (signal === 'stray') show();
	}

	function onPointer(e: PointerEvent) {
		if (!active) return;
		const el = e.target as Element | null;
		if (el?.closest?.(INTERACTIVE)) return;
		show();
	}

	function onWheel() {
		if (active) show();
	}

	onMount(() => {
		if (force) onboardDone.set(false);
		mounted = true;
		// CAPTURE phase: the deck's own key handlers page on → and may stop the event; this
		// must hear the key before the page unloads under it.
		window.addEventListener('keydown', onKey, true);
		window.addEventListener('pointerdown', onPointer, true);
		window.addEventListener('wheel', onWheel, { capture: true, passive: true });
		return () => {
			window.removeEventListener('keydown', onKey, true);
			window.removeEventListener('pointerdown', onPointer, true);
			window.removeEventListener('wheel', onWheel, { capture: true });
			disarm();
		};
	});
</script>

{#if active && shown}
	<div class="onboard-theme {themeClass}">
		{#if bars}
			<div class="edge top gp-chrome no-print" aria-hidden="true"></div>
			<div class="edge bottom gp-chrome no-print" aria-hidden="true"></div>
		{/if}
		<div
			class="onboard-hint gp-chrome no-print {klass}"
			id={id || undefined}
			role="status"
			aria-live="polite"
			{style}
		>
			<p class="title">New here? Here's how to get around.</p>
			<!-- → turns the page; Space plays the slide's next build step first, and only
			     turns the page once there is none left. -->
			<p class="row">
				<Kbd>→</Kbd> next slide
				<span class="sep" aria-hidden="true">·</span>
				<Kbd>Space</Kbd> next step
				<span class="sep" aria-hidden="true">·</span>
				<Kbd>←</Kbd> back
			</p>
			{#if bars}
				<!-- Its own line, not a tail on the sentence below: the keyboard way to both bars
				     is as much a key to learn as →. `auto` draws it ⌥. on a Mac. -->
				<p class="row alt-bars">
					<Kbd keys="Alt+." platform="auto" /> tool bar <span class="where">(top)</span> + nav bar
					<span class="where">(bottom)</span>
				</p>
				<p class="row">or point at the <b>top</b> or <b>bottom</b> edge of the window</p>
			{/if}
			<button type="button" class="got-it" on:click={done}>Got it</button>
		</div>
	</div>
{/if}

<style>
	.onboard-theme {
		/* Carries the deck's theme class for its tokens only — no box of its own, so a
		   theme's background or padding cannot paint here. */
		display: contents;
	}

	.onboard-hint {
		position: fixed;
		left: 50%;
		bottom: 18vh;
		transform: translateX(-50%);
		/* Above the ink surface (40), below the bars' overlay (50): opening a bar ends the
		   hint anyway, and a bar must never sit under it. */
		z-index: 45;
		max-width: min(36rem, calc(100vw - 2rem));
		box-sizing: border-box;
		padding: 0.9rem 1.2rem 1rem;
		border-radius: 0.8rem;
		font-family: system-ui, sans-serif;
		font-size: 1rem;
		line-height: 1.5;
		text-align: center;
		color: var(--onboard-fg, var(--hint-fg, #c0f1ff));
		background: color-mix(in srgb, var(--onboard-bg, var(--hint-bg, #000000)) 88%, transparent);
		border: 1px solid
			color-mix(in srgb, var(--onboard-border, var(--hint-border, #c0f1ff)) 40%, transparent);
		box-shadow: 0 0.5rem 2rem rgba(0, 0, 0, 0.45);
		animation: onboard-in 280ms ease-out;
	}

	.title {
		margin: 0 0 0.4rem;
		font-weight: bold;
		font-size: 1.1rem;
	}

	.row {
		margin: 0.25rem 0;
	}

	.where {
		opacity: 0.7;
	}

	.sep {
		margin: 0 0.4em;
		opacity: 0.6;
	}

	.got-it {
		margin-top: 0.6rem;
		padding: 0.3rem 1.1rem;
		font: inherit;
		font-weight: bold;
		color: inherit;
		background: transparent;
		border: 1px solid
			color-mix(in srgb, var(--onboard-accent, var(--hint-border, #c0f1ff)) 60%, transparent);
		border-radius: 999px;
		cursor: pointer;
	}
	.got-it:hover,
	.got-it:focus-visible {
		background: color-mix(
			in srgb,
			var(--onboard-accent, var(--hint-border, #c0f1ff)) 18%,
			transparent
		);
	}

	/* The two window edges where the bars hide, glowing so "the top or bottom edge" is a
	   place you can see rather than a sentence you have to decode. */
	.edge {
		position: fixed;
		left: 0;
		right: 0;
		height: 0.5rem;
		z-index: 45;
		pointer-events: none;
		animation: onboard-pulse 1.6s ease-in-out infinite;
	}
	.edge.top {
		top: 0;
		background: linear-gradient(
			to bottom,
			var(--onboard-accent, var(--hint-border, #c0f1ff)),
			transparent
		);
	}
	.edge.bottom {
		bottom: 0;
		background: linear-gradient(
			to top,
			var(--onboard-accent, var(--hint-border, #c0f1ff)),
			transparent
		);
	}

	@keyframes onboard-in {
		from {
			opacity: 0;
			transform: translate(-50%, 0.6rem);
		}
		to {
			opacity: 1;
			transform: translate(-50%, 0);
		}
	}

	@keyframes onboard-pulse {
		0%,
		100% {
			opacity: 0.15;
		}
		50% {
			opacity: 0.7;
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.onboard-hint,
		.edge {
			animation: none;
		}
		.edge {
			opacity: 0.4;
		}
	}
</style>
