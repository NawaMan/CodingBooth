<!--
  Carousel — a one-at-a-time stepper for a slide (or Text).

  Cycle through a set of items in place: images, cards, code, any markup. Each
  item is a <CarouselItem>; the Carousel coordinates them over Svelte context, so
  authors just nest them in document order:

    <script>
      import Carousel     from '$lib/components/Carousel.svelte';
      import CarouselItem from '$lib/components/CarouselItem.svelte';
      let car;                       // bind:this for the imperative API
    </script>

    <Carousel bind:this={car} width="1200px" height="600px">
      <CarouselItem><img src="a.png" alt="" /></CarouselItem>
      <CarouselItem><h2>Any markup</h2></CarouselItem>
    </Carousel>

  Controls: prev/next arrows and clickable dots (both on by default), plus
  keyboard stepping on , / < (prev) and . / > (next) — keys the deck's arrow-key
  nav doesn't touch, so a presenter can step without clicking. For a build-step
  feel, `advanceOnClick` steps forward on click/Enter. Opt into `wheel` for
  scroll-to-step. Set `loop={false}` to stop at the ends instead of wrapping
  (arrows disable; keys, clicks and the wheel all clamp). Drive it from code with
  bind:this: `car.next()`, `car.prev()`, `car.goTo(2)`, `car.reset()`.

  Like the other GeekPresent components it anchors to its own box (fixed
  width/height), so it works on a slide and inline in Text alike.
-->
<script lang="ts">
	import { setContext, onMount, onDestroy } from 'svelte';
	import { writable } from 'svelte/store';
	import { browser } from '$app/environment';

	/** Stage size. Fixed like Box/Code so the carousel owns its own box. */
	export let width = '1200px';
	export let height = '600px';
	/** Initial active item (0-based). */
	export let start = 0;
	/** Wrap past the ends. When false, the arrows disable at first/last. */
	export let loop = true;
	/** 'fade' (crossfade), 'slide' (horizontal), or 'none' (instant cut). */
	export let transition: 'fade' | 'slide' | 'none' = 'fade';
	/** Transition length in seconds. */
	export let duration = 0.4;
	/** Show the prev/next arrows. */
	export let arrows = true;
	/** Show the dot indicators. */
	export let dots = true;
	/** Click (or Enter/Space) on the stage advances to the next item. */
	export let advanceOnClick = false;
	/** Step on mouse-wheel / trackpad scroll while the pointer is over it. Off by
	    default: a wheel-consuming carousel embedded in a scrolling Text would trap
	    the page scroll. When looping is off it releases the wheel at the ends so
	    the page can scroll past. */
	export let wheel = false;
	/** Keyboard stepping with , / < (prev) and . / > (next). These keys don't
	    clash with the deck's arrow-key nav.
	    'global' = works deck-wide (best when a slide has one carousel);
	    'focus'  = only when the carousel is focused (use with several per slide);
	    'off'    = no keyboard stepping. */
	export let keys: 'global' | 'focus' | 'off' = 'global';
	/** aria-label for the region. */
	export let label = 'Carousel';

	/** Inline style for the root element, applied last so it wins. */
	export let style: string = '';
	/** DOM id for the root element. */
	export let id: string = '';
	/** Extra class(es) for the root element. NOTE: a slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS (global.css / roles.css / a
	    :global(...) block) or a utility class. See AGENTS.md. */
	let klass: string = '';
	export { klass as class };

	// total: item count, kept reactive so the dot row tracks registrations.
	// current: the active index; items subscribe to know when they're showing.
	// mode: the transition mode, shared so each item can style itself.
	const total = writable(0);
	const current = writable(start);
	const mode = writable(transition);
	$: mode.set(transition);

	// Items register in document order during their init, getting a stable index.
	function register(): number {
		let index = 0;
		total.update((n) => {
			index = n;
			return n + 1;
		});
		return index;
	}

	setContext('carousel', { register, current, mode });

	function resolve(i: number): number {
		const n = $total;
		if (n === 0) return 0;
		if (loop) return ((i % n) + n) % n;
		return Math.max(0, Math.min(n - 1, i));
	}

	/** Jump to a specific item (clamped, or wrapped when `loop`). */
	export function goTo(i: number) {
		current.set(resolve(i));
	}
	/** Advance to the next item. */
	export function next() {
		goTo($current + 1);
	}
	/** Go back to the previous item. */
	export function prev() {
		goTo($current - 1);
	}
	/** Return to the starting item. */
	export function reset() {
		goTo(start);
	}

	// Keep the active index in range if items appear/disappear or `loop` flips.
	$: if ($current > $total - 1 && $total > 0) current.set(resolve($current));

	$: atStart = $current <= 0;
	$: atEnd = $current >= $total - 1;

	function onStageKeydown(e: KeyboardEvent) {
		if (e.key === 'Enter' || e.key === ' ') {
			e.preventDefault();
			next();
		}
	}

	// , / < step back, . / > step forward (matching shifted + unshifted forms).
	// stopPropagation keeps the event from also reaching any deck-level handler.
	function onKeys(e: KeyboardEvent) {
		if (keys === 'off' || e.defaultPrevented) return;
		const t = e.target as HTMLElement | null;
		if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable)) return;
		if (e.key === ',' || e.key === '<') {
			e.preventDefault();
			e.stopPropagation();
			prev();
		} else if (e.key === '.' || e.key === '>') {
			e.preventDefault();
			e.stopPropagation();
			next();
		}
	}

	// One step per wheel gesture: consume the notch, but only actually move once
	// per cooldown so a trackpad flick doesn't skip several items.
	let wheelLockUntil = 0;
	function onWheel(e: WheelEvent) {
		if (!wheel) return;
		const delta = Math.abs(e.deltaX) > Math.abs(e.deltaY) ? e.deltaX : e.deltaY;
		if (Math.abs(delta) < 6) return; // ignore jitter → page scrolls normally
		const target = resolve($current + (delta > 0 ? 1 : -1));
		if (target === $current) return; // clamped at an end → let the page scroll past
		e.preventDefault();
		const now = Date.now();
		if (now < wheelLockUntil) return; // still within the one-step cooldown
		current.set(target);
		wheelLockUntil = now + 320;
	}

	onMount(() => {
		if (browser && keys === 'global') window.addEventListener('keydown', onKeys);
	});
	onDestroy(() => {
		if (browser) window.removeEventListener('keydown', onKeys);
	});
</script>

<!-- Focus mode makes the region focusable so , / . / < / > work while it's the
     active widget; region is the right role, hence the a11y overrides. -->
<!-- svelte-ignore a11y-no-noninteractive-tabindex a11y-no-noninteractive-element-interactions -->
<div
	class="carousel mode-{transition} {klass}"
	class:focusable={keys === 'focus'}
	id={id || undefined}
	role="region"
	aria-roledescription="carousel"
	aria-label={label}
	tabindex={keys === 'focus' ? 0 : undefined}
	style="--carousel-dur: {duration}s; width: {width}; height: {height}; {style}"
	on:keydown={keys === 'focus' ? onKeys : undefined}
	on:wheel|nonpassive={onWheel}
>
	{#if advanceOnClick}
		<div
			class="carousel-stage"
			role="button"
			tabindex="0"
			aria-label="Next item"
			on:click={next}
			on:keydown={onStageKeydown}
		>
			<div class="carousel-track" style="--carousel-x: {$current * -100}%;">
				<slot />
			</div>
		</div>
	{:else}
		<div class="carousel-stage">
			<div class="carousel-track" style="--carousel-x: {$current * -100}%;">
				<slot />
			</div>
		</div>
	{/if}

	{#if arrows && $total > 1}
		<button
			class="carousel-arrow prev"
			aria-label="Previous item"
			disabled={!loop && atStart}
			on:click|stopPropagation={prev}
		>
			<svg viewBox="0 0 24 24" aria-hidden="true"
				><path d="M15 4 L7 12 L15 20" fill="none" stroke="currentColor" stroke-width="2.5"
					stroke-linecap="round" stroke-linejoin="round" /></svg
			>
		</button>
		<button
			class="carousel-arrow next"
			aria-label="Next item"
			disabled={!loop && atEnd}
			on:click|stopPropagation={next}
		>
			<svg viewBox="0 0 24 24" aria-hidden="true"
				><path d="M9 4 L17 12 L9 20" fill="none" stroke="currentColor" stroke-width="2.5"
					stroke-linecap="round" stroke-linejoin="round" /></svg
			>
		</button>
	{/if}

	{#if dots && $total > 1}
		<div class="carousel-dots" role="tablist" aria-label="Choose item">
			{#each Array($total) as _, i (i)}
				<button
					class="carousel-dot"
					class:active={$current === i}
					role="tab"
					aria-label={`Go to item ${i + 1}`}
					aria-selected={$current === i}
					on:click|stopPropagation={() => goTo(i)}
				></button>
			{/each}
		</div>
	{/if}
</div>

<style>
	.carousel {
		/* Tunables — override per instance via style, or globally in a theme.
		   The accent falls back to the shared control colour. */
		--carousel-arrow-size: 3em;
		--carousel-dot-size: 0.85em;
		--carousel-accent: var(--ctrl-strong-bg, #2980b9);

		position: relative;
		display: block;
		margin: 0 auto;
	}
	.carousel.focusable:focus-visible {
		outline: 2px solid var(--carousel-accent);
		outline-offset: 4px;
	}

	.carousel-stage {
		position: relative;
		width: 100%;
		height: 100%;
		overflow: hidden;
		border-radius: 10px;
	}

	.carousel-track {
		position: relative;
		width: 100%;
		height: 100%;
	}
	/* slide: lay items in a row and shift the track; items are flex:0 0 100%. */
	.carousel.mode-slide .carousel-track {
		display: flex;
		transform: translateX(var(--carousel-x, 0%));
		transition: transform var(--carousel-dur, 0.4s) ease;
	}

	/* --- arrows --- */
	.carousel-arrow {
		position: absolute;
		top: 50%;
		transform: translateY(-50%);
		width: var(--carousel-arrow-size);
		height: var(--carousel-arrow-size);
		display: flex;
		align-items: center;
		justify-content: center;
		padding: 0;
		border: 0;
		border-radius: 50%;
		cursor: pointer;
		color: var(--on-accent, #fff);
		background: var(--ctrl-bg, #181818);
		opacity: 0.72;
		transition: opacity 0.15s ease, background-color 0.15s ease;
		z-index: 2;
	}
	.carousel-arrow.prev {
		left: 0.6em;
	}
	.carousel-arrow.next {
		right: 0.6em;
	}
	.carousel-arrow:hover:not(:disabled) {
		opacity: 1;
		background: var(--ctrl-hover-bg, #2980b9);
	}
	.carousel-arrow:active:not(:disabled) {
		transform: translateY(-50%) scale(0.94);
	}
	.carousel-arrow:disabled {
		opacity: 0.25;
		cursor: default;
	}
	.carousel-arrow svg {
		width: 55%;
		height: 55%;
	}

	/* --- dots --- */
	.carousel-dots {
		position: absolute;
		left: 50%;
		bottom: 0.7em;
		transform: translateX(-50%);
		display: flex;
		gap: 0.55em;
		padding: 0.35em 0.7em;
		border-radius: 999px;
		background: color-mix(in srgb, var(--ctrl-bg, #181818) 55%, transparent);
		z-index: 2;
	}
	.carousel-dot {
		width: var(--carousel-dot-size);
		height: var(--carousel-dot-size);
		padding: 0;
		border: 0;
		border-radius: 50%;
		cursor: pointer;
		background: var(--on-accent, #fff);
		opacity: 0.4;
		transition: opacity 0.15s ease, transform 0.15s ease, background-color 0.15s ease;
	}
	.carousel-dot:hover {
		opacity: 0.75;
	}
	.carousel-dot.active {
		opacity: 1;
		background: var(--carousel-accent);
		transform: scale(1.15);
	}

	@media (prefers-reduced-motion: reduce) {
		.carousel.mode-slide .carousel-track {
			transition: none;
		}
	}
</style>
