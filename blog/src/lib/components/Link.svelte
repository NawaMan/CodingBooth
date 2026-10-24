<!--
  Link — the one anchor every slide and Text should use.

  Every link in the deck looks the SAME — one colour (--link-fg), one thin dashed
  underline — and a trailing GLYPH says which kind it is. Link owns two of the three;
  AppendixLink owns the middle one:

    (no glyph)  an ordinary move inside the site — the unmarked, common case
    ↩           a detour you will be brought back from  (AppendixLink)
    ↗           this leaves the site

  One look plus one glyph, rather than a colour and a stroke per kind: the links read
  as one family at a glance, and the glyph is what you look at when you want to know
  where a particular one goes.

  Usage:

    <script>
      import Link from '$lib/components/Link.svelte';
    </script>

    <Link href="./slide-pages/title.html">Open the Slide Pages reference →</Link>
    <Link href="https://codingbooth.io/">codingbooth.io</Link>

  The second one classifies itself: external tone, a trailing ↗, `target="_blank"`
  and `rel="noopener noreferrer"`, none of which the author typed. That is the point
  of the component — the promise cannot drift from the destination.

  Props:
    href    — the destination, exactly as an <a> would take it. NOT base-path aware:
              a root-relative "/x" under a subpath deploy needs `{base}` in front,
              same as a hand-written anchor (AGENTS.md Rule 4). Relative hrefs, which
              is what slides normally write, need nothing.
    kind    — 'auto' (default) | 'internal' | 'external'. `auto` reads the href;
              set it explicitly when the URL lies (a redirector that lands back on
              this site, a docs domain that is really "ours").
    newTab  — force the window: true opens away, false keeps it here. Default null
              = follow the kind (external opens away, internal does not). Forcing it
              true also flips the LOOK to external, because it is: the reader ends
              up somewhere else. That is how an internal-but-leaving link — a
              handout, a print view — gets the "you are leaving" stroke.
    glyph   — show the trailing kind glyph (default true). Turn it off where it
              would fight the layout — but note that with one shared colour and
              stroke, the glyph is the ONLY thing distinguishing an external link
              from an internal one, so dropping it drops the distinction.
    icon    — override the glyph outright (e.g. "⇱"). Empty string hides it, same
              as glyph={false}.
    origin  — treat http(s) URLs on this origin as internal. Left null on purpose by
              default: at prerender there is no real origin to compare against (see
              linkCore), so an absolute URL is external unless a caller knows better.
    style / id / class — the standard three. `style` is applied last, so it wins.

  All logic lives in `$lib/utils/linkCore.ts`, so it is pure and unit-tested and this
  file is markup. Declarative throughout — no onMount, no browser API — so it renders
  identically at prerender, which is what the handout and the SSR tests need.
-->
<script lang="ts">
	import {
		resolveKind,
		linkTarget,
		linkRel,
		linkTone,
		linkGlyph,
		type KindProp
	} from '$lib/utils/linkCore';

	/** Destination, exactly as an <a> would take it. */
	export let href: string = '';
	/** 'auto' classifies from the href; 'internal'/'external' override it. */
	export let kind: KindProp = 'auto';
	/** Force the window; null follows the kind. */
	export let newTab: boolean | null = null;
	/** Show the trailing kind glyph. */
	export let glyph: boolean = true;
	/** Override the glyph outright; null uses the kind's own. */
	export let icon: string | null = null;
	/** Origin that counts as "this site" for absolute http(s) URLs. */
	export let origin: string | null = null;
	/** Inline style for the root element, applied last so it wins. */
	export let style: string = '';
	/** DOM id for the root element. */
	export let id: string = '';
	/** Extra class(es) for the root element. NOTE: a slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS (global.css / roles.css / a
	    :global(...) block) or a utility class. See AGENTS.md. */
	let klass: string = '';
	export { klass as class };

	$: resolved = resolveKind(kind, href, origin);
	$: tone     = linkTone(resolved, newTab);
	$: mark     = !glyph ? '' : icon === null ? linkGlyph(tone) : icon;
</script>

<a
	class="gp-link {tone} {klass}"
	{href}
	target={linkTarget(resolved, newTab)}
	rel={linkRel(resolved, newTab)}
	id={id || undefined}
	style={style || undefined}
	on:click
><slot />{#if mark}<span class="marker" aria-hidden="true">{mark}</span>{/if}</a>

<style>
	/* ONE look for every link, internal or external — the trailing glyph is what
	   distinguishes them. AppendixLink repeats these five declarations verbatim so
	   the family holds; keep the two in step if either moves.

	   The var() fallbacks ARE the main deck's dark theme (see roles.css) — the
	   `slides` and `references` decks set no theme class, so every value here has to
	   resolve, unthemed, to the dark look. #58A6FF sits at ~7:1 against the #181818
	   canvas; going much darker drops under the 4.5:1 body-text floor, which is what
	   the original #1E6FB0 (3.3:1) did. */
	.gp-link {
		color: var(--link-fg, #58A6FF);
		text-decoration: underline;
		text-decoration-style: dashed;
		text-decoration-thickness: 1px;
		text-underline-offset: 0.18em;
		cursor: pointer;
	}

	/* Hover brightens the one token rather than reading a second one, so a theme that
	   moves --link-fg gets a matching hover for free (AppendixLink does the same). */
	.gp-link:hover {
		color: color-mix(in srgb, var(--link-fg, #58A6FF) 75%, white);
	}

	/* A theme MAY still pull the leaving links apart by hue, but it has to ask: the
	   token defaults to the shared link colour, so out of the box every link matches
	   and only the glyph differs. */
	.gp-link.external {
		color: var(--link-external-fg, var(--link-fg, #58A6FF));
	}

	.gp-link.external:hover {
		color: color-mix(in srgb, var(--link-external-fg, var(--link-fg, #58A6FF)) 75%, white);
	}

	/* inline-block is load-bearing, not cosmetic: it stops the anchor's underline
	   propagating into the glyph, so the ↗ sits beside the rule rather than on it. */
	.marker {
		display: inline-block;
		margin-left: 0.15em;
		font-size: 0.85em;
	}
</style>
