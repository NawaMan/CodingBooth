<!--
  ContentPage — the template behind most slides: a header, then your content.

  The header has three parts — title, subtitle and the rule beneath them — and
  EACH IS INDEPENDENTLY OMITTABLE. Whatever survives closes the gap: drop the
  subtitle and the rule rides up under the title; drop all three and the content
  starts at the top of the canvas. (Previously all three were mandatory — an
  empty `title`/`subtitle` still rendered its box, and the rule was welded to the
  subtitle as `.subtitle::after`, so a subtitle-less slide kept the empty span's
  margins and the rule sat too low. The rule is now its own element.)

  Usage:

    <script>
      import ContentPage from '$lib/templates/ContentPage.svelte';
    </script>

    <ContentPage title="My Title" subtitle="Optional">
      <p>Any HTML or Svelte components here.</p>
    </ContentPage>

  Props:
    title    — heading text; '' (default) drops the <h1> entirely.
    subtitle — line under the title; '' (default) drops it, pulling the rule up.
    rule     — the hairline under the header (default true). `rule={false}`
               removes it. With no title, no subtitle and no rule there is no
               header at all and the content starts at the top.
    align    — 'left' (default) | 'center'. Centers the title and subtitle; the
               rule spans the header either way, so it needs no alignment.

  The FIRST/PREV/CONTINUE/NEXT/LAST pager is no longer this template's concern — it
  lives once in SlideDeck's ControlBar (the bottom-centre chrome bar) for every slide.
  A slide outside the linear order that needs its own way out (an appendix) still
  brings one — see templates/AppendixPage.svelte.

  The content area keeps its own styling (justified, slightly smaller than the
  header) regardless of `align` — `align` is the HEADER's alignment.

  Theming: sizes, spacing and the rule's weight/colour come from role tokens
  (roles.css). The `var(--token, fallback)` fallbacks below ARE the main deck's
  look — a deck without `.gp-deck`/a theme resolves to exactly these, so they
  must stay the dark-default (light-on-dark) values:

    --page-title-fg      title colour            (#F0A33E)
    --page-title-size    title font-size         (2.5em)
    --page-subtitle-fg   subtitle colour         (currentColor)
    --page-subtitle-size subtitle font-size      (1.2em)
    --page-title-gap     title → subtitle gap    (0.5em)
    --page-rule-gap      header → rule gap       (15px)
    --page-rule-weight   rule thickness          (4.5px)
    --subtitle-rule      rule colour             (#F0F8FF)
    --page-content-gap   header → content gap    (1em)
-->
<script lang="ts">
	/** Heading text; '' drops the <h1>. */
	export let title = "";
	/** Line under the title; '' drops it and pulls the rule up. */
	export let subtitle = "";
	/** The hairline under the header; false removes it. */
	export let rule = true;
	/** Header alignment: 'left' (default) or 'center'. */
	export let align: 'left' | 'center' = 'left';

	/** Inline style for the page root, applied last so it wins. */
	export let style: string = '';
	/** DOM id for the page root. */
	export let id: string = '';
	/** Extra class(es) for the page root. NOTE: a slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS (global.css / roles.css / a
	    :global(...) block) or a utility class. See AGENTS.md. */
	let klass: string = '';
	export { klass as class };

	// An unknown `align` falls back to the default rather than emitting a class
	// that matches nothing (which would silently render as left anyway, but via
	// a lie in the markup).
	$: centered = align === 'center';
	// Nothing to show → no header element, so no margins of its own survive and
	// the content starts at the top of the canvas.
	$: hasHeader = Boolean(title) || Boolean(subtitle) || rule;
</script>

<div class="page {klass}" id={id || undefined} style={style || undefined}>
    {#if hasHeader}
        <header class="header" class:centered>
            {#if title}<h1>{title}</h1>{/if}
            {#if subtitle}<span class="subtitle">{subtitle}</span>{/if}
            {#if rule}<div class="rule" aria-hidden="true"></div>{/if}
        </header>
    {/if}
    <div class="content">
        <slot />
    </div>
</div>

<style>
    .page {
        /* cosmetic */
        width: 100%;
        height: 100%;
        padding-left: 2em;
        padding-right: 2em;
    }
    .header.centered {
        text-align: center;
    }
    .page h1 {
        font-size: var(--page-title-size, 2.5em);
        margin-bottom: 0em;
        font-family: 'Playfair Display Bolds', 'Cormorant Garamond', serif;
        color: var(--page-title-fg, #F0A33E);
    }
    .page .subtitle {
        /* cosmetic */
        display: block;
        margin-left: 0em;
        margin-top: var(--page-title-gap, 0.5em);
        font-size: var(--page-subtitle-size, 1.2em);
        /* currentColor, not `inherit`: a CSS-wide keyword arriving via var()
           substitution is invalid at computed-value time (it happens to fall
           back to the inherited colour, but only by accident of `color` being
           an inherited property). currentColor says the same thing outright. */
        color: var(--page-subtitle-fg, currentColor);
    }

    /* Its own element, not `.subtitle::after` — so the subtitle can go away
       without taking the rule with it, and the rule can go away on its own.
       Adjacent-sibling margins collapse, so the gap above it is the same
       whether it follows the subtitle, the title, or nothing. */
    .page .rule {
        margin-top: var(--page-rule-gap, 15px);
        border-bottom: var(--page-rule-weight, 4.5px) solid var(--subtitle-rule, #F0F8FF);
    }
    .page .content {
        /* cosmetic */
        margin-top: var(--page-content-gap, 1em);
        margin-bottom: 2em;
        font-size: 1.28em;   /* 80% of the former 1.6em default */
        line-height: 1.1em;
        text-align: justify;
        text-justify: inter-word;
    }
</style>
