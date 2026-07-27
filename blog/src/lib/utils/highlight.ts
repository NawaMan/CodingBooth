// Shiki syntax highlighting — a single shared highlighter for the whole app.
//
// Unlike the Monaco-based Code/CodeBox (whose CDN AMD loader re-bootstraps on every
// mount and breaks across client-side navigations — see the project memory
// "monaco-breaks-on-spa-nav"), Shiki is a plain ESM module. We create ONE highlighter
// lazily and reuse it for every snippet, so there is no global to clobber and it
// survives SPA navigation + View Transitions. The result is a string of HTML.
//
// Uses Shiki's FINE-GRAINED core: only the css grammar + one theme + the JS regex
// engine are bundled (no WASM, no 200-language bundle), so this adds ~tens of KB
// rather than Shiki's multi-MB full bundle.

import { createHighlighterCore, type HighlighterCore } from 'shiki/core';
import { createJavaScriptRegexEngine } from 'shiki/engine/javascript';
import cssLang from 'shiki/langs/css.mjs';
import everforestDark from 'shiki/themes/everforest-dark.mjs';

/** Green-toned theme to match the deck; its background is dropped by callers so the
    deck's own surface shows through and only the token colours apply. */
const THEME = 'everforest-dark';

let highlighterPromise: Promise<HighlighterCore> | null = null;

function getHighlighter(): Promise<HighlighterCore> {
	if (!highlighterPromise) {
		// Eagerly bundle only `css` (the snippet boxes). The JS regex engine handles
		// every grammar we use, so no Oniguruma WASM is bundled.
		highlighterPromise = createHighlighterCore({
			themes: [everforestDark],
			langs: [cssLang],
			engine: createJavaScriptRegexEngine(),
		});
	}
	return highlighterPromise;
}

// Heavier grammars (svelte pulls in ts/js) are loaded on demand, so the common
// css-snippet path stays light and each grammar only ships when a slide that uses
// it actually renders. Each lang loads at most once.
const langLoaders: Record<string, () => Promise<unknown>> = {
	svelte: () => import('shiki/langs/svelte.mjs'),
	javascript: () => import('shiki/langs/javascript.mjs'),
	python: () => import('shiki/langs/python.mjs'),
	go: () => import('shiki/langs/go.mjs'),
	bash: () => import('shiki/langs/bash.mjs'),
};
const langLoaded: Record<string, Promise<void>> = {};

async function ensureLang(highlighter: HighlighterCore, lang: string): Promise<void> {
	if (highlighter.getLoadedLanguages().includes(lang) || !langLoaders[lang]) return;
	if (!langLoaded[lang]) {
		langLoaded[lang] = langLoaders[lang]().then((m) =>
			highlighter.loadLanguage((m as { default: Parameters<HighlighterCore['loadLanguage']>[0] }).default)
		);
	}
	await langLoaded[lang];
}

/**
 * Highlight `code` as `lang` and return Shiki's `<pre class="shiki">…</pre>` HTML.
 * `css` is bundled eagerly; `svelte` (+ embedded css/js/ts) loads on first use.
 * Anything else falls back to css.
 */
export async function highlightToHtml(code: string, lang = 'css'): Promise<string> {
	const highlighter = await getHighlighter();
	await ensureLang(highlighter, lang);
	const useLang = highlighter.getLoadedLanguages().includes(lang) ? lang : 'css';
	return highlighter.codeToHtml(code, { lang: useLang, theme: THEME });
}

/** One themed token: the text run and the colour Shiki assigned it. `bold`/`italic`
    are decoded from Shiki's `fontStyle` bitmask so a caller can render them without
    importing Shiki's own types. */
export interface CodeToken {
	content: string;
	color?: string;
	bold?: boolean;
	italic?: boolean;
}

// Shiki's FontStyle bitmask (Italic = 1, Bold = 2, Underline = 4). Decoded here so
// the value never leaks past this module.
const FONT_ITALIC = 1;
const FONT_BOLD = 2;

/**
 * Highlight `code` and return its tokens grouped BY LINE — one array of
 * {@link CodeToken} per source line — rather than one HTML blob. This is what a
 * component that owns its own per-line markup (line numbers, a diff gutter, a
 * reveal) needs: it can colour each line's text while wrapping the line however it
 * likes. Same lazy-grammar path as {@link highlightToHtml}; anything not loadable
 * falls back to css.
 *
 * The returned array has exactly one entry per line of `code` (splitting on `\n`),
 * so a caller can zip it with its own line list. On any failure it rejects, and the
 * caller keeps its plain-text fallback — the QuickCode contract.
 */
export async function highlightToLines(code: string, lang = 'css'): Promise<CodeToken[][]> {
	const highlighter = await getHighlighter();
	await ensureLang(highlighter, lang);
	const useLang = highlighter.getLoadedLanguages().includes(lang) ? lang : 'css';
	const { tokens } = highlighter.codeToTokens(code, { lang: useLang, theme: THEME });
	return tokens.map((line) =>
		line.map((t) => ({
			content: t.content,
			color: t.color,
			bold: ((t.fontStyle ?? 0) & FONT_BOLD) !== 0,
			italic: ((t.fontStyle ?? 0) & FONT_ITALIC) !== 0
		}))
	);
}
