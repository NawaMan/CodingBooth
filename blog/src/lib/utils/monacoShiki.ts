// Impure half of the Shiki → Monaco bridge (pure half: shikiMonacoCore.ts).
//
// Monaco has no Svelte language. Shiki does — the same grammar QuickCode and
// SourceView already colour `.svelte` with — so register a `svelte` language in
// Monaco whose tokenizer is that grammar. Before this, `.svelte` sources were
// shown as `html`: the markup coloured, the <script> and {expressions} not.

import { grammarFor } from './highlight';
import {
	SVELTE_LANGUAGE_CONFIG,
	TokenState,
	monacoTheme,
	tokenizeLine,
	type LineGrammar
} from './shikiMonacoCore';
import { MONACO_THEME } from './monacoCdn';

/** Monaco language ids this bridge provides, and what to show if Shiki fails. */
const BRIDGED: Record<string, string> = { svelte: 'html' };

const ready: Record<string, Promise<string>> = {};

/** The Monaco language id to create an editor with. For a bridged language
    (`svelte`) this first registers it — once per page — and falls back to its
    stand-in (`html`) if the grammar can't load. Anything else is returned as is. */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function ensureMonacoLanguage(monaco: any, language: string): Promise<string> {
	const fallback = BRIDGED[language];
	if (!fallback) return Promise.resolve(language);
	if (!ready[language]) {
		ready[language] = register(monaco, language).catch((err) => {
			console.warn(`[Code] no ${language} highlighting, showing it as ${fallback}:`, err);
			return fallback;
		});
	}
	return ready[language];
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
async function register(monaco: any, language: string): Promise<string> {
	const { grammar, colorMap } = await grammarFor(language);
	const lineGrammar = grammar as unknown as LineGrammar;
	monaco.languages.register({ id: language, extensions: [`.${language}`] });
	monaco.languages.setLanguageConfiguration(language, SVELTE_LANGUAGE_CONFIG);
	monaco.languages.setTokensProvider(language, {
		getInitialState: () => new TokenState(null),
		tokenize: (line: string, state: TokenState) => tokenizeLine(lineGrammar, line, state)
	});
	// Re-define the page's one theme with the Shiki colours added. Monaco applies a
	// re-defined active theme at once, so editors already open pick them up too.
	monaco.editor.defineTheme(MONACO_THEME, monacoTheme(colorMap));
	monaco.editor.setTheme(MONACO_THEME);
	return language;
}
