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
// css-snippet path stays light and the svelte grammar only ships when the </> Source
// viewer is actually opened. Each lang loads at most once.
const langLoaders: Record<string, () => Promise<unknown>> = {
	svelte: () => import('shiki/langs/svelte.mjs'),
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
