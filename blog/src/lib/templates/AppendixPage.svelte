<!--
  AppendixPage — a slide you jump INTO and return FROM. A slide as a function call,
  rather than a destination.

  The deep-dive a talk only sometimes needs: a proof, a full API table, a backup
  demo. It behaves like a real book's appendix, and that is the whole design:

    - It is a CHAPTER, not a slide. Give several slides `hidden: true`, contiguously
      in pages.ts, and PREV/NEXT page through them exactly as they page through the
      body of the deck. FIRST/LAST are the appendix's own ends, not the deck's.

    - The ordinary forward march RETURNS from it. Page off the end of the run — NEXT,
      →, or Space, whichever the speaker reaches for — and you land back on the slide
      that called you. Page back off the front and you land there too. So there is
      nothing new to learn: you leave an appendix by walking out of it. RETURN (and
      Backspace) are the shortcut, for leaving from the middle.

    - `hidden` is OPTIONAL. It makes the appendix a DETOUR: off the linear order, so
      a straight run-through of the deck never wanders in. Leave it off and the same
      appendix sits in the deck's normal flow — back matter you can simply page into,
      the way a book lets you — and still returns to a caller that jumped in.

  Usage — the appendix's own +page.svelte:

    <script>
      import AppendixPage from '$lib/templates/AppendixPage.svelte';
    </script>

    <AppendixPage title="How the GC actually marks">
      <p>The long version, for when someone asks.</p>
    </AppendixPage>

  and its pages.ts entries — contiguous, and `hidden` if it should be a detour:

    { path: "appendix-gc.html",   title: "Appendix — GC",            hidden: true },
    { path: "appendix-gc-2.html", title: "Appendix — Write barriers", hidden: true },

  THE RETURN ADDRESS rides in the URL — `?return=heap-layout.html`, stamped by the
  AppendixLink that called us — not in a store. So it survives a reload, and it is
  legible: a speaker can see where RETURN goes by reading the address bar. Every link
  within the appendix re-stamps it, so paging deeper never loses the way home.

  It is also, therefore, untrusted; utils/appendixCore.ts validates it and refuses
  anything that is not a plain in-deck slide name. With no usable address (a direct
  link, a bookmark, a refused one) the way out becomes the deck's first slide and the
  control reads DECK — an appendix must never strand you, since it is off the linear
  order and the browser's Back button would otherwise be the only way out.

  Props: title / subtitle / rule / align — and style / id / class — pass straight through
  to ContentPage — an appendix is an ordinary slide, laid out normally. Only its
  NAVIGATION differs.

    returnText — label for the return control (default 'RETURN').
    deckText   — label when there is no return address (default 'DECK').
    transition — animate the detour: leaving the appendix travels back UP (whichever
                 control does it — the appendix sinks away and the caller drops back
                 into place), and paging within it steps sideways like the rest of the
                 deck. The mirror image of the AppendixLink you travelled down through,
                 so set it on both. Default false — an animated navigation must
                 be a CLIENT-SIDE one (the View Transitions API cannot cross a
                 document), and Monaco does not survive that: an animated appendix
                 must use SourceView/QuickCode, never ViewSource/Code/CodeBox. See
                 SourceView.svelte and the memory "monaco-breaks-on-spa-nav".
-->
<script lang="ts">
	import ContentPage   from '$lib/templates/ContentPage.svelte';
	import CtrlBtn       from '$lib/components/CtrlBtn.svelte';
	import NavigationBar from '$lib/components/NavigationBar.svelte';

	import { browser }            from '$app/environment';
	import { page }               from '$app/stores';
	import { get }                from 'svelte/store';
	import { onMount, onDestroy } from 'svelte';

	import { getPages, getViewTransitions, setViewTransitions } from '$lib/presentation';
	import { navigate as pageNavigate }     from '$lib/utils/deckNav';
	import { getPageNavigation, visiblePages } from '$lib/utils/navigate';
	import {
		appendixKinds,
		appendixNavigation,
		appendixRun,
		carryReturnThrough,
		readReturnParam,
		returnHref,
		slidePathOf,
		KIND_OUT
	} from '$lib/utils/appendixCore';
	import { presenterMode } from '$lib/stores/presenter';

	// The keyframes the detour animates with (global, not scoped — ::view-transition
	// pseudo-elements belong to the document). Inert unless `transition` is on.
	import '$lib/styles/appendix-transition.css';

	export let title    = "";
	export let subtitle = "";
	export let rule     = true;
	export let align: 'left' | 'center' = 'left';
	export let returnText = 'RETURN';
	export let deckText   = 'DECK';
	export let transition = false;

	/** Inline style for the page root, applied last so it wins. */
	export let style: string = '';
	/** DOM id for the page root. */
	export let id: string = '';
	/** Extra class(es) for the page root. NOTE: a slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS (global.css / roles.css / a
	    :global(...) block) or a utility class. See AGENTS.md. */
	let klass: string = '';
	export { klass as class };

	const pages = getPages();

	// A view transition can only animate WITHIN one document, so an animated appendix has
	// to page client-side — and Monaco does not survive that. Which is why `transition`
	// arms the NavigationBar ONLY for a HIDDEN appendix, whose every link stays inside
	// the appendix or returns to its caller (both of them slides this deck's author chose
	// when they turned the animation on).
	//
	// An IN-FLOW appendix is different: it is part of the deck, so its NEXT leads into the
	// rest of the deck — slides that know nothing about any of this and may well render a
	// Monaco CodeBox. Arming the bar there would silently blank them. So its bar keeps the
	// deck's own paging (full loads), and only the way OUT — RETURN, ↑, Backspace, which
	// goes to the caller and nowhere else — animates.
	//
	// The path is read once, not reactively: a slide is a route, so it cannot become a
	// different slide while mounted, and setContext must happen during init anyway.
	const initialRun = appendixRun(pages, slidePathOf(get(page).url.pathname) ?? '');
	const viewTransitions = transition || getViewTransitions();
	if (transition && initialRun.length > 0) setViewTransitions(true);

	$: currentPath = slidePathOf($page.url.pathname) ?? '';

	// The caller, if the URL names one AND the deck actually contains it. The
	// membership test is the second lock (appendixCore's syntax check is the first):
	// an address that passes the pattern but names no slide in this deck would
	// navigate to a 404, so treat it as no address at all and fall back to the deck.
	//
	// `browser` guard: reading url.searchParams during PRERENDER is an error in SvelteKit,
	// and rightly so — a prerendered file is one file, so it cannot depend on a query string
	// that varies per visit. In the deck this never came up, because SlideDeck gates its slot
	// on `initialized` and no slide has ever been server-rendered. The HANDOUT renders slides
	// for real (routes/_handout/[deck].html), which is what surfaced it. At prerender there IS no
	// caller, so `null` is the honest answer and the exit falls back to the deck's first
	// slide; hydration then reads the real `?return=` and the way out is restored.
	$: returnTo = !browser
		? null
		: (() => {
				const target = readReturnParam($page.url.searchParams);
				return target && pages.some((p) => p.path === target) ? target : null;
			})();

	// The way out: back to the caller, or — lacking one — to the first slide of the
	// linear order (never this appendix, when the appendix is hidden from that order).
	$: deckHome = visiblePages(pages)[0]?.path;
	$: exitHref = returnHref(returnTo) ?? (deckHome ? `./${deckHome}` : '');

	// This appendix's chapter — the contiguous run of hidden slides it belongs to.
	// Empty when the slide is not hidden, i.e. an appendix sitting in the deck's
	// normal flow: then the deck's OWN navigation applies, and we only thread the
	// return address through it so paging on doesn't lose the way home.
	$: run = appendixRun(pages, currentPath);
	$: navigation = run.length
		? appendixNavigation(run, currentPath, exitHref, returnTo)
		: carryReturnThrough(getPageNavigation(pages, currentPath, './'), returnTo);

	// Which effect each edge of the bar performs. The NavigationBar picks its transition
	// from the LEAVING slide's pages.ts entry, which cannot know that the slide it is
	// leaving TO lies outside the appendix — so the appendix tells it: a step that stays
	// inside is sideways, a step off either end is the appendix lifting away.
	$: kinds = appendixKinds(run, currentPath);
	$: nextKind = transition ? kinds.next : null;
	$: prevKind = transition ? kinds.prev : null;

	// The RETURN control is shown when there is somewhere to return TO, and on any
	// hidden slide — which needs a way out even reached cold, being off the order.
	// An in-flow appendix nobody called is just a slide, and gets no extra control.
	$: showExit = Boolean(returnTo) || run.length > 0;
	$: exitLabel = returnTo ? returnText : deckText;

	// Paging strategy is the deck's, not ours — a View-Transition deck must animate
	// out of an appendix exactly as it animates between slides, so RETURN goes through
	// the same deckNav helper the NavigationBar uses. `back` because that is what
	// returning is. The `?present` flag is carried over for the same reason the
	// NavigationBar carries it: the presenter console must stay the console.
	function goBack() {
		if (!exitHref) return;
		const target = $presenterMode
			? exitHref + (exitHref.includes('?') ? '&' : '?') + 'present'
			: exitHref;
		// KIND_OUT, like every other way out — RETURN is a shortcut for the same gesture,
		// so it must not look like a different one.
		pageNavigate(target, { viewTransitions, kind: KIND_OUT, direction: 'back' });
	}

	// Two keys leave: ↑ and Backspace.
	//
	// ↑ because UP is where leaving goes — the same direction the animation travels, so
	// the key and the motion say one thing. (It costs nothing: ←/→ page the deck and ↑/↓
	// are otherwise unbound, so the vertical axis is free to mean "in and out of the
	// appendix". A caller binds ↓ to jump in — see slides/appendix-page.html.)
	//
	// Backspace as the plain "go back". NOT Escape: Escape is spoken for several times
	// over (it closes the TOC, deselects a Block, leaves Draw's isolation), and a key that
	// both dismisses a menu and navigates away is a key that will eventually navigate away
	// when someone meant to dismiss a menu.
	//
	// → and Space need no binding: they are the NavigationBar's own, and they return
	// simply because the run's last NEXT is the exit.
	function handleGlobalKeydown(event: KeyboardEvent) {
		if (event.key !== 'Backspace' && event.key !== 'ArrowUp') return;
		// Never steal the key from someone typing (a Draw label, a filter box).
		const el = event.target as HTMLElement | null;
		if (el && (el.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName))) return;
		event.preventDefault();
		goBack();
	}

	onMount(() => {
		if (browser) window.addEventListener('keydown', handleGlobalKeydown);
	});
	onDestroy(() => {
		if (browser) window.removeEventListener('keydown', handleGlobalKeydown);
	});
</script>

<!-- The page root IS the ContentPage, so the three pass-throughs go through it — an
     appendix's own root would be a second box. -->
<ContentPage {title} {subtitle} {rule} {align} {style} {id} class={klass}>
	<slot />
</ContentPage>

<!-- The deck's own bar, with the deck's own padding and baseline — an appendix pages
     like everything else, so it must not invent a second bar somewhere on the canvas.
     RETURN rides in the bar's slot, and it is deliberately NOT `chrome`: the muted
     chrome look is for the machinery a speaker already knows is there, and this is the
     one control on the slide that has to be findable at a glance. -->
<NavigationBar
	firstLink={navigation.first}
	prevLink={navigation.prev}
	nextLink={navigation.next}
	lastLink={navigation.last}
	{nextKind}
	{prevKind}
>
	{#if showExit}
		<CtrlBtn
			text={exitLabel}
			hoverText={returnTo ? `Return to ${returnTo}` : 'Back to the deck'}
			isDisabled={!exitHref}
			on:click={goBack}
		/>
	{/if}
</NavigationBar>
