// The track arithmetic behind <Columns> / <Column>, tested without a layout engine —
// jsdom has none. Every function is total: the interesting cases are the bad ones (a
// negative width, `columns={0}`, a span past the last track), because a slide must
// not collapse over any of them.
import { describe, expect, it } from 'vitest';
import {
	alignment,
	clampSpan,
	formatWidths,
	gutterCenters,
	parseGapPx,
	parseTrackPx,
	resizeTracks,
	toWeights,
	trackCount,
	trackTemplate,
	weightsTemplate
} from '../src/lib/utils/columnsCore';

describe('trackTemplate', () => {
	it('builds even minmax tracks from a count', () => {
		expect(trackTemplate(1, null)).toBe('minmax(0, 1fr)');
		expect(trackTemplate(3, null)).toBe('minmax(0, 1fr) minmax(0, 1fr) minmax(0, 1fr)');
	});

	it('floors every even track at 0 — a bare `1fr` bottoms out at min-content', () => {
		const template = trackTemplate(3, null);
		expect(template.match(/minmax\(0, 1fr\)/g)).toHaveLength(3);
		// ...and nothing else is in there, so no track can be a bare `1fr`.
		expect(template.replace(/minmax\(0, 1fr\)/g, '').trim()).toBe('');
	});

	it('falls back to a two-column split for an unusable count', () => {
		const split = 'minmax(0, 1fr) minmax(0, 1fr)';
		for (const bad of [0, -3, NaN, Infinity, 0.4, null, undefined, '3', {}]) {
			expect(trackTemplate(bad, null)).toBe(split);
		}
	});

	it('truncates a fractional count rather than rejecting it', () => {
		expect(trackTemplate(2.9, null)).toBe('minmax(0, 1fr) minmax(0, 1fr)');
	});

	it('reads a widths array as flex weights, mixed with CSS lengths', () => {
		expect(trackTemplate(2, [3, 2])).toBe('3fr 2fr');
		expect(trackTemplate(2, ['360px', 1])).toBe('360px 1fr');
		expect(trackTemplate(2, ['minmax(0, 1fr)', 'auto'])).toBe('minmax(0, 1fr) auto');
	});

	it('drops junk entries, keeping the survivors', () => {
		expect(trackTemplate(2, [3, -1, 0, NaN, '', '  ', null, 2])).toBe('3fr 2fr');
	});

	it('falls back to the count when nothing in widths survives', () => {
		expect(trackTemplate(3, [0, NaN, ''])).toBe(
			'minmax(0, 1fr) minmax(0, 1fr) minmax(0, 1fr)'
		);
		expect(trackTemplate(1, [])).toBe('minmax(0, 1fr)');
	});

	it('passes a string template through verbatim', () => {
		expect(trackTemplate(2, 'repeat(4, 1fr)')).toBe('repeat(4, 1fr)');
		expect(trackTemplate(2, '  1fr 2fr  ')).toBe('1fr 2fr');
	});

	it('rejects a semicolon — the template lands in an inline style attribute', () => {
		const split = 'minmax(0, 1fr) minmax(0, 1fr)';
		expect(trackTemplate(2, '1fr; color: red')).toBe(split);
		expect(trackTemplate(2, ['1fr; color: red', '2fr'])).toBe('2fr');
	});

	it('is always a usable template, never the empty string', () => {
		for (const widths of [null, undefined, '', '   ', [], [NaN], 42, {}]) {
			expect(trackTemplate(NaN, widths)).not.toBe('');
		}
	});
});

describe('trackCount', () => {
	it('counts the tracks it can', () => {
		expect(trackCount(3, null)).toBe(3);
		expect(trackCount(2, [3, 2])).toBe(2);
		expect(trackCount(2, ['360px', 1, 'auto'])).toBe(3);
		expect(trackCount(9, [1, 0, NaN])).toBe(1);
	});

	it('counts the fallback when nothing in widths survives', () => {
		expect(trackCount(3, [0, ''])).toBe(3);
		expect(trackCount(-1, [])).toBe(2);
	});

	it('gives up on a raw template — `repeat(3, 1fr)` is three tracks, `1fr 1fr` is two', () => {
		expect(trackCount(2, 'repeat(3, 1fr)')).toBeNull();
		expect(trackCount(2, '1fr 2fr')).toBeNull();
	});

	it('a rejected string is not a template, so the count stands', () => {
		expect(trackCount(3, '  ')).toBe(3);
		expect(trackCount(3, '1fr; color: red')).toBe(3);
	});
});

describe('clampSpan', () => {
	it('clamps to the group’s track count — grid would silently add a column', () => {
		expect(clampSpan(3, 2)).toBe(2);
		expect(clampSpan(2, 3)).toBe(2);
		expect(clampSpan(1, 1)).toBe(1);
	});

	it('floors at one track', () => {
		for (const bad of [0, -2, NaN, Infinity, null, undefined, '2']) {
			expect(clampSpan(bad, 3)).toBe(1);
		}
	});

	it('truncates a fractional span', () => {
		expect(clampSpan(2.7, 4)).toBe(2);
	});

	it('trusts the author when the tracks cannot be counted', () => {
		expect(clampSpan(4, null)).toBe(4);
		expect(clampSpan(-1, null)).toBe(1);
	});
});

describe('alignment', () => {
	it('passes the recognized values through', () => {
		for (const value of ['stretch', 'start', 'center', 'end', 'baseline']) {
			expect(alignment(value, 'stretch')).toBe(value);
		}
	});

	it('falls back rather than emitting a value the stylesheet does not know', () => {
		expect(alignment('middle', 'stretch')).toBe('stretch');
		expect(alignment('', 'stretch')).toBe('stretch');
		expect(alignment(undefined, null)).toBeNull();
		expect(alignment(3, null)).toBeNull();
	});
});

// ── Resizable dividers ────────────────────────────────────────────────────────

describe('parseTrackPx', () => {
	it('reads the used widths the browser resolved', () => {
		expect(parseTrackPx('300px 500px')).toEqual([300, 500]);
		expect(parseTrackPx('  300.5px   499.5px  ')).toEqual([300.5, 499.5]);
	});

	it('gives up on anything that is not a clean list of pixel lengths', () => {
		// An unrendered grid, a jsdom stub echoing the var() back, an unresolved
		// repeat(), a stray unit. The caller keeps the authored template instead of
		// dragging against numbers it invented.
		for (const junk of ['none', '', '   ', '1fr 1fr', 'repeat(2, 1fr)', 'var(--x)', '300px 2fr']) {
			expect(parseTrackPx(junk)).toEqual([]);
		}
		expect(parseTrackPx(null)).toEqual([]);
		expect(parseTrackPx(300)).toEqual([]);
	});

	it('rejects a negative track rather than shipping it as a gutter position', () => {
		expect(parseTrackPx('-10px 500px')).toEqual([]);
	});
});

describe('parseGapPx', () => {
	it('reads a pixel gap, and treats a missing one as none', () => {
		expect(parseGapPx('48px')).toBe(48);
		expect(parseGapPx('0px')).toBe(0);
		// grid's initial column-gap. A missing measurement must not shift a handle.
		expect(parseGapPx('normal')).toBe(0);
		expect(parseGapPx(undefined)).toBe(0);
		expect(parseGapPx('-4px')).toBe(0);
	});
});

describe('gutterCenters', () => {
	it('centres one handle in each gutter', () => {
		// tracks 300 | gap 40 | 500 | gap 40 | 300  →  gutters at 300..340 and 840..880
		expect(gutterCenters([300, 500, 300], 40)).toEqual([320, 860]);
	});

	it('collapses to the track edges when there is no gap', () => {
		expect(gutterCenters([300, 500], 0)).toEqual([300]);
	});

	it('has no gutter to centre in a single track — or none at all', () => {
		expect(gutterCenters([500], 40)).toEqual([]);
		expect(gutterCenters([], 40)).toEqual([]);
	});

	it('treats an unusable gap as none rather than emitting NaN positions', () => {
		expect(gutterCenters([300, 500], NaN)).toEqual([300]);
		expect(gutterCenters([300, 500], -10)).toEqual([300]);
	});
});

describe('resizeTracks', () => {
	it('trades width between the two tracks the gutter separates, and no others', () => {
		expect(resizeTracks([300, 500, 300], 0, 100, 40)).toEqual([400, 400, 300]);
		expect(resizeTracks([300, 500, 300], 1, -50, 40)).toEqual([300, 450, 350]);
	});

	it('holds the pair’s sum invariant, so the grid never resizes', () => {
		const before = [300, 500, 300];
		const after = resizeTracks(before, 0, 137.5, 40);
		expect(after[0] + after[1]).toBe(before[0] + before[1]);
		expect(after[2]).toBe(before[2]);
	});

	it('floors both sides at minTrack', () => {
		expect(resizeTracks([300, 500], 0, 1000, 40)).toEqual([760, 40]);
		expect(resizeTracks([300, 500], 0, -1000, 40)).toEqual([40, 760]);
	});

	it('refuses to move a pair too narrow to honour minTrack, rather than jumping', () => {
		const tracks = [30, 30];
		expect(resizeTracks(tracks, 0, 10, 40)).toBe(tracks);
	});

	it('is total: a bad index, a bad delta, a bad track leave the tracks alone', () => {
		const tracks = [300, 500];
		expect(resizeTracks(tracks, 1, 10, 40)).toBe(tracks); // last track has no gutter
		expect(resizeTracks(tracks, -1, 10, 40)).toBe(tracks);
		expect(resizeTracks(tracks, 0, NaN, 40)).toEqual([300, 500]);
		expect(resizeTracks([NaN, 500], 0, 10, 40)).toEqual([NaN, 500]);
	});
});

describe('weightsTemplate', () => {
	it('re-emits the measured px AS fr weights — exact, since they sum to the free space', () => {
		expect(weightsTemplate([700, 500])).toBe('minmax(0, 700fr) minmax(0, 500fr)');
	});

	it('keeps the minmax(0, …) floor, or a wide child would overrule the drag', () => {
		// Every track is wrapped; strip the wrappers and nothing bare is left behind.
		const template = weightsTemplate([700, 500]);
		expect(template.match(/minmax\(0, \d+(\.\d+)?fr\)/g)).toHaveLength(2);
		expect(template.replace(/minmax\(0, \d+(\.\d+)?fr\)/g, '').trim()).toBe('');
	});

	it('yields nothing to apply when there is no ratio to preserve', () => {
		expect(weightsTemplate([])).toBe('');
		expect(weightsTemplate([0, 0])).toBe('');
		expect(weightsTemplate([NaN, 500])).toBe('');
		expect(weightsTemplate([-10, 500])).toBe('');
	});
});

describe('toWeights / formatWidths', () => {
	it('normalizes to weights that average 1, so they read as a ratio', () => {
		expect(toWeights([700, 500])).toEqual([1.17, 0.83]);
		expect(toWeights([300, 300, 300])).toEqual([1, 1, 1]);
	});

	it('never rounds a visible column down to a 0fr one', () => {
		const [big, small] = toWeights([10000, 1]);
		expect(small).toBe(0.01);
		expect(big).toBeGreaterThan(1.9);
	});

	it('formats the snippet a ADJUST Copy puts on the clipboard', () => {
		expect(formatWidths([700, 500])).toBe('widths={[1.17, 0.83]}');
		expect(formatWidths([])).toBe('');
		expect(formatWidths([0, 0])).toBe('');
	});
});
