<!--
  Quote — a pull-quote / blockquote with attribution and avatar.

  A large quotation with an optional decorative quote glyph, a left accent rule,
  and a footer carrying the speaker: an avatar (image, or auto initials when no
  image is given), their name, and a role/source line. Pure CSS, no deps; the
  Tier-3 companion to Stat and Callout on a "what people say" / testimonial slide.

  Every colour is a roles.css token (--quote-*), so a theme reskins every Quote by
  moving those. The decorative mark and the left rule pull the accent; the avatar
  falls back to initials tinted from the same accent, so a quote needs no image to
  look finished.

  Usage:

    <script>
      import Quote from '$lib/components/Quote.svelte';
      import avatar from './grace.jpg';   // import assets so a base path survives
    </script>

    <Quote
      text="Premature optimization is the root of all evil."
      author="Donald Knuth" role="The Art of Computer Programming" />

    <Quote author="Grace Hopper" role="Rear Admiral, US Navy" {avatar}>
      The most dangerous phrase is: we've always done it this way.
    </Quote>

  Props:
    text    — the quotation (string). Omit to use the default slot instead.
    author  — who said it, shown in the footer. Also seeds the initials avatar.
    role    — their title or the source, a dim secondary line under the author.
    avatar  — image URL (import it). Omitted → an initials disc from `author`.
    align   — 'left' (default) or 'center'. Center drops the left rule.
    mark    — show the big decorative opening quote glyph (default true).
    rule    — the left accent rule (default true; ignored when align='center').
    border  — draw a border around the quote (a "card").
    radius  — corner radius, any CSS length (default '14px'). Rounds border/bg.
    background — figure background, any CSS value (colour, gradient…). '' → none.
    style   — extra inline CSS appended to the figure.

  A border or a background makes it a padded card; the mark then sits inside the
  top of the frame instead of tucking above bare text.

  In normal flow the figure hugs its content. Wrap it in a <Block> to pin/size it —
  Block fills its content by default, so the quote stretches to the box.
-->
<script lang="ts">
	/** The quotation text; `''` falls through to the default slot. */
	export let text: string = '';
	/** Who said it — shown in the footer and used for the initials avatar. */
	export let author: string = '';
	/** Their title or the source; a dim line under the author. */
	export let role: string = '';
	/** Avatar image URL (import it). Omit for an initials disc from `author`. */
	export let avatar: string = '';
	/** Text/footer alignment. 'center' also drops the left rule. */
	export let align: 'left' | 'center' = 'left';
	/** Show the big decorative opening-quote glyph. */
	export let mark: boolean = true;
	/** Draw the left accent rule (ignored when centered). */
	export let rule: boolean = true;
	/** Draw a border around the quote (a "card"). The mark straddles the top edge. */
	export let border: boolean = false;
	/** Corner radius, any CSS length. Rounds the border and/or background. */
	export let radius: string = '14px';
	/** Figure background, any CSS value (colour, gradient…). '' → transparent. */
	export let background: string = '';
	/** Extra inline CSS appended to the figure. */
	export let style: string = '';
	/** DOM id for the root element. */
	export let id: string = '';
	/** Extra class(es) for the root element. NOTE: a slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS (global.css / roles.css / a
	    :global(...) block) or a utility class. See AGENTS.md. */
	let klass: string = '';
	export { klass as class };

	// Unknown align falls back to left rather than emitting a class that matches
	// nothing — the same discipline ContentPage's `align` follows.
	$: resolvedAlign = align === 'center' ? 'center' : 'left';

	// Initials for the fallback disc: first letters of up to two words, upper-cased.
	// Total by construction — an empty/space-only author yields '' and the disc is
	// simply not rendered, never a blank circle.
	$: initials = author
		.trim()
		.split(/\s+/)
		.filter(Boolean)
		.slice(0, 2)
		.map((w) => w[0]!.toUpperCase())
		.join('');

	$: hasFooter = Boolean(author || role || avatar);

	// A border or a background turns the quote into a padded "card"; the mark then
	// sits inside the top of the frame rather than tucking above bare text.
	$: framed = border || Boolean(background);
	$: frameVars =
		`--quote-radius: ${radius};` + (background ? ` --quote-bg: ${background};` : '');
</script>

<figure
	class="quote align-{resolvedAlign} {klass}"
	class:has-rule={rule}
	class:framed
	class:bordered={border}
	id={id || undefined}
	style="{frameVars} {style}"
>
	{#if mark}
		<span class="mark" aria-hidden="true">&ldquo;</span>
	{/if}

	<blockquote class="body">
		{#if text}<p>{text}</p>{:else}<slot />{/if}
	</blockquote>

	{#if hasFooter}
		<figcaption class="cite">
			{#if avatar}
				<img class="avatar" src={avatar} alt={author || ''} />
			{:else if initials}
				<span class="avatar disc" aria-hidden="true">{initials}</span>
			{/if}
			{#if author || role}
				<span class="who">
					{#if author}<span class="author">{author}</span>{/if}
					{#if role}<span class="role">{role}</span>{/if}
				</span>
			{/if}
		</figcaption>
	{/if}
</figure>

<style>
	.quote {
		display: flex;
		flex-direction: column;
		box-sizing: border-box;
		min-width: 0;
		margin: 0;
		color: var(--quote-fg, #c0f1ff);
	}

	/* A border and/or background turns the quote into a padded card. */
	.framed {
		padding: 1.2em 1.4em;
		border-radius: var(--quote-radius, 14px);
		background: var(--quote-bg, transparent);
	}
	.bordered {
		/* Softened from the line token so the frame reads on any surface without
		   knowing its colour — the same color-mix trick Callout/Kbd/the avatar use. */
		border: 1px solid color-mix(in srgb, var(--quote-border, #cccccc) 55%, transparent);
	}

	/* The decorative glyph is a serif lead-in tucked above the text; line-height 0
	   keeps it from adding a tall empty row, and the negative margin pulls the
	   quotation up under its hook. Purely ornamental, so aria-hidden. */
	.mark {
		font-family: Georgia, 'Times New Roman', serif;
		font-size: 3.4em;
		line-height: 0;
		height: 0.5em;
		color: var(--quote-mark, #2980b9);
		opacity: 0.55;
		user-select: none;
	}

	/* Framed: the mark sits fully inside the top of the card (line-height 1, in
	   flow), rather than the tucked-above-text watermark the bare variant uses. */
	.framed .mark {
		height: auto;
		line-height: 1;
		font-size: 2.6em;
		margin-bottom: 0.05em;
	}

	.body {
		margin: 0;
		font-size: 1.5em;
		line-height: 1.4;
		font-weight: 500;
	}
	.body :global(p:first-child) { margin-top: 0; }
	.body :global(p:last-child)  { margin-bottom: 0; }

	/* The left rule is a classic blockquote bar. Only meaningful left-aligned, so
	   the centered variant strips it below. */
	.has-rule .body {
		border-left: 4px solid var(--quote-rule, #2980b9);
		padding-left: 0.7em;
	}

	.cite {
		display: flex;
		align-items: center;
		gap: 0.6em;
		margin-top: 0.9em;
	}

	.avatar {
		flex: 0 0 auto;
		width: 2.6em;
		height: 2.6em;
		border-radius: 50%;
		object-fit: cover;
		/* Softened from the line token so the ring reads on any surface without
		   knowing its colour — the same color-mix trick Callout/Kbd use. */
		border: 2px solid color-mix(in srgb, var(--quote-avatar-ring, #cccccc) 55%, transparent);
	}
	/* Initials fallback: an accent-tinted disc, so a quote with no image still
	   looks finished rather than leaving an empty gap. */
	.disc {
		display: flex;
		align-items: center;
		justify-content: center;
		font-size: 0.9em;
		font-weight: 700;
		line-height: 1;
		color: var(--quote-mark, #2980b9);
		background: color-mix(in srgb, var(--quote-mark, #2980b9) 18%, transparent);
		border-color: color-mix(in srgb, var(--quote-mark, #2980b9) 45%, transparent);
	}

	.who {
		display: flex;
		flex-direction: column;
		min-width: 0;
	}
	.author {
		font-weight: 700;
		color: var(--quote-author-fg, #c0f1ff);
	}
	/* Same ink as the author, dimmed — so it tracks the theme instead of needing a
	   separate (theme-fragile) muted token, like Stat's label. */
	.role {
		font-size: 0.82em;
		color: var(--quote-cite-fg, #c0f1ff);
		opacity: 0.62;
	}

	/* Centered: text and footer centre, and the left rule is dropped (a centred
	   bar reads as a divider, not a quote). */
	.align-center .body {
		text-align: center;
	}
	.align-center.has-rule .body {
		border-left: none;
		padding-left: 0;
	}
	.align-center .mark {
		text-align: center;
	}
	.align-center .cite {
		justify-content: center;
	}
	.align-center .who {
		text-align: left;
	}
</style>
