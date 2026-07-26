import { describe, expect, it } from 'vitest';
import {
	aggregate,
	arcPath,
	areaPath,
	avgOf,
	bandScale,
	bubbleRadius,
	countOf,
	ganttBars,
	ganttExtent,
	ganttLinks,
	groupRows,
	heatmapMatrix,
	histogramBins,
	isBlank,
	linePath,
	linearScale,
	nearestIndex,
	nearestPoint,
	niceTicks,
	numericExtent,
	sampleFunction,
	seriesColor,
	stackExtent,
	stackSeries,
	sumOf,
	timeTicks,
	toNumber,
	toTime,
	valueOf,
	waterfallBars,
	waterfallExtent
} from '../src/lib/chart/chartCore';

describe('isBlank / toNumber', () => {
	it('treats null, undefined and empty string as blank', () => {
		expect(isBlank(null)).toBe(true);
		expect(isBlank(undefined)).toBe(true);
		expect(isBlank('')).toBe(true);
		expect(isBlank(0)).toBe(false);
		expect(isBlank('x')).toBe(false);
		expect(isBlank(false)).toBe(false);
	});

	it('coerces to a finite number or NaN — never silently 0', () => {
		expect(toNumber(42)).toBe(42);
		expect(toNumber('3.5')).toBe(3.5);
		expect(toNumber('  7 ')).toBe(7);
		expect(toNumber(null)).toBeNaN();
		expect(toNumber('')).toBeNaN();
		expect(toNumber('   ')).toBeNaN();
		expect(toNumber('abc')).toBeNaN();
		expect(toNumber(-0)).toBe(-0);
	});
});

describe('valueOf', () => {
	it('resolves a field name or an accessor function', () => {
		const row = { a: 1, b: { c: 2 } };
		expect(valueOf(row, 'a')).toBe(1);
		expect(valueOf(row, (r) => r.b.c)).toBe(2);
	});

	it('is null-safe on missing rows / fields', () => {
		expect(valueOf(null as unknown as { a: number }, 'a')).toBeUndefined();
		expect(valueOf({ a: 1 }, 'missing')).toBeUndefined();
	});
});

describe('numericExtent', () => {
	const rows = [{ v: 3 }, { v: 'N/A' }, { v: null }, { v: 987 }, { v: '' }, { v: 50 }];

	it('returns [min, max] ignoring blanks and non-numbers', () => {
		expect(numericExtent(rows, 'v')).toEqual([3, 987]);
	});

	it('works through an accessor function', () => {
		expect(numericExtent([{ n: '10' }, { n: '2' }], (r) => r.n)).toEqual([2, 10]);
	});

	it('returns [NaN, NaN] when nothing is comparable', () => {
		const [lo, hi] = numericExtent([{ v: null }, { v: 'x' }, { v: '' }], 'v');
		expect(lo).toBeNaN();
		expect(hi).toBeNaN();
	});

	it('handles negative-only and mixed-sign data', () => {
		expect(numericExtent([{ v: -100 }, { v: -3 }], 'v')).toEqual([-100, -3]);
		expect(numericExtent([{ v: -30 }, { v: 70 }, { v: 0 }], 'v')).toEqual([-30, 70]);
	});
});

describe('niceTicks', () => {
	it('covers [3, 987] with round 200-steps 0…1000 (the classic case)', () => {
		expect(niceTicks(3, 987)).toEqual([0, 200, 400, 600, 800, 1000]);
	});

	it('produces a first tick ≤ min and a last tick ≥ max', () => {
		const ticks = niceTicks(17, 63);
		expect(ticks[0]).toBeLessThanOrEqual(17);
		expect(ticks[ticks.length - 1]).toBeGreaterThanOrEqual(63);
	});

	it('falls back to [0, 1] for all-blank / non-finite input', () => {
		expect(niceTicks(NaN, NaN)).toEqual([0, 0.2, 0.4, 0.6, 0.8, 1]);
	});

	it('pads a collapsed span (min === max) toward zero — no NaN, no collapse', () => {
		const ticks = niceTicks(42, 42);
		expect(ticks[0]).toBe(0);
		expect(ticks[ticks.length - 1]).toBeGreaterThanOrEqual(42);
		expect(ticks.length).toBeGreaterThan(1);
		expect(ticks.some(Number.isNaN)).toBe(false);
	});

	it('pads a negative constant toward zero', () => {
		const ticks = niceTicks(-42, -42);
		expect(ticks[ticks.length - 1]).toBe(0);
		expect(ticks[0]).toBeLessThanOrEqual(-42);
	});

	it('pads a zero constant to a unit axis', () => {
		expect(niceTicks(0, 0)).toEqual([0, 0.2, 0.4, 0.6, 0.8, 1]);
	});

	it('handles negative-only domains, including 0 where it falls', () => {
		const ticks = niceTicks(-100, -3);
		expect(ticks[0]).toBeLessThanOrEqual(-100);
		expect(ticks).toContain(0);
	});

	it('handles mixed-sign domains with 0 among the ticks', () => {
		expect(niceTicks(-30, 70)).toContain(0);
	});

	it('normalises reversed input (min > max)', () => {
		expect(niceTicks(987, 3)).toEqual([0, 200, 400, 600, 800, 1000]);
	});

	it('keeps small fractional steps clean (no float fuzz)', () => {
		expect(niceTicks(0, 0.5)).toEqual([0, 0.1, 0.2, 0.3, 0.4, 0.5]);
	});
});

describe('linearScale', () => {
	it('maps domain endpoints onto the range', () => {
		const s = linearScale([0, 100], [0, 400], { nice: false });
		expect(s.map(0)).toBe(0);
		expect(s.map(100)).toBe(400);
		expect(s.map(50)).toBe(200);
	});

	it('maps a blank/uncoercible value to NaN (not 0)', () => {
		const s = linearScale([0, 100], [0, 400]);
		expect(s.map(null)).toBeNaN();
		expect(s.map('')).toBeNaN();
		expect(s.map('x')).toBeNaN();
	});

	it('nices the domain out to round tick bounds by default', () => {
		const s = linearScale([3, 987], [0, 400]);
		expect(s.domain).toEqual([0, 1000]);
		expect(s.ticks).toEqual([0, 200, 400, 600, 800, 1000]);
		expect(s.map(0)).toBe(0);
		expect(s.map(1000)).toBe(400);
	});

	it('zero:true forces the domain to include 0 even for all-positive data', () => {
		const s = linearScale([500, 900], [0, 400], { zero: true });
		expect(s.domain[0]).toBe(0);
		expect(s.map(0)).toBe(0);
	});

	it('zero:true extends an all-negative domain up to 0', () => {
		const s = linearScale([-90, -10], [0, 400], { zero: true });
		expect(s.domain[1]).toBe(0);
	});

	it('falls back to a [0, 1] domain when the extent is non-finite', () => {
		const s = linearScale([NaN, NaN], [0, 400]);
		expect(s.domain).toEqual([0, 1]);
		expect(s.map(0)).toBe(0);
		expect(s.map(1)).toBe(400);
	});

	it('does not collapse or NaN on a flat domain (min === max)', () => {
		const s = linearScale([42, 42], [0, 400]);
		expect(Number.isNaN(s.map(42))).toBe(false);
		expect(s.domain[0]).not.toBe(s.domain[1]);
	});

	it('inverts the range for a top-down y axis', () => {
		const s = linearScale([0, 100], [400, 0], { nice: false });
		expect(s.map(0)).toBe(400);
		expect(s.map(100)).toBe(0);
	});
});

describe('bandScale', () => {
	it('builds a first-seen-order domain, dropping duplicates', () => {
		const s = bandScale(['b', 'a', 'b', 'c', 'a'], [0, 300]);
		expect(s.domain).toEqual(['b', 'a', 'c']);
	});

	it('spaces bands across the range with a positive bandwidth', () => {
		const s = bandScale(['a', 'b', 'c'], [0, 300]);
		expect(s.bandwidth).toBeGreaterThan(0);
		expect(s.step).toBeGreaterThan(s.bandwidth);
		// bands are ordered left-to-right and fit inside the range
		expect(s.map('a')).toBeLessThan(s.map('b'));
		expect(s.map('b')).toBeLessThan(s.map('c'));
		expect(s.map('a')).toBeGreaterThanOrEqual(0);
		expect(s.map('c') + s.bandwidth).toBeLessThanOrEqual(300 + 1e-9);
	});

	it('maps a value outside the domain to NaN', () => {
		const s = bandScale(['a', 'b'], [0, 300]);
		expect(s.map('z')).toBeNaN();
	});

	it('handles a single category without collapsing', () => {
		const s = bandScale(['only'], [0, 300]);
		expect(s.domain).toEqual(['only']);
		expect(s.bandwidth).toBeGreaterThan(0);
		expect(Number.isNaN(s.map('only'))).toBe(false);
	});

	it('handles an empty input (no bands, NaN map)', () => {
		const s = bandScale([], [0, 300]);
		expect(s.domain).toEqual([]);
		expect(s.bandwidth).toBe(0);
		expect(s.map('anything')).toBeNaN();
	});

	it('treats equal Date values as one band', () => {
		const s = bandScale([new Date('2024-01-01'), new Date('2024-01-01')], [0, 300]);
		expect(s.domain).toHaveLength(1);
		expect(Number.isNaN(s.map(new Date('2024-01-01')))).toBe(false);
	});

	it('respects custom padding', () => {
		const tight = bandScale(['a', 'b', 'c'], [0, 300], { paddingInner: 0, paddingOuter: 0 });
		expect(tight.bandwidth).toBe(tight.step);
		expect(tight.map('a')).toBe(0);
	});
});

describe('stackSeries', () => {
	const series = [
		{ key: 'a', value: 'a' },
		{ key: 'b', value: 'b' },
		{ key: 'c', value: 'c' }
	];

	it('accumulates positive segments into running [y0, y1] totals', () => {
		const [row] = stackSeries([{ a: 10, b: 20, c: 5 }], series);
		expect(row).toEqual([
			{ key: 'a', y0: 0, y1: 10, value: 10 },
			{ key: 'b', y0: 10, y1: 30, value: 20 },
			{ key: 'c', y0: 30, y1: 35, value: 5 }
		]);
	});

	it('treats a blank as 0 thickness — the stack above it is undisturbed', () => {
		const [row] = stackSeries([{ a: 10, b: null, c: 5 }], series);
		expect(row[1]).toEqual({ key: 'b', y0: 10, y1: 10, value: 0 }); // zero-thick
		expect(row[2]).toEqual({ key: 'c', y0: 10, y1: 15, value: 5 }); // keeps stacking
	});

	it('stacks negatives on a baseline independent of the positives', () => {
		const [row] = stackSeries([{ a: 10, b: -4, c: -6 }], series);
		expect(row[0]).toEqual({ key: 'a', y0: 0, y1: 10, value: 10 });
		expect(row[1]).toEqual({ key: 'b', y0: 0, y1: -4, value: -4 });
		expect(row[2]).toEqual({ key: 'c', y0: -4, y1: -10, value: -6 });
	});

	it('degenerates to plain [0, value] bars for a single series', () => {
		const stacks = stackSeries([{ a: 7 }, { a: -3 }], [{ key: 'a', value: 'a' }]);
		expect(stacks).toEqual([
			[{ key: 'a', y0: 0, y1: 7, value: 7 }],
			[{ key: 'a', y0: 0, y1: -3, value: -3 }]
		]);
	});

	it('yields one aligned segment array per row', () => {
		const stacks = stackSeries(
			[
				{ a: 1, b: 2, c: 3 },
				{ a: 4, b: 5, c: 6 }
			],
			series
		);
		expect(stacks).toHaveLength(2);
		expect(stacks[0]).toHaveLength(3);
	});
});

describe('stackExtent', () => {
	it('spans the tallest stack and always includes 0', () => {
		const stacks = stackSeries(
			[{ a: 10, b: 20, c: 5 }],
			[
				{ key: 'a', value: 'a' },
				{ key: 'b', value: 'b' },
				{ key: 'c', value: 'c' }
			]
		);
		expect(stackExtent(stacks)).toEqual([0, 35]);
	});

	it('reaches below zero for a negative stack', () => {
		const stacks = stackSeries(
			[{ a: -4, b: -6 }],
			[
				{ key: 'a', value: 'a' },
				{ key: 'b', value: 'b' }
			]
		);
		expect(stackExtent(stacks)).toEqual([-10, 0]);
	});

	it('returns [0, 0] for empty input (still a valid baseline)', () => {
		expect(stackExtent([])).toEqual([0, 0]);
	});
});

describe('ganttBars', () => {
	type Row = { task: string; from: string | null; to?: string | null; done?: unknown };
	const opts = { task: 'task' as const, start: 'from' as const, end: 'to' as const };
	const DAY = 86400000;

	it('turns a start/end pair into a span with a duration and a lane index', () => {
		const bars = ganttBars<Row>(
			[
				{ task: 'a', from: '2026-03-02', to: '2026-03-16' },
				{ task: 'b', from: '2026-03-09', to: '2026-03-12' }
			],
			opts
		);
		expect(bars[0]).toMatchObject({ row: 0, duration: 14 * DAY, milestone: false, blank: false });
		expect(bars[1]).toMatchObject({ row: 1, duration: 3 * DAY });
		expect(bars[0].t1 - bars[0].t0).toBe(14 * DAY);
	});

	it('treats a row with no end as a MILESTONE at its start', () => {
		const [bar] = ganttBars<Row>([{ task: 'cutover', from: '2026-04-20' }], opts);
		expect(bar).toMatchObject({ milestone: true, duration: 0 });
		expect(bar.t1).toBe(bar.t0); // a moment, not an open-ended span
		expect(Number.isFinite(bar.t0)).toBe(true);
	});

	it('normalises a REVERSED pair instead of drawing it inside-out', () => {
		const [bar] = ganttBars<Row>([{ task: 'oops', from: '2026-03-20', to: '2026-03-10' }], opts);
		expect(bar.t0).toBeLessThan(bar.t1);
		expect(bar.duration).toBe(10 * DAY); // positive, never negative
	});

	it('keeps the LANE for a row with no usable start, drawing nothing', () => {
		const bars = ganttBars<Row>(
			[
				{ task: 'a', from: '2026-03-02', to: '2026-03-04' },
				{ task: 'unscheduled', from: '', to: '' },
				{ task: 'c', from: 'not a date', to: '2026-03-09' }
			],
			opts
		);
		expect(bars).toHaveLength(3); // the plan is not silently shortened
		expect(bars[1]).toMatchObject({ blank: true, row: 1 });
		expect(bars[2].blank).toBe(true);
		expect(Number.isNaN(bars[1].t0)).toBe(true);
	});

	it('accepts Dates and raw timestamps, not just ISO strings', () => {
		const d0 = new Date('2026-03-02T00:00:00Z');
		const d1 = new Date('2026-03-05T00:00:00Z');
		const [fromDate] = ganttBars(
			[{ task: 'a', from: d0, to: d1 }],
			{ task: 'task', start: 'from', end: 'to' }
		);
		expect(fromDate.duration).toBe(3 * DAY);
		const [fromMs] = ganttBars(
			[{ task: 'a', from: d0.getTime(), to: d1.getTime() }],
			{ task: 'task', start: 'from', end: 'to' }
		);
		expect(fromMs.duration).toBe(3 * DAY);
	});

	it('clamps progress, rescaling a 0–100 value and zeroing junk', () => {
		const rows: Row[] = [
			{ task: 'a', from: '2026-03-02', to: '2026-03-04', done: 70 }, // percent
			{ task: 'b', from: '2026-03-02', to: '2026-03-04', done: 0.4 }, // fraction
			{ task: 'c', from: '2026-03-02', to: '2026-03-04', done: 250 }, // over
			{ task: 'd', from: '2026-03-02', to: '2026-03-04', done: -5 }, // under
			{ task: 'e', from: '2026-03-02', to: '2026-03-04', done: 'soon' } // junk
		];
		const bars = ganttBars<Row>(rows, { ...opts, progress: 'done' });
		expect(bars.map((b) => b.progress)).toEqual([0.7, 0.4, 1, 0, 0]);
	});

	it('is total: empty rows and a missing field stay NaN-free where it matters', () => {
		expect(ganttBars<Row>([], opts)).toEqual([]);
		const bars = ganttBars([{ task: 'x' }] as never, opts as never);
		expect(bars[0]).toMatchObject({ blank: true, duration: 0, progress: 0 });
	});
});

describe('ganttLinks', () => {
	type Row = { task: string; from: string; to: string; after?: string | string[] };
	const rows: Row[] = [
		{ task: 'a', from: '2026-03-02', to: '2026-03-06' },
		{ task: 'b', from: '2026-03-07', to: '2026-03-11', after: 'a' },
		{ task: 'c', from: '2026-03-12', to: '2026-03-16', after: ['a', 'b'] }
	];
	const bars = ganttBars<Row>(rows, { task: 'task', start: 'from', end: 'to' });

	it('resolves dependencies by task NAME into bar indices', () => {
		const links = ganttLinks<Row>(rows, bars, 'after');
		expect(links).toHaveLength(3);
		expect(links[0]).toMatchObject({ fromKey: 't:a', toKey: 't:b', from: 0, to: 1 });
		expect(links.filter((l) => l.to === 2).map((l) => l.from)).toEqual([0, 1]);
	});

	it('drops an edge naming a task that does not exist, rather than mispointing', () => {
		const withGhost: Row[] = [...rows, { task: 'd', from: '2026-03-17', to: '2026-03-18', after: 'ghost' }];
		const ghostBars = ganttBars<Row>(withGhost, { task: 'task', start: 'from', end: 'to' });
		const links = ganttLinks<Row>(withGhost, ghostBars, 'after');
		expect(links.some((l) => l.to === 3)).toBe(false);
		expect(links).toHaveLength(3); // the real three survive
	});

	it('drops self-dependencies and collapses duplicates', () => {
		const odd: Row[] = [
			{ task: 'a', from: '2026-03-02', to: '2026-03-06' },
			{ task: 'b', from: '2026-03-07', to: '2026-03-11', after: ['a', 'a', 'b'] }
		];
		const oddBars = ganttBars<Row>(odd, { task: 'task', start: 'from', end: 'to' });
		const links = ganttLinks<Row>(odd, oddBars, 'after');
		expect(links).toHaveLength(1);
		expect(links[0]).toMatchObject({ from: 0, to: 1 });
	});

	it('drops an edge touching an unplaceable bar (no geometry to draw)', () => {
		const withBlank = [
			{ task: 'a', from: '', to: '' },
			{ task: 'b', from: '2026-03-07', to: '2026-03-11', after: 'a' }
		] as Row[];
		const blankBars = ganttBars<Row>(withBlank, { task: 'task', start: 'from', end: 'to' });
		expect(ganttLinks<Row>(withBlank, blankBars, 'after')).toEqual([]);
	});

	it('yields nothing when no row declares a dependency', () => {
		expect(ganttLinks<Row>(rows, bars, 'nothing' as never)).toEqual([]);
	});

	// Finish-to-start is the only relationship modelled, so "B waits for A" and
	// "B starts while A is still running" cannot both be true. The contradiction
	// is reported, never silently corrected.
	it('flags a dependent that starts BEFORE its predecessor finishes', () => {
		const clashing: Row[] = [
			{ task: 'cutover', from: '2026-04-20', to: '2026-04-20' },
			{ task: 'drop tables', from: '2026-04-15', to: '2026-04-22', after: 'cutover' }
		];
		const clashBars = ganttBars<Row>(clashing, { task: 'task', start: 'from', end: 'to' });
		const [link] = ganttLinks<Row>(clashing, clashBars, 'after');
		expect(link).toMatchObject({ from: 0, to: 1, violated: true });
	});

	it('does NOT flag touching ends — that is the normal finish-to-start case', () => {
		const touching: Row[] = [
			{ task: 'a', from: '2026-03-02', to: '2026-03-13' },
			{ task: 'b', from: '2026-03-13', to: '2026-03-27', after: 'a' }
		];
		const touchBars = ganttBars<Row>(touching, { task: 'task', start: 'from', end: 'to' });
		expect(ganttLinks<Row>(touching, touchBars, 'after')[0].violated).toBe(false);
	});

	it('leaves a clean chain unflagged, and keeps the violated one in the plan', () => {
		const links = ganttLinks<Row>(rows, bars, 'after');
		expect(links.every((l) => l.violated === false)).toBe(true);
	});

	it('treats a milestone predecessor by its single instant', () => {
		const afterMilestone: Row[] = [
			{ task: 'cutover', from: '2026-04-20' } as Row, // no end → milestone
			{ task: 'after', from: '2026-04-21', to: '2026-04-25', after: 'cutover' }
		];
		const msBars = ganttBars<Row>(afterMilestone, { task: 'task', start: 'from', end: 'to' });
		expect(ganttLinks<Row>(afterMilestone, msBars, 'after')[0].violated).toBe(false);
	});
});

describe('ganttExtent', () => {
	type Row = { task: string; from: string; to?: string | null };
	const build = (rows: Row[]) =>
		ganttBars<Row>(rows, { task: 'task', start: 'from', end: 'to' });

	it('spans the earliest start to the latest end', () => {
		const bars = build([
			{ task: 'a', from: '2026-03-10', to: '2026-03-20' },
			{ task: 'b', from: '2026-03-02', to: '2026-03-08' }
		]);
		expect(ganttExtent(bars)).toEqual([Date.parse('2026-03-02'), Date.parse('2026-03-20')]);
	});

	it('ignores unplaceable rows', () => {
		const bars = build([
			{ task: 'a', from: '2026-03-10', to: '2026-03-20' },
			{ task: 'b', from: '', to: '' }
		]);
		expect(ganttExtent(bars)).toEqual([Date.parse('2026-03-10'), Date.parse('2026-03-20')]);
	});

	it('returns [NaN, NaN] when nothing is placeable (linearScale then falls back)', () => {
		expect(ganttExtent([]).every(Number.isNaN)).toBe(true);
		expect(ganttExtent(build([{ task: 'a', from: '', to: '' }])).every(Number.isNaN)).toBe(true);
	});
});

describe('waterfallBars', () => {
	type Row = { stage: string; cost: number | null; check?: boolean };
	const opts = { x: 'stage' as const, value: 'cost' as const };

	it('walks each bar from the running total before it to the one after', () => {
		const bars = waterfallBars<Row>(
			[
				{ stage: 'a', cost: 10 },
				{ stage: 'b', cost: 20 },
				{ stage: 'c', cost: 5 }
			],
			opts
		);
		expect(bars.map((b) => [b.y0, b.y1, b.total])).toEqual([
			[0, 10, 10],
			[10, 30, 30],
			[30, 35, 35]
		]);
		expect(bars.map((b) => b.kind)).toEqual(['rise', 'rise', 'rise']);
	});

	it('falls for a negative contribution without breaking the walk', () => {
		const bars = waterfallBars<Row>(
			[
				{ stage: 'a', cost: 100 },
				{ stage: 'b', cost: -40 },
				{ stage: 'c', cost: 10 }
			],
			opts
		);
		expect(bars[1]).toMatchObject({ y0: 100, y1: 60, value: -40, kind: 'fall' });
		expect(bars[2]).toMatchObject({ y0: 60, y1: 70, total: 70 });
	});

	it('treats a blank as 0 and KEEPS the bar (the category holds its slot)', () => {
		const bars = waterfallBars<Row>(
			[
				{ stage: 'a', cost: 10 },
				{ stage: 'b', cost: null },
				{ stage: 'c', cost: 5 }
			],
			opts
		);
		expect(bars).toHaveLength(3);
		expect(bars[1]).toMatchObject({ y0: 10, y1: 10, value: 0, blank: true, total: 10 });
		expect(bars[2]).toMatchObject({ y0: 10, y1: 15 }); // walk undisturbed
	});

	it('seeds the walk from `start`, ignoring a non-finite one', () => {
		const [bar] = waterfallBars<Row>([{ stage: 'a', cost: -100 }], { ...opts, start: 2100 });
		expect(bar).toMatchObject({ y0: 2100, y1: 2000, total: 2000 });
		const [fallback] = waterfallBars<Row>([{ stage: 'a', cost: 5 }], {
			...opts,
			start: Number.NaN
		});
		expect(fallback).toMatchObject({ y0: 0, y1: 5 });
	});

	it('draws an `isTotal` row from the baseline and leaves the total unmoved', () => {
		const bars = waterfallBars<Row>(
			[
				{ stage: 'a', cost: 30 },
				{ stage: 'b', cost: 12 },
				{ stage: 'mid', cost: null, check: true },
				{ stage: 'c', cost: 8 }
			],
			{ ...opts, isTotal: 'check' }
		);
		expect(bars[2]).toMatchObject({ y0: 0, y1: 42, value: 42, total: 42, kind: 'total' });
		expect(bars[3]).toMatchObject({ y0: 42, y1: 50 }); // resumes from the same total
	});

	it('appends an endTotal column from the baseline, labelled', () => {
		const bars = waterfallBars<Row>(
			[
				{ stage: 'a', cost: 10 },
				{ stage: 'b', cost: 5 }
			],
			{ ...opts, endTotal: true, endTotalLabel: 'Sum' }
		);
		expect(bars).toHaveLength(3);
		expect(bars[2]).toMatchObject({ category: 'Sum', y0: 0, y1: 15, kind: 'total' });
	});

	it('is total: empty rows, garbage values and a missing field stay NaN-free', () => {
		expect(waterfallBars<Row>([], opts)).toEqual([]);
		const bars = waterfallBars(
			[{ stage: 'a', cost: 'nonsense' }, { stage: 'b' }, { stage: 'c', cost: '12' }],
			opts as never
		);
		for (const bar of bars) {
			expect(Number.isFinite(bar.y0)).toBe(true);
			expect(Number.isFinite(bar.y1)).toBe(true);
			expect(Number.isFinite(bar.total)).toBe(true);
		}
		// only the coercible '12' moved the walk
		expect(bars[2]).toMatchObject({ y0: 0, y1: 12 });
	});

	it('gives each bar a stable key and carries the raw category through', () => {
		const bars = waterfallBars<Row>([{ stage: 'a', cost: 1 }], { ...opts, endTotal: true });
		expect(bars[0].key).toBe('t:a');
		expect(bars[0].category).toBe('a');
		expect(bars[1].key).toBe('t:Total'); // the default endTotalLabel
	});
});

describe('waterfallExtent', () => {
	it('spans the walk and always includes 0', () => {
		const bars = waterfallBars(
			[
				{ s: 'a', v: 10 },
				{ s: 'b', v: 25 }
			],
			{ x: 's', value: 'v' }
		);
		expect(waterfallExtent(bars)).toEqual([0, 35]);
	});

	it('reaches below zero when the walk crosses the baseline', () => {
		const bars = waterfallBars(
			[
				{ s: 'a', v: 10 },
				{ s: 'b', v: -30 }
			],
			{ x: 's', value: 'v' }
		);
		expect(waterfallExtent(bars)).toEqual([-20, 10]);
	});

	it('covers a walk seeded above zero from the baseline up', () => {
		const bars = waterfallBars([{ s: 'a', v: -100 }], { x: 's', value: 'v', start: 500 });
		expect(waterfallExtent(bars)).toEqual([0, 500]);
	});

	it('returns [0, 0] for empty input (still a valid baseline)', () => {
		expect(waterfallExtent([])).toEqual([0, 0]);
	});
});

describe('nearestIndex', () => {
	const xs = [0, 10, 20, 30, 40];

	it('finds an exact hit', () => {
		expect(nearestIndex(xs, 20)).toBe(2);
	});

	it('snaps to the closer neighbour between ticks', () => {
		expect(nearestIndex(xs, 12)).toBe(1); // closer to 10
		expect(nearestIndex(xs, 17)).toBe(2); // closer to 20
	});

	it('breaks an exact midpoint tie toward the lower index', () => {
		expect(nearestIndex(xs, 15)).toBe(1); // 10 vs 20, tie → 10
	});

	it('clamps out-of-range queries to the ends', () => {
		expect(nearestIndex(xs, -100)).toBe(0);
		expect(nearestIndex(xs, 999)).toBe(4);
	});

	it('handles a single element and an empty array', () => {
		expect(nearestIndex([7], 3)).toBe(0);
		expect(nearestIndex([], 3)).toBe(-1);
	});

	it('agrees with a linear scan on random-ish queries', () => {
		const scan = (arr: number[], p: number) => {
			let best = 0;
			for (let i = 1; i < arr.length; i++) {
				if (Math.abs(arr[i] - p) < Math.abs(arr[best] - p)) best = i;
			}
			return best;
		};
		const arr = [2, 5, 9, 14, 22, 31, 50];
		for (const p of [0, 3, 4, 7, 12, 18, 27, 40, 60]) {
			expect(nearestIndex(arr, p)).toBe(scan(arr, p));
		}
	});
});

describe('nearestPoint', () => {
	const pts = [
		{ x: 0, y: 0 },
		{ x: 10, y: 10 },
		{ x: 20, y: 0 },
		{ x: 30, y: 30 }
	];

	it('finds the nearest point by 2D distance', () => {
		expect(nearestPoint(pts, 11, 9)).toBe(1); // hugging (10,10)
		expect(nearestPoint(pts, 19, 2)).toBe(2); // hugging (20,0)
		expect(nearestPoint(pts, 100, 100)).toBe(3); // (30,30) is closest
	});

	it('skips points with a non-finite coordinate (a blanked axis value)', () => {
		const withGap = [
			{ x: NaN, y: 5 },
			{ x: 40, y: 40 },
			{ x: 5, y: Infinity }
		];
		expect(nearestPoint(withGap, 0, 0)).toBe(1); // only the finite point matches
	});

	it('returns -1 when nothing is comparable', () => {
		expect(nearestPoint([], 1, 1)).toBe(-1);
		expect(nearestPoint([{ x: NaN, y: NaN }], 0, 0)).toBe(-1);
	});

	it('breaks ties toward the earlier index', () => {
		const tie = [
			{ x: 0, y: 0 },
			{ x: 2, y: 0 }
		];
		expect(nearestPoint(tie, 1, 0)).toBe(0);
	});
});

describe('bubbleRadius', () => {
	it('maps the domain endpoints onto the radius range', () => {
		expect(bubbleRadius(0, [0, 100], [4, 20])).toBeCloseTo(4);
		expect(bubbleRadius(100, [0, 100], [4, 20])).toBeCloseTo(20);
	});

	it('scales AREA (not radius) linearly — the midpoint value sits between in r²', () => {
		const r = bubbleRadius(50, [0, 100], [0, 10]);
		// area-proportional: r² is half of the max r², so r = sqrt(50) ≈ 7.07
		expect(r).toBeCloseTo(Math.sqrt(50));
		expect(r).toBeGreaterThan(5); // and NOT the radius-midpoint 5
	});

	it('falls back to the smallest radius for a blank / non-finite value', () => {
		expect(bubbleRadius(null, [0, 100], [4, 20])).toBe(4);
		expect(bubbleRadius('nope', [0, 100], [4, 20])).toBe(4);
	});

	it('gives the mid radius for a flat or non-finite domain', () => {
		expect(bubbleRadius(5, [7, 7], [4, 20])).toBe(12);
		expect(bubbleRadius(5, [NaN, NaN], [4, 20])).toBe(12);
	});

	it('clamps values outside the domain to the range', () => {
		expect(bubbleRadius(-50, [0, 100], [4, 20])).toBeCloseTo(4);
		expect(bubbleRadius(999, [0, 100], [4, 20])).toBeCloseTo(20);
	});
});

describe('seriesColor', () => {
	it('prefers an explicit SeriesDef.color', () => {
		expect(seriesColor('#abc', 3)).toBe('#abc');
	});

	it('falls back to --chart-series-{i+1} with a palette default', () => {
		expect(seriesColor(undefined, 0)).toBe('var(--chart-series-1, #4c78a8)');
		expect(seriesColor(undefined, 1)).toBe('var(--chart-series-2, #f58518)');
	});

	it('wraps the palette default past eight series (var index keeps counting)', () => {
		expect(seriesColor(undefined, 8)).toBe('var(--chart-series-9, #4c78a8)');
	});
});

describe('toTime', () => {
	it('reads a Date, passes a number through, parses an ISO string', () => {
		const d = new Date(2024, 0, 15);
		expect(toTime(d)).toBe(d.getTime());
		expect(toTime(1700000000000)).toBe(1700000000000);
		expect(toTime('2024-01-01')).toBe(new Date('2024-01-01').getTime());
	});

	it('returns NaN for blanks and invalid dates', () => {
		expect(toTime(null)).toBeNaN();
		expect(toTime('')).toBeNaN();
		expect(toTime('not a date')).toBeNaN();
	});
});

describe('timeTicks', () => {
	// Local Date(y, m, d) constructors keep these robust across timezones — the
	// floor/step logic works in local calendar fields.
	const labels = (min: Date, max: Date, count?: number) => {
		const t = timeTicks(min.getTime(), max.getTime(), count);
		return { ticks: t.ticks, labels: t.ticks.map((v) => t.format(v)) };
	};

	it('a ~3-year span yields year ticks (no numeric spam)', () => {
		const { ticks, labels: ls } = labels(new Date(2021, 0, 1), new Date(2024, 0, 1));
		expect(ls.every((l) => /^\d{4}$/.test(l))).toBe(true);
		expect(ticks.length).toBeLessThanOrEqual(7);
		expect(ls).toContain('2022');
	});

	it('a ~6-month span yields month ticks', () => {
		const { labels: ls } = labels(new Date(2024, 0, 1), new Date(2024, 6, 1));
		expect(ls).toContain('Feb 2024');
		expect(ls.every((l) => /^[A-Z][a-z]{2} \d{4}$/.test(l))).toBe(true);
	});

	it('a ~2-week span yields day ticks — no overlapping spam', () => {
		const { ticks, labels: ls } = labels(new Date(2024, 0, 1), new Date(2024, 0, 15));
		expect(ticks.length).toBeLessThanOrEqual(8);
		expect(ls.every((l) => /^[A-Z][a-z]{2} \d{1,2}$/.test(l))).toBe(true);
		expect(ls[0]).toBe('Jan 1');
	});

	it('lands every tick on a local calendar boundary across a DST change', () => {
		// March 2024 contains the US spring-forward; calendar stepping (not fixed
		// ms) must keep each tick at local midnight regardless.
		const { ticks } = labels(new Date(2024, 2, 1), new Date(2024, 2, 31));
		expect(ticks.length).toBeGreaterThan(1);
		for (const t of ticks) {
			const d = new Date(t);
			expect(d.getHours()).toBe(0);
			expect(d.getMinutes()).toBe(0);
		}
	});

	it('keeps ticks ascending and inside [min, max]', () => {
		const min = new Date(2024, 0, 1).getTime();
		const max = new Date(2024, 5, 1).getTime();
		const { ticks } = timeTicks(min, max);
		for (let i = 1; i < ticks.length; i++) expect(ticks[i]).toBeGreaterThan(ticks[i - 1]);
		expect(ticks[0]).toBeGreaterThanOrEqual(min);
		expect(ticks[ticks.length - 1]).toBeLessThanOrEqual(max);
	});

	it('degenerates to a single tick when min === max', () => {
		const t = new Date(2024, 3, 10).getTime();
		expect(timeTicks(t, t).ticks).toEqual([t]);
	});

	it('normalises reversed input', () => {
		const a = new Date(2024, 0, 1).getTime();
		const b = new Date(2024, 6, 1).getTime();
		expect(timeTicks(b, a).ticks).toEqual(timeTicks(a, b).ticks);
	});
});

describe('linePath', () => {
	it('draws a single connected sub-path for all-finite points', () => {
		const d = linePath([
			{ x: 0, y: 10 },
			{ x: 10, y: 20 },
			{ x: 20, y: 5 }
		]);
		expect(d).toBe('M 0 10 L 10 20 L 20 5');
	});

	it('breaks into two sub-paths across a NaN y — a gap, not a dip to 0', () => {
		const d = linePath([
			{ x: 0, y: 10 },
			{ x: 10, y: NaN },
			{ x: 20, y: 30 }
		]);
		// the blank point is absent entirely — the line never routes through y=0
		expect(d).toBe('M 0 10 M 20 30');
		expect(d).not.toContain('L'); // no segment drawn across the gap
		// exactly two moves = two sub-paths = a visible gap
		expect(d.match(/M/g)).toHaveLength(2);
	});

	it('gaps on a non-finite x too', () => {
		const d = linePath([
			{ x: 0, y: 1 },
			{ x: Infinity, y: 2 },
			{ x: 2, y: 3 }
		]);
		expect(d.match(/M/g)).toHaveLength(2);
	});

	it('starts a fresh sub-path after a leading gap', () => {
		const d = linePath([
			{ x: 0, y: NaN },
			{ x: 10, y: 5 },
			{ x: 20, y: 6 }
		]);
		expect(d).toBe('M 10 5 L 20 6');
	});

	it('rounds coordinates to keep the path short', () => {
		expect(linePath([{ x: 1.23456, y: 7.89123 }])).toBe('M 1.23 7.89');
	});

	it('returns an empty string when there is nothing drawable', () => {
		expect(linePath([])).toBe('');
		expect(linePath([{ x: NaN, y: NaN }])).toBe('');
	});
});

describe('areaPath', () => {
	const flatBase = (top: { x: number; y: number }[], y0: number) =>
		top.map((p) => ({ x: p.x, y: y0 }));

	it('traces the top edge forward, the base edge back, and closes with Z', () => {
		const top = [
			{ x: 0, y: 10 },
			{ x: 10, y: 4 },
			{ x: 20, y: 8 }
		];
		const d = areaPath(top, flatBase(top, 40));
		// top L→R, then base R→L, then close
		expect(d).toBe('M 0 10 L 10 4 L 20 8 L 20 40 L 10 40 L 0 40 Z');
		expect(d.endsWith('Z')).toBe(true);
	});

	it('breaks a run into separate closed sub-polygons across a blank top (a gap)', () => {
		const top = [
			{ x: 0, y: 10 },
			{ x: 10, y: NaN }, // blank → the area gaps here
			{ x: 20, y: 8 },
			{ x: 30, y: 6 }
		];
		const d = areaPath(top, flatBase(top, 40));
		// two runs → two M commands, each its own closed sub-polygon
		expect(d.match(/M/g)).toHaveLength(2);
		expect(d.match(/Z/g)).toHaveLength(2);
		expect(d).not.toContain('NaN');
	});

	it('breaks a run when the base edge is blank too (stacked pinch below)', () => {
		const top = [
			{ x: 0, y: 5 },
			{ x: 10, y: 4 },
			{ x: 20, y: 3 }
		];
		const base = [
			{ x: 0, y: 40 },
			{ x: 10, y: NaN }, // blank base → break
			{ x: 20, y: 40 }
		];
		expect(areaPath(top, base).match(/M/g)).toHaveLength(2);
	});

	it('rounds coordinates and returns "" when nothing is drawable', () => {
		expect(areaPath([{ x: 1.23456, y: 2 }], [{ x: 1.23456, y: 9 }])).toBe('M 1.23 2 L 1.23 9 Z');
		expect(areaPath([], [])).toBe('');
		expect(areaPath([{ x: NaN, y: NaN }], [{ x: NaN, y: NaN }])).toBe('');
	});
});

describe('sampleFunction', () => {
	it('samples y = f(x) into `samples` points, hitting both endpoints exactly', () => {
		const pts = sampleFunction((x) => 2 * x, [0, 10], 6);
		expect(pts).toHaveLength(6);
		expect(pts[0]).toEqual({ x: 0, y: 0 });
		expect(pts[5]).toEqual({ x: 10, y: 20 }); // last point lands ON x1, no float drift
		expect(pts[1]).toEqual({ x: 2, y: 4 });
	});

	it('keeps a non-finite result as a non-finite y so linePath gaps it', () => {
		const pts = sampleFunction((x) => 1 / x, [-1, 1], 3); // middle sample at x = 0
		expect(pts[1].x).toBe(0);
		expect(Number.isFinite(pts[1].y)).toBe(false); // 1/0 → Infinity, kept as a gap
		expect(linePath(pts)).not.toContain('Infinity');
		expect((linePath(pts).match(/M /g) ?? []).length).toBe(2); // pen lifts → two sub-paths
	});

	it('turns a thrown domain error into a gap (NaN), never a crash', () => {
		const pts = sampleFunction(
			(x) => {
				if (x < 0) throw new Error('domain');
				return Math.sqrt(x);
			},
			[-1, 1],
			3
		);
		expect(Number.isNaN(pts[0].y)).toBe(true); // threw → NaN
		expect(pts[2].y).toBeCloseTo(1);
	});

	it('coerces a non-number return (NaN, Infinity survive) and orders a reversed domain', () => {
		const pts = sampleFunction(() => Math.sqrt(-1), [0, 1], 2); // NaN
		expect(pts.every((p) => Number.isNaN(p.y))).toBe(true);
		const rev = sampleFunction((x) => x, [10, 0], 3);
		expect(rev.map((p) => p.x)).toEqual([0, 5, 10]); // sorted ascending
	});

	it('degenerates safely: non-finite domain → [], zero-width → one point', () => {
		expect(sampleFunction((x) => x, [NaN, 1])).toEqual([]);
		expect(sampleFunction((x) => x * x, [3, 3])).toEqual([{ x: 3, y: 9 }]);
	});
});
describe('aggregation — groupRows / aggregate / reducers', () => {
	type Row = { region: string; requests: number | string | null };
	const rows: Row[] = [
		{ region: 'us-east', requests: 100 },
		{ region: 'us-west', requests: 200 },
		{ region: 'us-east', requests: 300 },
		{ region: 'us-west', requests: 'N/A' }, // blank measure (uncoercible)
		{ region: 'eu', requests: null } // blank measure
	];

	it('groupRows buckets by accessor in first-seen order, keeping row order', () => {
		const groups = groupRows(rows, 'region');
		expect(groups.map((g) => g.group)).toEqual(['us-east', 'us-west', 'eu']);
		expect(groups[0].rows).toHaveLength(2);
		expect(groups[0].rows.map((r) => r.requests)).toEqual([100, 300]); // original order
		expect(groups[2].rows).toHaveLength(1); // eu, one blank row
	});

	it('groupRows accepts a function accessor and keeps a blank group as its own bucket', () => {
		const withBlank: Row[] = [...rows, { region: '', requests: 5 }];
		const groups = groupRows(withBlank, (r) => r.region);
		expect(groups.map((g) => g.group)).toEqual(['us-east', 'us-west', 'eu', '']);
	});

	it('aggregate produces {group, value, count} rows in group order', () => {
		const out = aggregate(rows, 'region', { value: sumOf('requests'), label: 'Requests' });
		expect(out).toEqual([
			{ group: 'us-east', value: 400, count: 2 },
			{ group: 'us-west', value: 200, count: 2 }, // 200 + blank(skipped)
			{ group: 'eu', value: 0, count: 1 } // all-blank group sums to 0
		]);
	});

	it('sumOf skips blanks (never adds them as 0) and an all-blank group sums to 0', () => {
		expect(sumOf('requests')(rows.filter((r) => r.region === 'us-west'))).toBe(200);
		expect(sumOf('requests')([{ region: 'x', requests: null }])).toBe(0);
	});

	it('avgOf skips blanks in BOTH the sum and the divisor — a blank does not drag it toward 0', () => {
		// us-west: 200 and one blank → mean of just [200] = 200, not 100.
		const avg = avgOf('requests');
		expect(avg(rows.filter((r) => r.region === 'us-west'))).toBe(200);
		expect(
			avg([
				{ region: 'x', requests: 100 },
				{ region: 'x', requests: 300 }
			])
		).toBe(200);
		expect(avg([{ region: 'x', requests: null }])).toBe(0); // all-blank → 0, not NaN
	});

	it('countOf() counts every row; countOf(accessor) counts only non-blank measures', () => {
		const groups = groupRows(rows, 'region');
		const west = groups[1].rows; // 200 and a blank
		expect(countOf()(west)).toBe(2); // both rows
		expect(countOf('requests')(west)).toBe(1); // only the non-blank one
		// aggregate's own `count` field is always the group's row count
		const out = aggregate(rows, 'region', { value: countOf('requests') });
		expect(out.map((r) => [r.group, r.value, r.count])).toEqual([
			['us-east', 2, 2],
			['us-west', 1, 2], // 1 non-blank value, 2 rows
			['eu', 0, 1]
		]);
	});

	it('aggregate over an empty set yields no rows', () => {
		expect(aggregate([] as Row[], 'region', { value: sumOf('requests') })).toEqual([]);
	});
});

describe('arcPath', () => {
	// cx=100, cy=100, r=50: angle 0 = top (100,50), π/2 = right (150,100),
	// π = bottom (100,150), 3π/2 = left (50,100).
	const HALF = Math.PI;
	const QUARTER = Math.PI / 2;
	const TAU = Math.PI * 2;

	it('draws a solid wedge from the centre across a quadrant', () => {
		expect(arcPath(100, 100, 50, 0, 0, QUARTER)).toBe('M 100 100 L 100 50 A 50 50 0 0 1 150 100 Z');
	});

	it('keeps the large-arc flag 0 for a half turn and 1 past it', () => {
		// exactly a semicircle (span === π): still the short-arc flag
		expect(arcPath(100, 100, 50, 0, 0, HALF)).toContain('A 50 50 0 0 1 100 150');
		// three quarters (span > π): large-arc flag flips to 1
		expect(arcPath(100, 100, 50, 0, 0, 3 * QUARTER)).toContain('A 50 50 0 1 1 50 100');
	});

	it('cuts a ring segment (two radii, an L between the arcs) when innerR > 0', () => {
		const d = arcPath(100, 100, 50, 25, 0, QUARTER);
		expect(d).toBe('M 100 50 A 50 50 0 0 1 150 100 L 125 100 A 25 25 0 0 0 100 75 Z');
		expect(d).not.toContain('M 100 100'); // a donut segment never touches the centre
	});

	it('draws a full circle as TWO half-circle arcs (not a degenerate single arc)', () => {
		const disc = arcPath(100, 100, 50, 0, 0, TAU);
		expect((disc.match(/A /g) ?? []).length).toBe(2); // two semicircles
		expect(disc.startsWith('M 100 50')).toBe(true);
		expect(disc).not.toContain('L'); // a full disc has no radial edge
	});

	it('draws a full donut ring as two outer + two inner arcs', () => {
		const ring = arcPath(100, 100, 50, 25, 0, TAU);
		expect((ring.match(/A 50 50/g) ?? []).length).toBe(2); // outer ring
		expect((ring.match(/A 25 25/g) ?? []).length).toBe(2); // inner hole
	});

	it('returns "" for a zero-size or reversed slice, or a non-positive radius', () => {
		expect(arcPath(100, 100, 50, 0, 1, 1)).toBe(''); // zero span
		expect(arcPath(100, 100, 50, 0, 2, 1)).toBe(''); // reversed
		expect(arcPath(100, 100, 0, 0, 0, QUARTER)).toBe(''); // no radius
	});

	it('never emits NaN, even at the quadrant boundaries', () => {
		for (let k = 0; k <= 4; k++) {
			expect(arcPath(100, 100, 50, 20, 0, (k * Math.PI) / 2 || 0.001)).not.toContain('NaN');
		}
	});
});
describe('histogramBins', () => {
	const sum = (bins: { count: number }[]) => bins.reduce((s, b) => s + b.count, 0);

	it('bins a sample into contiguous, ascending edges that count every value', () => {
		const bins = histogramBins([1, 2, 2, 3, 5, 8, 9, 10]);
		expect(bins.length).toBeGreaterThan(1);
		// edges are contiguous: each bin's x1 is the next bin's x0
		for (let i = 1; i < bins.length; i++) expect(bins[i].x0).toBe(bins[i - 1].x1);
		// every value fell into some bin
		expect(sum(bins)).toBe(8);
	});

	it('drops blanks and non-finite values (never counts them as 0)', () => {
		const bins = histogramBins([1, 2, null, '', undefined, NaN, Infinity, 'x', 9] as unknown[]);
		expect(sum(bins)).toBe(3); // only 1, 2, 9 are finite numbers
	});

	it('is half-open [x0, x1) with a CLOSED final bin (the max is never dropped)', () => {
		// explicit edges make the boundary rule easy to read: [0,10) [10,20) [20,30]
		const bins = histogramBins([0, 10, 20, 30], { edges: [0, 10, 20, 30] });
		expect(bins.map((b) => b.count)).toEqual([1, 1, 2]); // 20 → 3rd bin, 30 → closed last
		expect(sum(bins)).toBe(4);
	});

	it('honours an explicit bin count (snapped to round edges)', () => {
		const values = Array.from({ length: 50 }, (_, i) => i); // 0..49
		const bins = histogramBins(values, { bins: 5 });
		expect(sum(bins)).toBe(50);
		// nice edges over [0,49] with ~5 bins land on tens
		expect(bins[0].x0).toBe(0);
		expect(bins.every((b) => Number.isFinite(b.x0) && Number.isFinite(b.x1))).toBe(true);
	});

	it('sanitises explicit edges: unsorted, duplicated, and non-finite are cleaned', () => {
		const bins = histogramBins([1, 2, 3], { edges: [3, 1, 2, 2, NaN, Infinity] });
		expect(bins.map((b) => [b.x0, b.x1])).toEqual([
			[1, 2],
			[2, 3]
		]);
	});

	it('clamps to an explicit domain, dropping values outside it', () => {
		const bins = histogramBins([-5, 0, 3, 7, 20], { domain: [0, 10] });
		expect(bins[0].x0).toBe(0);
		expect(bins[bins.length - 1].x1).toBe(10);
		expect(sum(bins)).toBe(3); // -5 and 20 dropped; 0, 3, 7 kept
	});

	it('gives a single distinct value a real, centred bin instead of a zero-width one', () => {
		const bins = histogramBins([5, 5, 5]);
		expect(bins.length).toBeGreaterThanOrEqual(1);
		expect(sum(bins)).toBe(3);
		expect(bins[0].x1).toBeGreaterThan(bins[0].x0);
	});

	it('returns [] when there is neither data nor a domain', () => {
		expect(histogramBins([])).toEqual([]);
		expect(histogramBins([null, '', NaN] as unknown[])).toEqual([]);
	});

	it('falls back to computed edges when explicit edges are unusable', () => {
		const bins = histogramBins([1, 2, 3], { edges: [5] });
		expect(bins.length).toBeGreaterThan(0);
		expect(sum(bins)).toBe(3);
	});
});

describe('heatmapMatrix', () => {
	type Row = { d: string; s: string; v: number | null };
	// Find the single cell at (x, y) — the component looks up by scale, the test
	// by category, so the row-major cell order never leaks into the assertions.
	const at = (m: ReturnType<typeof heatmapMatrix>, x: unknown, y: unknown) =>
		m.cells.find((c) => c.x === x && c.y === y);

	it('pivots rows into the FULL grid, categories in first-seen order', () => {
		const rows: Row[] = [
			{ d: 'Mon', s: 'AM', v: 1 },
			{ d: 'Tue', s: 'AM', v: 3 },
			{ d: 'Mon', s: 'PM', v: 5 }
		];
		const m = heatmapMatrix(rows, { x: 'd', y: 's', value: 'v' });
		expect(m.xs).toEqual(['Mon', 'Tue']); // first-seen
		expect(m.ys).toEqual(['AM', 'PM']);
		expect(m.cells).toHaveLength(4); // 2×2 full grid, missing combos included
		expect(at(m, 'Mon', 'AM')?.value).toBe(1);
		expect(at(m, 'Tue', 'AM')?.value).toBe(3);
		// Tue × PM never appeared → an explicit blank cell, not a hole
		expect(at(m, 'Tue', 'PM')?.value).toBeNull();
	});

	it('averages rows sharing a cell, excluding blanks from the mean', () => {
		const rows: Row[] = [
			{ d: 'Mon', s: 'AM', v: 2 },
			{ d: 'Mon', s: 'AM', v: null }, // dropped, not counted as 0
			{ d: 'Mon', s: 'AM', v: 4 }
		];
		const m = heatmapMatrix(rows, { x: 'd', y: 's', value: 'v' });
		expect(at(m, 'Mon', 'AM')?.value).toBe(3); // mean(2, 4), not mean(2, 0, 4)
	});

	it('leaves an all-blank cell null (never the low-end colour)', () => {
		const rows: Row[] = [
			{ d: 'Mon', s: 'AM', v: null },
			{ d: 'Tue', s: 'AM', v: 6 }
		];
		const m = heatmapMatrix(rows, { x: 'd', y: 's', value: 'v' });
		const blank = at(m, 'Mon', 'AM');
		expect(blank?.value).toBeNull();
		expect(blank?.t).toBeNaN(); // a blank never lands on the ramp
	});

	it('normalises values to t ∈ [0,1] across the data extent', () => {
		const rows: Row[] = [
			{ d: 'Mon', s: 'AM', v: 1 },
			{ d: 'Tue', s: 'AM', v: 3 },
			{ d: 'Mon', s: 'PM', v: 5 }
		];
		const m = heatmapMatrix(rows, { x: 'd', y: 's', value: 'v' });
		expect([m.min, m.max]).toEqual([1, 5]);
		expect(at(m, 'Mon', 'AM')?.t).toBe(0); // min → 0
		expect(at(m, 'Mon', 'PM')?.t).toBe(1); // max → 1
		expect(at(m, 'Tue', 'AM')?.t).toBe(0.5); // midway
	});

	it('maps a flat matrix (every value equal) to t = 0.5', () => {
		const rows: Row[] = [
			{ d: 'Mon', s: 'AM', v: 7 },
			{ d: 'Tue', s: 'AM', v: 7 }
		];
		const m = heatmapMatrix(rows, { x: 'd', y: 's', value: 'v' });
		expect(at(m, 'Mon', 'AM')?.t).toBe(0.5);
		expect(at(m, 'Tue', 'AM')?.t).toBe(0.5);
	});

	it('honours a colour-scale domain override, clamping t', () => {
		const rows: Row[] = [
			{ d: 'Mon', s: 'AM', v: 0 },
			{ d: 'Tue', s: 'AM', v: 50 }
		];
		const m = heatmapMatrix(rows, { x: 'd', y: 's', value: 'v', domain: [0, 100] });
		expect([m.min, m.max]).toEqual([0, 100]);
		expect(at(m, 'Tue', 'AM')?.t).toBe(0.5); // 50 of [0,100], not of [0,50]
	});

	it('ignores a degenerate domain override', () => {
		const rows: Row[] = [{ d: 'Mon', s: 'AM', v: 2 }];
		const m = heatmapMatrix(rows, { x: 'd', y: 's', value: 'v', domain: [5, 5] });
		expect([m.min, m.max]).toEqual([2, 2]); // fell back to the data extent
	});

	it('is total on empty / all-blank input', () => {
		const empty = heatmapMatrix([] as Row[], { x: 'd', y: 's', value: 'v' });
		expect(empty.xs).toEqual([]);
		expect(empty.ys).toEqual([]);
		expect(empty.cells).toEqual([]);
		expect(empty.min).toBeNaN();
		expect(empty.max).toBeNaN();

		const allBlank = heatmapMatrix([{ d: 'Mon', s: 'AM', v: null }] as Row[], {
			x: 'd',
			y: 's',
			value: 'v'
		});
		expect(allBlank.min).toBeNaN(); // no finite value → no colour scale
		expect(at(allBlank, 'Mon', 'AM')?.value).toBeNull();
	});
});
