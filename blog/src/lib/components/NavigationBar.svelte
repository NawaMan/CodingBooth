<script lang="ts">
	import CtrlBtn from './CtrlBtn.svelte';

	import { browser }            from '$app/environment';
	import { page }               from '$app/stores';
	import { onMount, onDestroy } from 'svelte';
	import { getMode, getViewTransitions, getPages, getHandout } from '$lib/presentation';
	import { navigate as pageNavigate } from '$lib/utils/deckNav';
	import { presenterMode } from '$lib/stores/presenter';
	import { activeSteps } from '$lib/stores/activeSteps';
	import { localNav, registerNav, unregisterNav } from '$lib/stores/localChrome';
	import { spaceIntent, isInteractiveTarget } from '$lib/utils/stepKeys';

	export let firstLink = '';
	export let prevLink  = '';
	export let nextLink  = '';
	export let lastLink  = '';
	export let onContinue: (() => void) | null = null;
	/** The ONE deck-level pager, mounted once by SlideDeck's ControlBar rather than
	    per-slide by a template. It reads the current slide's neighbours from SlideDeck
	    and owns arrow/Space paging for every ordinary slide — but it must never fight a
	    slide that brings its OWN NavigationBar (an AppendixPage's RETURN pager, a bespoke
	    route). So a NON-deckLevel bar REGISTERS itself in `localNav` while it lives, and
	    the deckLevel bar goes DORMANT (hidden, and its key handler inert) while any such
	    registration stands. It stays mounted while dormant — not conditionally unmounted —
	    so a client-side slide change can't flicker it in and out. */
	export let deckLevel = false;
	/** Override the view transition used when paging FORWARD (NEXT / → / Space) and
	    BACKWARD (PREV / ←) from this slide.

	    Normally the effect comes from the LEAVING slide's own pages.ts entry, which is
	    right when a slide always leaves the same way. An AppendixPage is the exception:
	    the same NEXT is a step *within* the appendix on one slide and the appendix
	    *closing* on the next, and only the appendix knows which — a leaving slide
	    cannot see that the slide it leaves to lies outside the run. Unset (null) keeps
	    the pages.ts behaviour. */
	export let nextKind: string | null = null;
	export let prevKind: string | null = null;

	// In a Text artifact there are no slides to page through; the bar collapses
	// to a single TOP control that jumps back up the document.
	const mode = getMode();

	// In a HANDOUT (routes/_handout/[deck].html) there is no bar at all. Not hidden — ABSENT,
	// and the difference matters three times over. A handout holds every slide of the deck
	// at once, so a rendered bar would be sixty-odd bars each arming its own global keydown
	// listener, and one → keypress would be handled sixty times; it would emit sixty sets of
	// paging links for the prerenderer to crawl; and "page to the next slide" is not a thing
	// a document can do — the next slide is already there, below this one.
	const handout = getHandout();

	// Most decks page with a full-page load (route-per-slide, honest reload). A
	// deck that opted into setViewTransitions(true) instead navigates client-side
	// (goto) wrapped in the View Transitions API, so a slide animates into the next.
	const viewTransitions = getViewTransitions();
	const pages = getPages();

	// The current slide's chosen leave-transition, picked per DIRECTION: `transition`
	// going forward (→), `transitionBack` going back (←). Both default to 'slide'.
	// So a slide can show an effect forward and replay (or stay neutral) on the way
	// back. See pages.ts / view-transitions.css.
	$: currentPath = $page.url.pathname.replace(/\/+$/, '').split('/').pop() || '';
	$: currentPage = pages.find((p) => p.path === currentPath);

	type Dir = 'forward' | 'back';

	function kindFor(direction: Dir): string {
		const override = direction === 'back' ? prevKind : nextKind;
		if (override) return override;
		return (direction === 'back' ? currentPage?.transitionBack : currentPage?.transition) ?? 'slide';
	}

	// In the presenter console (?present) keep the flag across paging, so the
	// console stays the console; the audience window pages without it.
	function decorate(href: string): string {
		if (!href || !$presenterMode) return href;
		return href + (href.includes('?') ? '&' : '?') + 'present';
	}

	// Navigate to `href`, animating in `direction` when this deck uses view
	// transitions (delegated to the shared deckNav helper so a followed navigation
	// in SlideDeck animates identically).
	function navigate(href: string, direction: Dir) {
		pageNavigate(decorate(href), { viewTransitions, kind: kindFor(direction), direction });
	}

	$: onFirst = () => navigate(firstLink, 'back');
	$: onPrev  = () => navigate(prevLink,  'back');
	$: onNext  = () => navigate(nextLink,  'forward');
	$: onLast  = () => navigate(lastLink,  'forward');

	// CONTINUE is the in-slide step. A <Steps> build on this slide publishes itself
	// to `activeSteps` (it can't reach us over context — it's a sibling), so the
	// button reveals the next Fragment and greys out once the build is spent. Unlike
	// Space it never pages: CONTINUE is strictly the *within-slide* control, which is
	// why it disables instead of falling through to NEXT. A slide can still pass its
	// own onContinue hook; when both exist the click drives each of them once.
	$: steps = $activeSteps;
	$: canContinue = !!onContinue || !!steps?.hasNext;

	function doContinue() {
		if (steps?.hasNext) steps.next();
		onContinue?.();
	}

	function onTop() {
		// A Text artifact scrolls inside its own container; fall back to the window.
		const target = document.querySelector('[data-text-scroll]') ?? window;
		target.scrollTo({ top: 0, behavior: 'smooth' });
	}

	// A deckLevel pager yields the keys entirely while a slide owns its own bar — the
	// slide-local one handles paging (and the appendix its RETURN keys) instead.
	$: dormant = deckLevel && $localNav.size > 0;

	function handleGlobalKeydown(event: KeyboardEvent) {
		if (dormant) return;
		// While the user is typing (Monaco textarea, an input, …) ←/→ must not page
		// the deck out from under the caret. Space already ignores interactive
		// targets via spaceIntent → isInteractiveTarget; arrows need the same check.
		if (isInteractiveTarget(event.target)) return;
		if (event.key === 'ArrowLeft' && prevLink) {
			event.preventDefault();
			navigate(prevLink, 'back');

		} else if (event.key === 'ArrowRight' && nextLink) {
			event.preventDefault();
			navigate(nextLink, 'forward');

		} else {
			// Space advances: a <Steps> build swallows it while steps remain (that
			// listener acts on 'reveal'/'peel'), and once spent it falls to us and
			// pages the deck. Both listeners judge the SAME build state, so it does
			// not matter which of them the browser calls first.
			const intent = spaceIntent(event, steps ? { hasNext: steps.hasNext, hasPrev: steps.hasPrev } : null);
			if (intent === 'page-next' && nextLink) {
				event.preventDefault();
				navigate(nextLink, 'forward');
			} else if (intent === 'page-prev' && prevLink) {
				event.preventDefault();
				navigate(prevLink, 'back');
			}
		}
	}

	// A CONTINUE pulse relayed from the presenter console (SlideDeck turns it into
	// this DOM event) drives the same onContinue hook as the on-screen CONTINUE button.
	function handleRelayedContinue() {
		onContinue?.();
	}

	// A slide-local pager (NOT the deckLevel one) publishes itself so the deck-level
	// pager can yield to it. Only where it actually renders a bar — never in a handout,
	// which draws no pager at all (and would otherwise register sixty of them).
	const navOwner = Symbol('nav');

	onMount(() => {
		// Arrow-key paging only makes sense between slides, not in a document.
		if (browser && mode !== 'text' && !handout) {
			window.addEventListener('keydown', handleGlobalKeydown);
			window.addEventListener('gp:continue', handleRelayedContinue);
		}
		if (browser && !deckLevel && !handout) registerNav(navOwner);
	});

	onDestroy(() => {
		if (browser) {
			window.removeEventListener('keydown', handleGlobalKeydown);
			window.removeEventListener('gp:continue', handleRelayedContinue);
			if (!deckLevel && !handout) unregisterNav(navOwner);
		}
	});
</script>

<style>
	.nav {
		/* functional */
		position: absolute;
		/* Vertical position knob: negative = lower, positive = higher. */
		bottom: -10px;
		left: 0px;
	}
	/* The deckLevel pager rides SlideDeck's ControlBar (a viewport-fixed flex row), not
	   the slide's bottom-left corner — so it drops its canvas-absolute anchor and flows
	   inline. `dormant` hides it (a slide owns its own pager) while it stays mounted, so
	   its window key listener can go inert rather than be torn down and re-armed. */
	.nav.bar {
		position: static;
		bottom: auto;
		left: auto;
	}
	.nav.bar.dormant {
		display: none;
	}
	.nav.text {
		/* Pinned to the viewport so it stays reachable while scrolling. */
		position: fixed;
		/* Keep the text-mode TOP control flush with the viewport bottom (the slide
		   nav's downward nudge above doesn't apply here). */
		bottom: 0px;
		/* In text mode the bar is rendered outside the .text-page font-size lever,
		   so set the same base here to keep the TOP control sized like slide nav. */
		font-size: 1.5em;
	}
</style>

{#if handout}
	<!-- Nothing. A document does not page. -->
{:else if mode === 'text'}
<div class="nav text gp-chrome no-print">
	<CtrlBtn chrome text="TOP" on:click={onTop} />
</div>
{:else}
<div class="nav gp-chrome no-print" class:bar={deckLevel} class:dormant>
	<CtrlBtn chrome text="FIRST"    on:click={onFirst}    isDisabled={!firstLink} />
	<CtrlBtn chrome text="PREV"     on:click={onPrev}     isDisabled={!prevLink} />
	<CtrlBtn chrome text="CONTINUE" on:click={doContinue} isDisabled={!canContinue} />
	<CtrlBtn chrome text="NEXT"     on:click={onNext}     isDisabled={!nextLink} />
	<CtrlBtn chrome text="LAST"     on:click={onLast}     isDisabled={!lastLink}/>
	<!-- A slide with an EXTRA way to move gets to put its control here rather than
	     inventing a second bar somewhere else on the canvas: an AppendixPage's RETURN
	     sits at the end of this row, in the same padding, on the same baseline. -->
	<slot />
</div>
{/if}
