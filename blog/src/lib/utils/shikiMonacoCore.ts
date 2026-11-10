// Pure half of the Shiki → Monaco bridge (the impure half is monacoShiki.ts).
//
// Monaco tokenizes a document LINE BY LINE, carrying a state object from one line
// to the next; a TextMate grammar (what Shiki runs) does exactly the same with its
// rule stack. So the bridge is thin: run the grammar's `tokenizeLine2` on each line,
// and turn every token's encoded foreground colour into a Monaco scope (`gp<n>`,
// n = the index into the grammar registry's colour map). A Monaco theme then maps
// each `gp<n>` back to that colour. No Monaco and no Shiki import here, so the
// whole mapping is unit-tested without a browser.

// vscode-textmate's encoded token metadata (EncodedTokenMetadata): bits 11–14 are
// the font style, bits 15–23 the foreground index into the colour map.
const FONT_STYLE_MASK = 0x7800;
const FONT_STYLE_OFFSET = 11;
const FOREGROUND_MASK = 0xff8000;
const FOREGROUND_OFFSET = 15;
// FontStyle bits inside that field.
const ITALIC = 1;
const BOLD = 2;

/** What Monaco's tokens provider wants back per token. */
export interface MonacoToken {
	startIndex: number;
	scopes: string;
}

/** The slice of a TextMate rule stack this bridge needs (vscode-textmate's StateStack). */
export interface RuleStack {
	equals(other: RuleStack): boolean;
}

/** The slice of a TextMate grammar this bridge needs (vscode-textmate's IGrammar). */
export interface LineGrammar<S extends RuleStack = RuleStack> {
	tokenizeLine2(
		line: string,
		prev: S | null,
		timeLimit?: number
	): { tokens: Uint32Array; ruleStack: S; stoppedEarly?: boolean };
}

/** Monaco's IState around a rule stack. The stack is immutable, so a clone may
    share it; `null` is the start of the document. */
export class TokenState<S extends RuleStack = RuleStack> {
	constructor(readonly stack: S | null) {}
	clone(): TokenState<S> {
		return new TokenState(this.stack);
	}
	equals(other: unknown): boolean {
		if (!(other instanceof TokenState)) return false;
		if (this.stack === other.stack) return true;
		if (!this.stack || !other.stack) return false;
		return this.stack.equals(other.stack);
	}
}

/** The scope for a colour index and font style: `gp7`, `gp7.i`, `gp7.b`, `gp7.ib`. */
export function scopeFor(colorIndex: number, fontStyle = 0): string {
	const style = (fontStyle & ITALIC ? 'i' : '') + (fontStyle & BOLD ? 'b' : '');
	return style ? `gp${colorIndex}.${style}` : `gp${colorIndex}`;
}

/** Decode `tokenizeLine2`'s binary output (start, metadata, start, metadata, …)
    into Monaco tokens. Adjacent tokens of the same scope are merged. */
export function monacoTokens(binary: ArrayLike<number>): MonacoToken[] {
	const out: MonacoToken[] = [];
	for (let i = 0; i + 1 < binary.length; i += 2) {
		const meta = binary[i + 1];
		const scopes = scopeFor(
			(meta & FOREGROUND_MASK) >>> FOREGROUND_OFFSET,
			(meta & FONT_STYLE_MASK) >>> FONT_STYLE_OFFSET
		);
		if (out.length && out[out.length - 1].scopes === scopes) continue;
		out.push({ startIndex: binary[i], scopes });
	}
	return out;
}

/** Long minified lines must not freeze the editor: give up on a line after this. */
export const LINE_TIME_LIMIT_MS = 500;

/** Tokenize one line from `state`. A line the grammar gives up on keeps the
    incoming state, so the next line still starts somewhere sane. */
export function tokenizeLine<S extends RuleStack>(
	grammar: LineGrammar<S>,
	line: string,
	state: TokenState<S>
): { tokens: MonacoToken[]; endState: TokenState<S> } {
	const r = grammar.tokenizeLine2(line, state.stack, LINE_TIME_LIMIT_MS);
	return {
		tokens: monacoTokens(r.tokens),
		endState: r.stoppedEarly ? state : new TokenState(r.ruleStack)
	};
}

/** `#RGB`, `#RRGGBB` or `#RRGGBBAA` → `rrggbb` (Monaco theme rules take no `#`
    and no alpha); anything else → null. */
export function hex6(color: unknown): string | null {
	if (typeof color !== 'string') return null;
	const m = /^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i.exec(color.trim());
	if (!m) return null;
	const h = m[1].toLowerCase();
	return h.length === 3 ? h.replace(/./g, (c) => c + c) : h.slice(0, 6);
}

export interface MonacoThemeRule {
	token: string;
	foreground: string;
	fontStyle?: string;
}

/** One rule per colour and font style, so every scope `monacoTokens` can emit has
    a colour. Index 0 of a TextMate colour map is unused; junk entries are skipped. */
export function themeRules(colorMap: readonly unknown[]): MonacoThemeRule[] {
	const rules: MonacoThemeRule[] = [];
	colorMap.forEach((color, i) => {
		const foreground = hex6(color);
		if (!foreground) return;
		rules.push({ token: scopeFor(i), foreground });
		rules.push({ token: scopeFor(i, ITALIC), foreground, fontStyle: 'italic' });
		rules.push({ token: scopeFor(i, BOLD), foreground, fontStyle: 'bold' });
		rules.push({ token: scopeFor(i, ITALIC | BOLD), foreground, fontStyle: 'italic bold' });
	});
	return rules;
}

/** The deck's one Monaco theme: vs-dark, plus the Shiki colours once a Shiki
    language is registered. Monaco's theme is GLOBAL to the page, so every editor
    must use this one name — an editor created with plain `vs-dark` would switch
    every other editor back and drop the Shiki colours. */
export function monacoTheme(colorMap: readonly unknown[] = []) {
	return { base: 'vs-dark' as const, inherit: true, rules: themeRules(colorMap), colors: {} };
}

/** Comments, brackets and auto-closing for `.svelte` in Monaco — what its built-in
    `html` gave before, plus the `{ }` of Svelte's template syntax. */
export const SVELTE_LANGUAGE_CONFIG = {
	comments: { blockComment: ['<!--', '-->'] as [string, string] },
	brackets: [
		['<!--', '-->'],
		['<', '>'],
		['{', '}'],
		['(', ')'],
		['[', ']']
	] as [string, string][],
	autoClosingPairs: [
		{ open: '{', close: '}' },
		{ open: '[', close: ']' },
		{ open: '(', close: ')' },
		{ open: '"', close: '"' },
		{ open: "'", close: "'" },
		{ open: '`', close: '`' },
		{ open: '<!--', close: '-->' }
	],
	surroundingPairs: [
		{ open: '{', close: '}' },
		{ open: '[', close: ']' },
		{ open: '(', close: ')' },
		{ open: '"', close: '"' },
		{ open: "'", close: "'" },
		{ open: '`', close: '`' },
		{ open: '<', close: '>' }
	]
};
