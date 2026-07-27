<!--
  Steps — accumulating build reveal within a single slide (the classic reveal).

  Wrap a run of content in <Steps> and mark the pieces that should appear one at a
  time with <Fragment>. Everything outside a Fragment shows immediately; each
  Fragment starts hidden (but reserves its layout space, so nothing jumps) and
  fades in when the presenter taps SPACE. SHIFT+SPACE peels the last one back off.

    <script>
      import Steps    from '$lib/components/Steps.svelte';
      import Fragment from '$lib/components/Fragment.svelte';
    </script>

    <Steps>
      <p>Shown right away.</p>
      <Fragment tag="p">Appears on the first Space.</Fragment>
      <Fragment tag="p" transition="fly">Then this one.</Fragment>
    </Steps>

  Keys: Space advances, Shift+Space reverses. While steps remain, Space reveals the
  next Fragment; once the build is spent Space falls through to NavigationBar and
  pages to the NEXT slide (and symmetrically, Shift+Space peels back until nothing
  is revealed, then pages to the PREVIOUS slide). So a build simply inserts
  sub-steps into the deck's forward march — tap Space to walk the whole deck. The
  ARROW keys are never stepped: →/← always page, build or no build. Space is
  ignored while a form field or button has focus, so focused controls keep their
  normal Space behaviour.

  The handoff is decided in utils/stepKeys.ts (spaceIntent), which BOTH this
  listener and NavigationBar's consult against the same build state — so neither
  can page a slide out from under a running build, whatever order they fire in.

  Use ONE Steps per slide with keys='global' (the default); for extra instances set
  keys='off' and drive them with bind:this. In `text` mode (a document artifact)
  every Fragment is shown at once and stepping is disabled — a document has no
  "current step".

  Chrome: the keyboard-owning Steps publishes itself to the `activeSteps` store, so
  NavigationBar's CONTINUE button clicks through the build and greys out when
  nothing is left to reveal (it never pages — that's what NEXT is for). The
  presenter console's CONTINUE relays a `gp:continue` pulse, which advances the
  build too (see `continueKey`).

  Coordinates its children over Svelte context, exactly like Carousel/CarouselItem,
  so authors just nest Fragments in document order.
-->
<script lang="ts">
	import { setContext, onMount, onDestroy } from 'svelte';
	import { writable } from 'svelte/store';
	import { browser } from '$app/environment';
	import { getMode } from '$lib/presentation';
	import { activeSteps } from '$lib/stores/activeSteps';
	import { spaceIntent } from '$lib/utils/stepKeys';

	/** Transition each Fragment uses unless it overrides its own. */
	export let transition: 'fade' | 'fly' | 'slide' | 'scale' | 'none' = 'fade';
	/** Reveal length in seconds (per Fragment default). */
	export let duration = 0.35;
	/** How many Fragments are showing at first (0 = all hidden, build from empty). */
	export let start = 0;
	/** Space/Shift+Space stepping. 'global' binds the whole deck (best: one Steps per
	    slide); 'off' disables keys so you can drive it with bind:this. */
	export let keys: 'global' | 'off' = 'global';
	/** Also advance when the presenter console relays a CONTINUE pulse (gp:continue). */
	export let continueKey = true;

	/** Inline style for the root element, applied last so it wins. */
	export let style: string = '';
	/** DOM id for the root element. */
	export let id: string = '';
	/** Extra class(es) for the root element. NOTE: a slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS (global.css / roles.css / a
	    :global(...) block) or a utility class. See AGENTS.md. */
	let klass: string = '';
	export { klass as class };

	// A document artifact has no notion of a "current step": show everything, and
	// never touch the keyboard (it pages nothing).
	const isText = getMode() === 'text';

	// total: registered Fragment count. revealed: how many are currently showing.
	// Fragments subscribe to `revealed` and compare it to their own index.
	const total = writable(0);
	const revealed = writable(start);
	const defaults = writable({ transition, duration });
	$: defaults.set({ transition, duration });

	// Fragments register in document order during init, getting a stable index.
	function register(): number {
		let index = 0;
		total.update((n) => {
			index = n;
			return n + 1;
		});
		return index;
	}

	setContext('steps', { register, revealed, defaults });

	function clamp(n: number): number {
		return Math.max(0, Math.min($total, n));
	}

	/** Reveal the next hidden Fragment (no-op past the last). */
	export function next() {
		revealed.set(clamp($revealed + 1));
	}
	/** Hide the most recently revealed Fragment (no-op before the first). */
	export function prev() {
		revealed.set(clamp($revealed - 1));
	}
	/** Show exactly `n` Fragments (clamped). */
	export function goTo(n: number) {
		revealed.set(clamp(n));
	}
	/** Reveal every Fragment at once. */
	export function revealAll() {
		revealed.set($total);
	}
	/** Return to the initial `start` count. */
	export function reset() {
		revealed.set(clamp(start));
	}

	$: atStart = $revealed <= 0;
	$: atEnd = $revealed >= $total;

	// In text mode keep every Fragment shown as they register.
	$: if (isText && $revealed !== $total) revealed.set($total);

	// Publish this build to the slide chrome so NavigationBar's CONTINUE button can
	// drive it (same action as Space) and disable itself once the build is spent.
	// Only the keyboard-owning instance registers, matching who Space would drive.
	const token = {};
	$: drivesChrome = browser && !isText && keys === 'global';
	$: if (drivesChrome) activeSteps.set({ owner: token, hasNext: !atEnd, hasPrev: !atStart, next });

	onDestroy(() => {
		// Only clear it if we're still the registered build (a later Steps may own it).
		activeSteps.update((v) => (v && v.owner === token ? null : v));
	});

	// Space builds up, Shift+Space steps back. We only claim the key while a step
	// remains — once the build is spent (or not yet started, going back) we leave
	// the event untouched so NavigationBar pages the deck instead. The arrow keys
	// are never handled here: →/← always page, build or no build.
	function onKeydown(e: KeyboardEvent) {
		const intent = spaceIntent(e, { hasNext: !atEnd, hasPrev: !atStart });
		if (intent === 'reveal') {
			e.preventDefault(); // also stops the browser's scroll-on-space
			next();
		} else if (intent === 'peel') {
			e.preventDefault();
			prev();
		}
		// 'page-next' / 'page-prev' / 'ignore' → not ours; NavigationBar decides.
	}

	// A CONTINUE pulse (presenter console → gp:continue) advances the build too, so
	// a step-through works from the presenter window. Once exhausted it does
	// nothing here, leaving any slide-level onContinue to fire normally.
	function onContinue() {
		if (!atEnd) next();
	}

	onMount(() => {
		if (browser && !isText && keys === 'global') {
			window.addEventListener('keydown', onKeydown);
			if (continueKey) window.addEventListener('gp:continue', onContinue);
		}
	});
	onDestroy(() => {
		if (browser) {
			window.removeEventListener('keydown', onKeydown);
			window.removeEventListener('gp:continue', onContinue);
		}
	});
</script>

<!-- display:contents → Steps adds no box of its own; Fragments lay out exactly
     where they sit in the parent's flow. -->
<div class="steps {klass}" id={id || undefined} style="display: contents; {style}"><slot /></div>
