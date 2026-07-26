// @vitest-environment node
//
// True server-side render of CodeDiff (svelte/server, no DOM). The Shiki token
// colours can't and shouldn't prerender — there is no highlighter during SSR, and
// the block deliberately renders PLAIN text first, then swaps colours in on mount
// (the QuickCode contract). What MUST prerender is the diff STRUCTURE: one row per
// line, the add/del/context class the stylesheet reads, the +/− gutter, the code
// text itself, and — when asked — the old/new line numbers. That structure is what
// makes a CodeDiff SSR-safe: no mount-time flash, and a symbol that can't differ
// between the server's idea of it and the browser's.
//
// CodeDiff takes props, not slots, so it renders directly — no host component.
import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';
import CodeDiff from '../src/lib/components/CodeDiff.svelte';

const body = (props: Record<string, unknown>) => render(CodeDiff, { props }).body;

describe('CodeDiff (SSR)', () => {
	it('computes a diff from before/after and renders one row per line', () => {
		const html = body({ before: 'a\nOLD\nc', after: 'a\nNEW\nc' });
		// 4 rows: context a, del OLD, add NEW, context c.
		expect((html.match(/role="listitem"/g) ?? []).length).toBe(4);
		expect(html).toContain('OLD');
		expect(html).toContain('NEW');
	});

	it('tags each row with its type class the stylesheet keys on', () => {
		const html = body({ before: 'a\nOLD\nc', after: 'a\nNEW\nc' });
		// The scope hash sits inside the class attribute, so match the type token.
		expect(html).toMatch(/class="row[^"]*\bdel\b/);
		expect(html).toMatch(/class="row[^"]*\badd\b/);
		expect(html).toMatch(/class="row[^"]*\bcontext\b/);
	});

	it('the code text prerenders plain (no Shiki colour spans on the server)', () => {
		const html = body({ before: 'x = 1', after: 'x = 2' });
		expect(html).toContain('x = 1');
		expect(html).toContain('x = 2');
		// No inline token colours are emitted server-side.
		expect(html).not.toContain('style="color:');
	});

	it('a git-style diff string is parsed into the same structure', () => {
		const html = body({ diff: ' keep\n-gone\n+added' });
		expect((html.match(/role="listitem"/g) ?? []).length).toBe(3);
		expect(html).toMatch(/class="row[^"]*\bdel\b/);
		expect(html).toMatch(/class="row[^"]*\badd\b/);
		expect(html).toContain('gone');
		expect(html).toContain('added');
	});

	// The scope hash sits between the class token and the closing quote
	// (class="sign svelte-…"), so every class assertion drops the closing quote.
	it('the gutter shows +/− and is on by default; gutter={false} drops it', () => {
		const withGutter = body({ diff: '+new\n-old' });
		expect(withGutter).toContain('class="sign');
		expect(withGutter).toContain('+');
		expect(withGutter).toContain('−'); // U+2212

		const without = body({ diff: '+new\n-old', gutter: false });
		expect(without).not.toContain('class="sign');
	});

	it('lineNumbers renders old + new number columns; off by default', () => {
		expect(body({ diff: '+a' })).not.toContain('class="num');
		const html = body({ before: 'a\nOLD', after: 'a\nNEW', lineNumbers: true });
		// Two num spans per row (old + new).
		expect(html).toContain('class="num old');
		expect(html).toContain('class="num new');
	});

	it('a summary chip is opt-in and reports the counts', () => {
		expect(body({ diff: '+a\n+b\n-c' })).not.toContain('class="summary');
		const html = body({ diff: '+a\n+b\n-c', summary: true });
		expect(html).toContain('class="summary');
		expect(html).toContain('+2');
		expect(html).toContain('−1');
	});

	it('a plain code block (no diff) renders every line as context', () => {
		const html = body({ code: 'line one\nline two' });
		expect((html.match(/role="listitem"/g) ?? []).length).toBe(2);
		expect(html).not.toMatch(/class="row[^"]*\b(add|del)\b/);
		expect(html).toContain('line one');
	});
});
