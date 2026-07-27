<!--
  Callout — a semantic admonition box (info / tip / warn / danger).

  A themed panel that flags a passage as informational, a tip, a warning, or a
  danger. Distinct from Box (a zooming modal) and Hint (a faint bottom cue): a
  Callout sits inline in the slide flow with a coloured left rule, a tinted
  background, and an icon badge + title. Each `kind` is driven by a single accent
  role token (roles.css: --callout-<kind>-accent); the box tints its own
  background and border from that accent via color-mix, so a theme only needs to
  move the accent to reskin every callout.

  Usage:

    <script>
      import Callout from '$lib/components/Callout.svelte';
    </script>

    <Callout kind="warn" title="Gotcha">
      Client-side navigation blanks Monaco — use CssSnippet in SPA decks.
    </Callout>

  Props:
    kind   — 'info' | 'tip' | 'warn' | 'danger'  (default 'info')
    title  — heading text. Omit to use the kind's default label
             ("Info" / "Tip" / "Warning" / "Danger"); pass "" to hide the title.
    icon   — override the badge glyph (default is per-kind).
    style  — extra inline CSS appended to the box (e.g. spacing tweaks per slide).

  In normal slide flow the callout hugs its content height. Wrap it in a <Block>
  to pin/size it — Block fills its content by default, so the callout stretches to
  the box and a resize rubber-bands it.
-->
<script lang="ts">
	type Kind = 'info' | 'tip' | 'warn' | 'danger';

	/** Which admonition this is; picks accent, default title and glyph. */
	export let kind: Kind = 'info';
	/** Heading text; `null` → the kind's default label, `''` → no heading. */
	export let title: string | null = null;
	/** Override the badge glyph; `null` → the kind's default. */
	export let icon: string | null = null;
	/** Extra inline CSS appended to the box. */
	export let style: string = '';
	/** DOM id for the root element. */
	export let id: string = '';
	/** Extra class(es) for the root element. NOTE: a slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS (global.css / roles.css / a
	    :global(...) block) or a utility class. See AGENTS.md. */
	let klass: string = '';
	export { klass as class };

	const KINDS: Record<Kind, { label: string; glyph: string; accent: string }> = {
		info:   { label: 'Info',    glyph: 'i', accent: 'var(--callout-info-accent, #2980B9)'   },
		tip:    { label: 'Tip',     glyph: '✦', accent: 'var(--callout-tip-accent, #00B356)'    },
		warn:   { label: 'Warning', glyph: '!', accent: 'var(--callout-warn-accent, #F0A33E)'   },
		danger: { label: 'Danger',  glyph: '✕', accent: 'var(--callout-danger-accent, #E5484D)' },
	};

	$: k            = KINDS[kind] ?? KINDS.info;
	$: displayTitle = title === null ? k.label : title;
	$: displayIcon  = icon  === null ? k.glyph : icon;
</script>

<div class="callout {klass}" id={id || undefined} style="--callout-accent: {k.accent}; {style}">
	<div class="badge" aria-hidden="true">{displayIcon}</div>
	<div class="body">
		{#if displayTitle}
			<div class="title">{displayTitle}</div>
		{/if}
		<div class="content"><slot /></div>
	</div>
</div>

<style>
	.callout {
		display: flex;
		align-items: flex-start;
		gap: 0.75em;
		box-sizing: border-box;
		/* Tint the surface and border from the single per-kind accent, so one
		   token reskins the whole box. transparent second stop = works on any
		   deck surface without knowing its colour. */
		background: color-mix(in srgb, var(--callout-accent) 14%, transparent);
		border: 1px solid color-mix(in srgb, var(--callout-accent) 45%, transparent);
		border-left: 6px solid var(--callout-accent);
		border-radius: 6px;
		padding: 0.7em 1em;
	}

	.badge {
		flex: 0 0 auto;
		width: 1.5em;
		height: 1.5em;
		border-radius: 50%;
		background: var(--callout-accent);
		color: var(--on-accent, #FFFFFF);
		font-weight: bold;
		font-style: normal;
		line-height: 1.5em;
		text-align: center;
		/* nudge the glyph optically centred */
		font-size: 1em;
	}

	.body {
		flex: 1 1 auto;
		min-width: 0;
	}

	.title {
		font-weight: bold;
		color: var(--callout-accent);
		line-height: 1.2em;
		margin-bottom: 0.25em;
	}

	/* Title present → content is the secondary line; titleless → content carries
	   the badge's vertical rhythm. */
	.content {
		line-height: 1.35em;
	}

	/* Tighten stray margins from slotted <p>/<ul> so the box stays compact. */
	.content :global(:first-child) { margin-top: 0; }
	.content :global(:last-child)  { margin-bottom: 0; }
</style>
