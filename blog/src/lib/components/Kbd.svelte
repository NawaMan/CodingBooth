<!--
  Kbd — keyboard keys, drawn as keycaps.

  The shortcut you keep having to typeset on a tooling slide: `Ctrl+Shift+P`,
  `⌘K`, `Ctrl+K Ctrl+S`. Pure CSS, no deps. It renders semantic <kbd> elements,
  sized in `em`, so a keycap tracks whatever text it sits in — a heading, a
  paragraph, a table cell.

  Usage:

    <script>
      import Kbd from '$lib/components/Kbd.svelte';
    </script>

    <Kbd keys="Mod+Shift+P" />            <!- Ctrl+Shift+P, or ⇧⌘P on a Mac ->
    <Kbd keys="Ctrl+K Ctrl+S" />          <!- a sequence: chord, then chord ->
    <Kbd>Any</Kbd>                        <!- one cap, contents as written ->

  The spec is one string: whitespace separates CHORDS (press, release, press
  again), `+` separates the keys within one. `+` is also a key, so a `+` with
  nothing to its left is the plus cap — `Ctrl++` is Ctrl and Plus.

  `Mod` is the point of the component. It is the portable modifier: Ctrl on a PC,
  ⌘ on a Mac. Write the shortcut once and let the slide say it correctly to
  whoever is looking at it.

  Props:
    keys     — the shortcut spec. Omit it and the slot becomes a single keycap.
    platform — 'pc' (default) | 'mac' | 'auto'. Picks what `Mod` means and which
               legends the caps carry. 'auto' reads the VIEWER's platform, and is
               therefore client-only: SSR and Text artifacts render 'pc', which is
               deterministic. A deck demoing a Mac app should just say platform="mac".
    symbols  — Mac glyphs (⇧⌘P) instead of words (Shift+Cmd+P). Default true; it
               only bites on a Mac, since a PC keyboard prints words on its caps.
    join     — override what sits between the keys of one chord. Defaults to `+`,
               or nothing at all under Mac symbols, where `⇧+⌘+P` reads wrong.
    then     — the word between chords of a sequence (default "then"; '' for a gap).
    style    — extra inline CSS appended to the root.

  Colours come from roles.css (--kbd-*), so a theme reskins every keycap.

  Accessibility: under Mac symbols the glyphs are decorative — a screen reader
  saying "⌘" helps nobody — so the root carries the spelled-out shortcut as its
  aria-label and the caps go aria-hidden. Spelled-out caps need no such rescue
  and keep their <kbd> semantics intact.
-->
<script lang="ts">
	import { onMount } from 'svelte';
	import { chordJoiner, detectPlatform, parseKeys, type Platform } from '$lib/utils/kbdCore';

	/** The shortcut spec: chords separated by whitespace, keys by `+`. */
	export let keys: string = '';
	/** Which keyboard to draw. 'auto' resolves on mount (SSR/text render 'pc'). */
	export let platform: Platform | 'auto' = 'pc';
	/** Use the Mac glyph set (⇧⌘P) rather than words. No effect on a PC. */
	export let symbols: boolean = true;
	/** What separates the keys of one chord; `null` → the platform's own joiner. */
	export let join: string | null = null;
	/** The word between chords of a sequence; `''` leaves just the gap. */
	export let then: string = 'then';
	/** Extra inline CSS appended to the root. */
	export let style: string = '';
	/** DOM id for the root element. */
	export let id: string = '';
	/** Extra class(es) for the root element. NOTE: a slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS (global.css / roles.css / a
	    :global(...) block) or a utility class. See AGENTS.md. */
	let klass: string = '';
	export { klass as class };

	// `auto` can only be answered by a browser, and answering it wrong on the
	// server would bake a Mac's ⌘ into a PC's prerendered page. So the server (and
	// any Text artifact built from it) sees 'pc' and the real platform arrives on
	// mount — the same deliberate degradation WebSite's lazy mount makes.
	let detected: Platform = 'pc';
	onMount(() => {
		if (platform === 'auto') detected = detectPlatform(globalThis.navigator);
	});

	$: resolved = platform === 'auto' ? detected : platform === 'mac' ? 'mac' : 'pc';
	$: chords = parseKeys(keys, resolved, symbols);
	$: joiner = join ?? chordJoiner(resolved, symbols);

	// Glyph caps say nothing out loud, so the root speaks the shortcut in words
	// instead. Word caps already read correctly, and wrapping them in an aria-label
	// would only mute the <kbd>s a screen reader wants to announce.
	$: glyphs = resolved === 'mac' && symbols;
	$: spoken = glyphs
		? parseKeys(keys, resolved, false)
				.map((chord) => chord.join(' '))
				.join(`, ${then || 'then'} `)
		: '';
</script>

{#if chords.length}
	<span class="kbd {klass}" id={id || undefined} {style} aria-label={glyphs ? spoken : undefined}>
		{#each chords as chord, i}
			{#if i > 0 && then}<span class="then" aria-hidden="true">{then}</span>{/if}
			<!-- Nested <kbd> is the HTML spec's own way to spell a chord: an outer kbd
			     for the input, one inner kbd per key pressed. -->
			<kbd class="chord" aria-hidden={glyphs ? 'true' : undefined}>
				{#each chord as cap, j}
					{#if j > 0 && joiner}<span class="join">{joiner}</span>{/if}
					<kbd class="cap">{cap}</kbd>
				{/each}
			</kbd>
		{/each}
	</span>
{:else if $$slots.default}
	<!-- No spec: the slot is one cap, rendered exactly as the author wrote it. -->
	<span class="kbd {klass}" id={id || undefined} {style}>
		<kbd class="chord"><kbd class="cap"><slot /></kbd></kbd>
	</span>
{/if}

<style>
	.kbd {
		display: inline-flex;
		align-items: center;
		gap: 0.4em;
		vertical-align: middle;
	}

	.chord {
		display: inline-flex;
		align-items: center;
		gap: 0.12em;
		/* A <kbd> defaults to monospace; the chord is a wrapper, not a legend. */
		font-family: inherit;
	}

	.cap {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		box-sizing: border-box;
		/* A single legend sits on a square-ish cap; a word grows its own. */
		min-width: 1.9em;
		height: 1.9em;
		padding: 0 0.45em;
		font-family: inherit;
		font-size: 0.8em;
		font-weight: 600;
		line-height: 1;
		white-space: nowrap;
		color: var(--kbd-fg, #c0f1ff);
		background: var(--kbd-bg, #1e1e1e);
		/* Softened from the line token so the cap reads as a raised key on any
		   surface without the border knowing that surface's colour — Callout's trick. */
		border: 1px solid color-mix(in srgb, var(--kbd-border, #cccccc) 45%, transparent);
		border-radius: 0.35em;
		/* The lip: a keycap is a key seen from above, so its bottom edge is thicker
		   and it casts no blur. One inset line, no shadow — this must stay crisp at
		   whatever scale SlideDeck transforms the canvas to. */
		box-shadow: inset 0 -0.18em 0 color-mix(in srgb, var(--kbd-border, #cccccc) 18%, transparent);
	}

	/* Between the keys of one chord, and between the chords of a sequence. Both are
	   punctuation, not legends: dimmed, and never boxed. */
	.join,
	.then {
		color: var(--kbd-sep-fg, #c0f1ff);
		opacity: 0.55;
		font-size: 0.8em;
		line-height: 1;
	}
	.then {
		font-style: italic;
	}
</style>
