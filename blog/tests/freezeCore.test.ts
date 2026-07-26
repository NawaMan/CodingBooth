// Unit tests for the FREEZE mapping — an ANNOTATE stroke becoming Draw source.
//
// The whole feature is this translation, so it is tested directly rather than through the
// component: hand it strokes, read the markup. The two properties that matter are that each
// tool lands on the right shape, and that the function is TOTAL — a stroke carrying junk
// still yields a tag that parses, because the output is pasted straight into someone's
// source file and `NaNpx` there is a broken slide.
import { describe, expect, it } from 'vitest';
import {
	freezeCount,
	freezeImport,
	freezeSnippet,
	freezeTag,
	freezeTags,
	isFreezable
} from '../src/lib/annotate/freezeCore';
import type { Stroke } from '../src/lib/annotate/annotateCore';

function ink(over: Partial<Stroke> = {}): Stroke {
	return { id: 'a', tool: 'pen', points: [[10, 20], [30, 40]], ...over };
}

describe('freezeTag — the per-tool mapping', () => {
	it('turns a PEN stroke into a smoothed Polyline through its own points', () => {
		const tag = freezeTag(ink({ tool: 'pen', points: [[10, 20], [30, 40], [55.5, 60]] }));
		expect(tag).toBe('<Polyline points={[[10, 20], [30, 40], [55.5, 60]]} smooth thickness={6} />');
	});

	it('keeps a HIGHLIGHTER a fat translucent band, not a box', () => {
		const tag = freezeTag(ink({ tool: 'highlighter' }));
		expect(tag).toContain('<Polyline');
		expect(tag).toContain('thickness={34}');
		// The token, not a frozen 0.45 — a re-theme moves the frozen band with the live ink.
		expect(tag).toContain('opacity:var(--annot-highlighter-alpha, 0.45)');
		expect(tag).not.toContain('<Rect');
	});

	it('turns LINE into a two-point Line, and ARROW into the same Line with its head', () => {
		const pts: [number, number][] = [[0, 0], [100, 100]];
		expect(freezeTag(ink({ tool: 'line', points: pts }))).toBe(
			'<Line from={[0, 0]} to={[100, 100]} thickness={6} />'
		);
		expect(freezeTag(ink({ tool: 'arrow', points: pts }))).toBe(
			'<Line from={[0, 0]} to={[100, 100]} arrow="end" thickness={6} />'
		);
	});

	it('normalises a RECTANGLE dragged bottom-right to top-left', () => {
		// The speaker dragged from (300, 400) back up to (100, 200); the frozen box is the
		// same box either way, exactly as rectD paints it.
		const tag = freezeTag(ink({ tool: 'rectangle', points: [[300, 400], [100, 200]] }));
		expect(tag).toBe('<Rect x={100} y={200} width={200} height={200} thickness={6} />');
	});

	it('refuses TEXT — the Draw family has no counterpart for a typed label', () => {
		const label = ink({ tool: 'text', text: 'hello', points: [[10, 10]] });
		expect(isFreezable(label)).toBe(false);
		expect(freezeTag(label)).toBe('');
	});
});

describe('freezeTag — colour follows the theme unless it was chosen', () => {
	it('emits NO colour for an untinted stroke, so --draw-stroke paints it', () => {
		// The absence is the meaningful case: a colourless stroke was painted by --annot-*,
		// and freezing today's hex would freeze today's theme with it.
		expect(freezeTag(ink())).not.toContain('color=');
	});

	it('carries a colour the speaker explicitly picked', () => {
		expect(freezeTag(ink({ color: '#E5484D' }))).toContain('color="#E5484D"');
	});

	it('omits thickness when it equals the Draw default, so the token still rules', () => {
		expect(freezeTag(ink({ tool: 'pen' }), { penWidth: 4 })).not.toContain('thickness=');
	});
});

describe('freezeTag — total, because the output is pasted into source', () => {
	it('repairs NaN and Infinity into drawable numbers rather than emitting them', () => {
		const tag = freezeTag(ink({ points: [[NaN, 20], [30, Infinity]] }));
		expect(tag).not.toMatch(/NaN|Infinity/);
		expect(tag).toBe('<Polyline points={[[0, 20], [30, 0]]} smooth thickness={6} />');
	});

	it('yields nothing for a stroke with no points at all', () => {
		expect(freezeTag(ink({ points: [] }))).toBe('');
		// …and for outright garbage where `points` isn't even an array.
		expect(freezeTag({ id: 'x', tool: 'pen' } as unknown as Stroke)).toBe('');
	});

	it('survives being handed nothing', () => {
		expect(isFreezable(undefined)).toBe(false);
		expect(freezeTags([], [])).toEqual([]);
		expect(freezeSnippet([], ['a'])).toBe('');
		expect(freezeCount([], ['a'])).toBe(0);
	});
});

describe('freezeTags — the selection', () => {
	const list: Stroke[] = [
		ink({ id: 'one', tool: 'pen' }),
		ink({ id: 'two', tool: 'rectangle' }),
		ink({ id: 'three', tool: 'line' })
	];

	it('emits only what was picked', () => {
		const tags = freezeTags(list, ['two']);
		expect(tags).toHaveLength(1);
		expect(tags[0]).toContain('<Rect');
	});

	it('emits in DRAW order, not pick order — so frozen shapes stack as they looked', () => {
		// Ink paints in array order, a later mark over an earlier one. Picking the last one
		// first must not invert that.
		const tags = freezeTags(list, ['three', 'one']);
		expect(tags[0]).toContain('<Polyline');
		expect(tags[1]).toContain('<Line');
	});

	it('ignores ids that are not on this slide', () => {
		expect(freezeTags(list, ['ghost'])).toEqual([]);
	});

	it('counts only what would actually produce a tag', () => {
		// A picked TEXT label contributes nothing, so the button must not promise it.
		const withText = [...list, ink({ id: 'four', tool: 'text', text: 'hi' })];
		expect(freezeCount(withText, ['one', 'four'])).toBe(1);
	});
});

describe('freezeSnippet — what lands on the clipboard', () => {
	const list = [ink({ id: 'one' })];

	it('wraps the tags in a <Draw>, because a bare Polyline renders nothing', () => {
		const out = freezeSnippet(list, ['one']);
		expect(out.startsWith('<Draw>')).toBe(true);
		expect(out.endsWith('</Draw>')).toBe(true);
		expect(out).toContain('\t<Polyline');
	});

	it('skips the wrapper when the destination already has one', () => {
		const out = freezeSnippet(list, ['one'], { wrap: false });
		expect(out).not.toContain('<Draw>');
		expect(out.startsWith('<Polyline')).toBe(true);
	});

	it('indents every line to the paste site', () => {
		const out = freezeSnippet(list, ['one'], { indent: '  ' });
		expect(out.split('\n').every((l) => l.startsWith('  '))).toBe(true);
	});
});

describe('freezeImport — only what the markup uses', () => {
	it('names Draw plus the components actually present', () => {
		expect(freezeImport(['<Polyline points={[]} />'])).toBe(
			"import { Draw, Polyline } from '$lib/draw';"
		);
		expect(freezeImport(['<Rect x={0} />', '<Line from={[0, 0]} />'])).toBe(
			"import { Draw, Line, Rect } from '$lib/draw';"
		);
	});

	it('is empty when there is nothing to import', () => {
		expect(freezeImport([])).toBe('');
	});
});
