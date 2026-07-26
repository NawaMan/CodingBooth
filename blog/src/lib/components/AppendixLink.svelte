<!--
  AppendixLink — the call site of an appendix. Jumps into a hidden slide and
  stamps the CURRENT slide's name into the link as the return address, so the
  appendix knows where to come back to.

  Usage:

    <script>
      import AppendixLink from '$lib/components/AppendixLink.svelte';
    </script>

    <p>
      The heap is compacted on the way out —
      <AppendixLink to="appendix-gc.html">how the GC actually marks</AppendixLink>.
    </p>

  which renders

    <a href="./appendix-gc.html?return=heap-layout.html">how the GC actually marks</a>

  The whole trick is that the author never types the return address: it is the
  slide the link is ON, read from the URL. So the same appendix can be called
  from three different slides and returns to whichever one asked — that is what
  makes it a function call rather than a destination.

  It is a plain <a> with a real href, computed during render rather than on click,
  so it works with JS off and shows its destination in the status bar. (It is not
  what gets the appendix PRERENDERED, though — every static route is a prerender
  entry, so a hidden slide is built whether or not anything links to it. Nor could
  it be: SlideDeck gates SSR, so the built deck HTML holds no slide markup for a
  crawler to find this link in.)

  Props:
    to     — the appendix's slide file name, e.g. "appendix-gc.html". This is
             AUTHOR input, so it is passed through as written; the `?return=` it
             produces is what gets validated, on the way back in (appendixCore).
    button — render as a prominent CtrlBtn instead of an inline link (default
             false). For "Backup demo" as an affordance rather than as prose.
    transition — animate the jump: we travel DOWN to the appendix (so, as when
             scrolling down a page, the deck rises out of view and the appendix comes
             up from below), and the matching AppendixPage travels back up on the way
             out. Default false, and it is an opt-in for a reason: an animated jump
             has to be a CLIENT-SIDE navigation (the View Transitions API can only
             animate within one document), and Monaco does not survive one. So a
             deck that turns this on must use SourceView/QuickCode on the slides it
             animates between, not ViewSource/Code/CodeBox — see SourceView.svelte
             and the memory "monaco-breaks-on-spa-nav". Set it on BOTH sides (here
             and on the AppendixPage) so the return animates too.
-->
<script lang="ts">
	import CtrlBtn from '$lib/components/CtrlBtn.svelte';

	import { page } from '$app/stores';
	import { appendixHref, slidePathOf, KIND_IN } from '$lib/utils/appendixCore';
	import { navigate as pageNavigate } from '$lib/utils/deckNav';

	// The keyframes the jump animates with. A plain global stylesheet rather than a
	// scoped Svelte style block: the ::view-transition pseudo-elements belong to the
	// document, not to any component. (Do not write that tag name literally in a
	// comment here — svelte-check's parser reads it as a real tag and gives up on the
	// file, even though the compiler is perfectly happy.)
	import '$lib/styles/appendix-transition.css';

	/** The appendix slide to jump into, e.g. "appendix-gc.html". */
	export let to: string;
	/** Render as a button rather than an inline text link. */
	export let button = false;
	/** Button label (ignored unless `button`); defaults to the slot's own text via
	    a plain fallback, since a CtrlBtn takes its label as a prop, not a slot. */
	export let text = 'APPENDIX';
	/** Animate the jump in (and let the appendix animate back out). */
	export let transition = false;

	// The return address is the slide we are ON. `$page` is populated during SSR too,
	// so the href is in the prerendered markup rather than appearing on hydration.
	$: from = slidePathOf($page.url.pathname);
	$: href = appendixHref(to, from);

	// Without `transition` this handler does nothing and the browser just follows the
	// href — a full page load, like the rest of a normal deck. With it, we take the
	// navigation over so it can be wrapped in a view transition; the href stays exactly
	// what it was, so middle-click, "open in new tab" and JS-off all still work.
	function onClick(event: MouseEvent) {
		if (!transition) return;
		// Leave the browser's own gestures alone: a modified click means "somewhere else".
		if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || event.button !== 0) return;
		event.preventDefault();
		pageNavigate(href, { viewTransitions: true, kind: KIND_IN, direction: 'forward' });
	}
</script>

{#if button}
	<a {href} class="appendix-link button" on:click={onClick}>
		<CtrlBtn {text} hoverText={`Appendix: ${to}`} />
	</a>
{:else}
	<a {href} class="appendix-link" on:click={onClick}><slot /></a>
{/if}

<style>
	/* Reads as a link into a side page rather than as deck navigation: the accent
	   colour of the deck, with a dashed underline saying "this is a detour, and you
	   will be brought back". The var() fallbacks ARE the main deck's dark theme
	   (see roles.css) — the `slides` deck sets no theme class. */
	.appendix-link {
		color: var(--appendix-link-fg, #F0A33E);
		text-decoration: underline;
		text-decoration-style: dashed;
		text-underline-offset: 0.18em;
		cursor: pointer;
	}
	/* Hover brightens the one token rather than reading a second one, so a theme
	   that moves --appendix-link-fg gets a matching hover for free. */
	.appendix-link:hover {
		color: color-mix(in srgb, var(--appendix-link-fg, #F0A33E) 75%, white);
	}
	/* As a button the CtrlBtn owns the look entirely. */
	.appendix-link.button {
		text-decoration: none;
		color: inherit;
	}
</style>
