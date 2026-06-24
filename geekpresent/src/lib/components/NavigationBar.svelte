<script lang="ts">
	import CtrlBtn from './CtrlBtn.svelte';

	import { browser }            from '$app/environment';
	import { goto }               from '$app/navigation';
	import { page }               from '$app/stores';
	import { onMount, onDestroy } from 'svelte';
	import { getMode, getViewTransitions, getPages } from '$lib/presentation';

	export let firstLink = '';
	export let prevLink  = '';
	export let nextLink  = '';
	export let lastLink  = '';
	export let onContinue: (() => void) | null = null;

	// In a Text artifact there are no slides to page through; the bar collapses
	// to a single TOP control that jumps back up the document.
	const mode = getMode();

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
		return (direction === 'back' ? currentPage?.transitionBack : currentPage?.transition) ?? 'slide';
	}

	// Navigate to `href`, animating in `direction` when this deck uses view
	// transitions and the browser supports them. Falls back, in order, to a plain
	// client-side goto (still no reload/blink), then to a full-page load.
	function navigate(href: string, direction: Dir) {
		if (!href) return;

		if (!viewTransitions) {
			window.location.href = href;
			return;
		}
		// @ts-ignore — startViewTransition is not in older lib.dom typings.
		if (!browser || typeof document.startViewTransition !== 'function') {
			goto(href);
			return;
		}

		// These attributes key the keyframes in view-transitions.css: data-vt-kind
		// picks the effect (the leaving slide's own), data-vt its direction. Both are
		// cleared once the transition settles.
		const root = document.documentElement;
		root.dataset.vtKind = kindFor(direction);
		root.dataset.vt = direction;
		// @ts-ignore
		const transition = document.startViewTransition(() => goto(href));
		transition.finished.finally(() => {
			delete root.dataset.vt;
			delete root.dataset.vtKind;
		});
	}

	$: onFirst = () => navigate(firstLink, 'back');
	$: onPrev  = () => navigate(prevLink,  'back');
	$: onNext  = () => navigate(nextLink,  'forward');
	$: onLast  = () => navigate(lastLink,  'forward');

	function onTop() {
		// A Text artifact scrolls inside its own container; fall back to the window.
		const target = document.querySelector('[data-text-scroll]') ?? window;
		target.scrollTo({ top: 0, behavior: 'smooth' });
	}

	function handleGlobalKeydown(event: KeyboardEvent) {
		if (event.key === 'ArrowLeft' && prevLink) {
			event.preventDefault();
			navigate(prevLink, 'back');

		} else if (event.key === 'ArrowRight' && nextLink) {
			event.preventDefault();
			navigate(nextLink, 'forward');
		}
	}

	onMount(() => {
		// Arrow-key paging only makes sense between slides, not in a document.
		if (browser && mode !== 'text') {
			window.addEventListener('keydown', handleGlobalKeydown);
		}
	});

	onDestroy(() => {
		if (browser) {
			window.removeEventListener('keydown', handleGlobalKeydown);
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

{#if mode === 'text'}
<div class="nav text no-print">
	<CtrlBtn chrome text="TOP" on:click={onTop} />
</div>
{:else}
<div class="nav no-print">
	<CtrlBtn chrome text="FIRST"    on:click={onFirst}    isDisabled={!firstLink} />
	<CtrlBtn chrome text="PREV"     on:click={onPrev}     isDisabled={!prevLink} />
	<CtrlBtn chrome text="CONTINUE" on:click={onContinue} isDisabled={!onContinue} />
	<CtrlBtn chrome text="NEXT"     on:click={onNext}     isDisabled={!nextLink} />
	<CtrlBtn chrome text="LAST"     on:click={onLast}     isDisabled={!lastLink}/>
</div>
{/if}
