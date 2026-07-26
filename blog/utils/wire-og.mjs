/*
  wire-og.mjs — add `image:` to a deck's pages.ts entries, pointing each slide at its own
  captured PNG, so social cards show THE SLIDE instead of the site's default card.

  Called by `capture-slides.sh --og`; also runnable on its own:

      node utils/wire-og.mjs src/routes/slides/pages.ts og/slides title.html intro.html …

  Why edit the source at all, rather than deriving the path at runtime? Because `image` is a
  field an AUTHOR owns. A slide may already point at a hand-made card, and a convention that
  silently overrode it would be a surprise; a convention that silently *created* a URL for a
  PNG nobody generated would 404 on someone's timeline. Writing it into `pages.ts` keeps the
  wiring visible, diffable and revertible — you can see in `git diff` exactly which slides got
  a card, and delete the line to opt one out.

  The rules that make it safe to re-run:
    - An entry that ALREADY has an `image` is never touched. The author outranks the tool.
    - Only entries whose `path` we actually captured get one. No URL is invented for a PNG
      that does not exist.
    - Idempotent: running it twice changes nothing the second time.
    - Anything it cannot confidently parse is LEFT ALONE and reported, never guessed — the
      same bargain patchSource.ts makes for LAYOUT's SAVE.
*/

/** The `image` value for a slide: site-relative, which is what seo/config.resolveImage wants
    (it makes it absolute against SITE_URL).

    @param {string} dir        e.g. "og/slides"
    @param {string} slideFile  e.g. "title.html"
    @returns {string}          e.g. "og/slides/title.png" */
export function ogImagePath(dir, slideFile) {
	const stem = String(slideFile ?? '').replace(/\.html?$/i, '');
	return `${String(dir ?? '').replace(/^\/+|\/+$/g, '')}/${stem}.png`;
}

/** Add `image: "…"` to every pages.ts entry we captured a PNG for.

    Works line by line, because a pages.ts entry is one line — and that is also the guard: an
    entry we cannot see whole on one line is skipped rather than half-edited. Returns the new
    source plus what happened, so the caller can report it instead of the tool going quiet.

    @param {string} source      the pages.ts contents
    @param {string} dir         the site-relative og directory, e.g. "og/slides"
    @param {string[]} slideFiles the slides we actually captured, e.g. ["title.html"]
    @returns {{ source: string, added: string[], kept: string[], skipped: string[] }} */
export function wireOgImages(source, dir, slideFiles) {
	const wanted = new Set(slideFiles ?? []);
	/** @type {string[]} */
	const added = [];
	/** @type {string[]} already had an image — the author's choice wins */
	const kept = [];
	/** @type {string[]} matched a slide but we could not place the field safely */
	const skipped = [];

	const lines = String(source ?? '').split('\n');
	const out = lines.map((line) => {
		// An entry line: `{ path: "x.html", title: "…" },` — optionally followed by a trailing
		// `// comment`, which is common in this file and carried through untouched. Comments and
		// the array's own scaffolding never match, so they pass through too. (A comment INSIDE
		// the braces is a different matter — see the refusal below.)
		const m = line.match(/^(\s*)\{(.*)\}(\s*,?\s*(?:\/\/.*)?)$/);
		if (!m) return line;

		const [, indent, body, tail] = m;
		const pathMatch = body.match(/\bpath\s*:\s*["']([^"']+)["']/);
		if (!pathMatch) return line;

		const file = pathMatch[1];
		if (!wanted.has(file)) return line;

		if (/\bimage\s*:/.test(body)) {
			kept.push(file);
			return line;
		}
		// Refuse anything that would need us to guess where the field goes — a nested object or
		// a trailing line comment inside the entry. Leaving it for a human beats a bad edit.
		if (/[{}]/.test(body) || body.includes('//')) {
			skipped.push(file);
			return line;
		}

		added.push(file);
		const trimmed = body.replace(/\s+$/, '').replace(/,\s*$/, '');
		return `${indent}{${trimmed}, image: "${ogImagePath(dir, file)}" }${tail}`;
	});

	return { source: out.join('\n'), added, kept, skipped };
}

// ── CLI ─────────────────────────────────────────────────────────────────────────────
if (process.argv[1] && process.argv[1].endsWith('wire-og.mjs')) {
	const { readFileSync, writeFileSync } = await import('node:fs');
	const [, , pagesFile, dir, ...slides] = process.argv;

	if (!pagesFile || !dir || slides.length === 0) {
		console.error('usage: node utils/wire-og.mjs <pages.ts> <og-dir> <slide.html>…');
		process.exit(2);
	}

	const before = readFileSync(pagesFile, 'utf8');
	const { source, added, kept, skipped } = wireOgImages(before, dir, slides);

	if (source !== before) writeFileSync(pagesFile, source);

	console.log(`  wired ${added.length} slide(s) into ${pagesFile}`);
	if (kept.length) console.log(`  left ${kept.length} with the image they already had`);
	if (skipped.length) console.error(`  ⚠ could not place image on: ${skipped.join(', ')}`);
}
