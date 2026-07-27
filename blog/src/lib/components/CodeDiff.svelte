<!--
  CodeDiff — a before/after code block with added/removed line styling.

  The gap this closes: a slide can show a snippet (QuickCode) or a full editor
  (Code/CodeBox), but not a *change* — the "here's the line we added, here's the one
  we removed" that a tech talk lives on. CodeDiff renders that: each line carries a
  +/− gutter, a green/red wash, and optional old/new line numbers.

  It is QuickCode-family, NOT a Code/Monaco variant — the same call Terminal made.
  Monaco is a CDN-loaded language service that re-bootstraps per mount (and renders
  blank after this deck's client-side goto — see project memory monaco-breaks-on-spa-nav);
  a diff needs none of that. It wants per-line control and Shiki's token colours, which
  is exactly what `highlightToLines` hands back. So the component owns its own row
  markup and only borrows Shiki's colours — plain DOM + CSS, no deps.

  Two authoring paths, both landing on the same DiffLine[] (see codeDiffCore):

    1. Two versions — the diff is computed for you (LCS over lines):
         CodeDiff  before={oldSrc}  after={newSrc}  lang="javascript"
    2. A git-style +/-/space-prefixed block — you say exactly what changed:
         CodeDiff  lang="python"  lineNumbers  diff="…the block…"
       (the demo slide codediff-component.html shows a real one).

  `lang` is a Shiki language id (javascript / python / go / bash / svelte / css —
  see highlight.ts). Like QuickCode it renders plain text immediately, then swaps in
  the token colours once Shiki resolves, so it is SSR-safe and never flashes.

  To reveal the change progressively, wrap it in Steps / Fragment — a CodeDiff is a
  static block, so the deck's existing reveal machinery drives it; it grows no stepping
  logic of its own.
-->
<script lang="ts">
	import { onMount } from 'svelte';
	import { highlightToLines, type CodeToken } from '$lib/utils/highlight';
	import { diffLines, parseDiff, diffStats, signOf, type DiffLine } from '$lib/utils/codeDiffCore';

	/** Old version of the file. Pair with `after` to have the diff computed. */
	export let before: string | undefined = undefined;
	/** New version of the file. Pair with `before`. */
	export let after: string | undefined = undefined;
	/** A git-style `+`/`-`/space-prefixed block, for exact control over the diff. */
	export let diff: string | undefined = undefined;
	/** A plain snippet with no diff at all (every line is context) — the degrade case. */
	export let code: string | undefined = undefined;
	/** Shiki language id for the code. */
	export let lang: string = 'javascript';
	/** Show the +/−/blank gutter column. */
	export let gutter: boolean = true;
	/** Show old + new line-number columns. */
	export let lineNumbers: boolean = false;
	/** Show a "+A −R" summary header above the block. */
	export let summary: boolean = false;
	/** Extra inline CSS appended to the box (e.g. spacing tweaks per slide). */
	export let style: string = '';
	/** DOM id for the root element. */
	export let id: string = '';
	/** Extra class(es) for the root element. NOTE: a slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS (global.css / roles.css / a
	    :global(...) block) or a utility class. See AGENTS.md. */
	let klass: string = '';
	export { klass as class };

	// The typed + numbered rows — pure, so this is right during SSR too. Precedence:
	// an explicit diff string, else two versions, else a plain block, else empty.
	$: lines =
		diff !== undefined
			? parseDiff(diff)
			: before !== undefined || after !== undefined
				? diffLines(before, after)
				: parseDiff((code ?? '').replace(/^/gm, ' ')); // plain: every line is context

	$: stats = diffStats(lines);

	// The exact text handed to the highlighter: every displayed line's text, in order,
	// joined by \n. Highlighting the whole block at once (rather than line by line)
	// keeps multi-line grammar context — a string or comment that a removed line opens
	// still colours the lines under it. `highlightToLines` returns one token array per
	// line, so it zips straight back onto `lines`.
	$: source = lines.map((l) => l.text).join('\n');

	// Token colours per line, filled in once Shiki resolves. Until then (and if Shiki
	// fails or the line count doesn't match) each row shows its plain text — the
	// QuickCode fallback. Null during SSR and the first client frame, so the block is
	// never blank: it renders plain, then swaps in the colours.
	let tokenLines: CodeToken[][] | null = null;

	// Highlight after mount (there is no highlighter during SSR), and re-highlight
	// whenever the source or language changes — a reactive `after`, an author editing
	// in dev. `mounted` gates the reactive so it doesn't fire a doomed highlight during
	// the server pass; the QuickCode onMount pattern, plus prop-reactivity.
	let mounted = false;
	onMount(() => {
		mounted = true;
		return () => {
			mounted = false;
		};
	});

	// Recompute whenever mounted / source / lang change. Reading them here registers the
	// dependency; the async result is written back through the `src === source` guard so
	// a stale in-flight highlight can never paint the wrong colours.
	$: void highlightInto(mounted, source, lang);

	function highlightInto(ready: boolean, src: string, l: string) {
		if (!ready) return;
		tokenLines = null; // drop stale colours so the rows fall back to plain text
		const expected = src === '' ? 1 : src.split('\n').length;
		highlightToLines(src, l)
			.then((out) => {
				// Guard: the token line count must match our row count, and the source
				// must not have changed under us — else the zip would paint one line's
				// colours onto another. Mismatch → keep plain text.
				if (out.length === expected && src === source) tokenLines = out;
			})
			.catch(() => {
				/* keep the plain fallback */
			});
	}

	// Column template: [old#] [new#] [sign] [code]. The number/sign columns only take
	// space when enabled, so a bare CodeDiff is just gutter + code.
	$: cols =
		(lineNumbers ? 'var(--codediff-num-w) var(--codediff-num-w) ' : '') +
		(gutter ? 'var(--codediff-sign-w) ' : '') +
		'1fr';

</script>

<div class="code-diff {klass}" id={id || undefined} {style} style:--codediff-cols={cols}>
	{#if summary}
		<div class="summary" aria-hidden="true">
			<span class="added">+{stats.added}</span>
			<span class="removed">−{stats.removed}</span>
		</div>
	{/if}
	<div class="rows" role="list">
		{#each lines as line, i (i)}
			<div class="row {line.type}" role="listitem">
				{#if lineNumbers}
					<span class="num old">{line.oldNo ?? ''}</span>
					<span class="num new">{line.newNo ?? ''}</span>
				{/if}
				{#if gutter}
					<span class="sign" aria-hidden="true">{signOf(line.type)}</span>
				{/if}
				<!-- Reference `tokenLines` directly so Svelte tracks the swap: a function
				     call here would hide the dependency and the colours would never paint. -->
				<span class="code">{#if tokenLines && tokenLines[i]}{#each tokenLines[i] as t}<span
								style:color={t.color}
								style:font-weight={t.bold ? '700' : null}
								style:font-style={t.italic ? 'italic' : null}>{t.content}</span
							>{/each}{:else}{line.text}{/if}</span>
			</div>
		{/each}
	</div>
</div>

<style>
	.code-diff {
		font-family: 'Fira Code', monospace;
		font-size: 0.85em;
		background: var(--codediff-bg, #111111);
		color: var(--codediff-fg, #ffffff);
		border-radius: 5px;
		padding: 0.5em 0;
		line-height: 1.7em;
		overflow-x: auto;

		/* Column widths for the number / sign gutters (used by the inline template). */
		--codediff-num-w: 2.6ch;
		--codediff-sign-w: 2ch;
	}

	.summary {
		display: flex;
		gap: 0.9em;
		padding: 0 1em 0.4em;
		margin: 0 0 0.3em;
		font-size: 0.8em;
		font-weight: 700;
		border-bottom: 1px solid color-mix(in srgb, var(--codediff-fg, #fff) 12%, transparent);
	}
	.summary .added {
		color: var(--codediff-add, #00b356);
	}
	.summary .removed {
		color: var(--codediff-del, #e5484d);
	}

	.rows {
		width: max-content;
		min-width: 100%;
	}

	.row {
		display: grid;
		grid-template-columns: var(--codediff-cols);
		align-items: baseline;
		/* An empty code line still needs a row's height; line-height on the row keeps
		   blank context/added lines from collapsing. */
		min-height: 1.7em;
	}

	/* The whole row washes for add/del; the left accent bar reads even where the wash
	   is faint (a dark theme deepens only slightly). Both mixed toward transparent from
	   ONE token so neither needs to know the surface colour — the Callout/Hint trick. */
	.row.add {
		background: color-mix(in srgb, var(--codediff-add, #00b356) 15%, transparent);
		box-shadow: inset 3px 0 0 var(--codediff-add, #00b356);
	}
	.row.del {
		background: color-mix(in srgb, var(--codediff-del, #e5484d) 15%, transparent);
		box-shadow: inset 3px 0 0 var(--codediff-del, #e5484d);
	}

	.num {
		padding: 0 0.5ch;
		text-align: right;
		font-size: 0.85em;
		color: color-mix(in srgb, var(--codediff-gutter-fg, #c0f1ff) 45%, transparent);
		user-select: none;
		white-space: nowrap;
	}
	.num.new {
		padding-right: 0.8ch;
	}

	.sign {
		text-align: center;
		font-weight: 700;
		user-select: none;
	}
	.row.add .sign {
		color: var(--codediff-add, #00b356);
	}
	.row.del .sign {
		color: var(--codediff-del, #e5484d);
	}
	.row.context .sign {
		color: color-mix(in srgb, var(--codediff-gutter-fg, #c0f1ff) 30%, transparent);
	}

	.code {
		padding-right: 1em;
		padding-left: 0.4ch;
		white-space: pre;
		/* Keep a blank line's row height even with no glyphs in it. */
	}
	.code:empty::before {
		content: '\200b'; /* zero-width space — occupies the line box, prints nothing */
	}
</style>
