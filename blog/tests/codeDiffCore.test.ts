// Unit tests for codeDiffCore — the pure line-diff engine behind <CodeDiff>.
// No DOM: every function is total, so the bad inputs (null/undefined source,
// disjoint versions, a lone marker, a huge paste) are as much the subject as the
// happy path. Line numbering is load-bearing (a wrong old/new number is a lie the
// audience reads), so it is asserted on every shape.
import { describe, expect, it } from 'vitest';
import {
	diffLines,
	parseDiff,
	diffStats,
	signOf,
	type DiffLine
} from '../src/lib/utils/codeDiffCore';

// Compact a DiffLine to `${sign}${text}@${old}/${new}` for terse assertions.
const show = (l: DiffLine) =>
	`${l.type[0]}:${l.text}@${l.oldNo ?? '_'}/${l.newNo ?? '_'}`;
const shown = (ls: DiffLine[]) => ls.map(show);

describe('diffLines', () => {
	it('two empty / null inputs → no rows', () => {
		expect(diffLines('', '')).toEqual([]);
		expect(diffLines(null, undefined)).toEqual([]);
	});

	it('identical inputs → all context, both numbers running together', () => {
		const out = diffLines('a\nb\nc', 'a\nb\nc');
		expect(shown(out)).toEqual(['c:a@1/1', 'c:b@2/2', 'c:c@3/3']);
	});

	it('an empty before → every after line is an add (no old numbers)', () => {
		expect(shown(diffLines('', 'x\ny'))).toEqual(['a:x@_/1', 'a:y@_/2']);
	});

	it('an empty after → every before line is a del (no new numbers)', () => {
		expect(shown(diffLines('x\ny', ''))).toEqual(['d:x@1/_', 'd:y@2/_']);
	});

	it('a one-line change: shared head + tail context, del before add', () => {
		const before = 'a\nOLD\nc';
		const after = 'a\nNEW\nc';
		expect(shown(diffLines(before, after))).toEqual([
			'c:a@1/1',
			'd:OLD@2/_',
			'a:NEW@_/2',
			'c:c@3/3'
		]);
	});

	it('numbers advance per side: old skips added lines, new skips removed ones', () => {
		// before: 1 2 3 4   after: 1 2 X 4 (line 3 replaced by X)
		const out = diffLines('1\n2\n3\n4', '1\n2\nX\n4');
		expect(shown(out)).toEqual([
			'c:1@1/1',
			'c:2@2/2',
			'd:3@3/_', // old #3, no new
			'a:X@_/3', // new #3, no old
			'c:4@4/4'
		]);
	});

	it('a pure insertion in the middle keeps the surrounding context', () => {
		const out = diffLines('a\nb', 'a\nMID\nb');
		expect(shown(out)).toEqual(['c:a@1/1', 'a:MID@_/2', 'c:b@2/3']);
	});

	it('disjoint inputs → all dels then all adds', () => {
		const out = diffLines('a\nb', 'x\ny');
		expect(out.map((l) => l.type)).toEqual(['del', 'del', 'add', 'add']);
		expect(shown(out)).toEqual(['d:a@1/_', 'd:b@2/_', 'a:x@_/1', 'a:y@_/2']);
	});

	it('a trailing newline does not add a phantom blank line', () => {
		expect(diffLines('a\n', 'a\n')).toEqual([
			{ type: 'context', text: 'a', oldNo: 1, newNo: 1 }
		]);
	});

	it('a huge paste still diffs (degrades to block-replace, never throws)', () => {
		const big = (tag: string) =>
			Array.from({ length: 1500 }, (_, i) => `${tag}${i}`).join('\n');
		const out = diffLines(big('a'), big('b'));
		// Totally different + over the LCS guard → all dels then all adds.
		expect(out.length).toBe(3000);
		expect(out[0].type).toBe('del');
		expect(out[out.length - 1].type).toBe('add');
	});
});

describe('parseDiff', () => {
	it('null / empty source → no rows', () => {
		expect(parseDiff(undefined)).toEqual([]);
		expect(parseDiff('')).toEqual([]);
	});

	it('reads +/-/space markers and strips exactly one', () => {
		const out = parseDiff(' keep\n-gone\n+added');
		expect(shown(out)).toEqual(['c:keep@1/1', 'd:gone@2/_', 'a:added@_/2']);
	});

	it('numbers old/new the same way diffLines does', () => {
		const out = parseDiff('  ctx\n-  old\n+  new\n  tail');
		expect(shown(out)).toEqual([
			'c: ctx@1/1', // one leading space stripped, the author's indent kept
			'd:  old@2/_',
			'a:  new@_/2',
			'c: tail@3/3'
		]);
	});

	it('git convention: a leading space marks context and is stripped once, so the +/-/space columns align', () => {
		// The real indent lives AFTER the one-char marker, exactly as `git diff` prints.
		const out = parseDiff(' def f():\n-    return 1\n+    return 2');
		expect(shown(out)).toEqual(['c:def f():@1/1', 'd:    return 1@2/_', 'a:    return 2@_/2']);
	});

	it('a line with no marker char at all keeps its full content (the escape hatch)', () => {
		const out = parseDiff('def f():\nreturn 1');
		expect(shown(out)).toEqual(['c:def f():@1/1', 'c:return 1@2/2']);
	});

	it('a lone marker is that marker on an empty line, never a throw', () => {
		const out = parseDiff('+\n-');
		expect(shown(out)).toEqual(['a:@_/1', 'd:@1/_']);
	});

	it('a blank line in the block is blank context', () => {
		const out = parseDiff('+a\n\n+b');
		expect(out.map((l) => l.type)).toEqual(['add', 'context', 'add']);
		expect(out[1].text).toBe('');
	});
});

describe('diffStats', () => {
	it('counts each type', () => {
		const out = parseDiff('+a\n+b\n-c\n d');
		expect(diffStats(out)).toEqual({ added: 2, removed: 1, context: 1 });
	});
	it('empty → all zero', () => {
		expect(diffStats([])).toEqual({ added: 0, removed: 0, context: 0 });
	});
});

describe('signOf', () => {
	it('maps the three types to gutter glyphs (a true minus, not a hyphen)', () => {
		expect(signOf('add')).toBe('+');
		expect(signOf('del')).toBe('−'); // U+2212
		expect(signOf('context')).toBe(' ');
	});
});
