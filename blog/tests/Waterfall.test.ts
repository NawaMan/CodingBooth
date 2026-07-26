import { render } from '@testing-library/svelte';
import { describe, expect, it } from 'vitest';
import Waterfall from '../src/lib/chart/Waterfall.svelte';
import type { AxisDef } from '../src/lib/chart/types';

// Structure-only smoke tests (no pixels): rect/step counts, the rise/fall/total
// distinction, aria-labels carrying the running total. The walk arithmetic is
// covered exhaustively in chartCore.test.ts (waterfallBars); these prove the
// component wires it up.

type Stage = { stage: string; cost: number | null; check?: boolean };
const budget: Stage[] = [
	{ stage: 'tls', cost: 180 },
	{ stage: 'query', cost: 90 },
	{ stage: 'cache', cost: -35 }, // falls
	{ stage: 'middleware', cost: null }, // blank → contributes 0, keeps its slot
	{ stage: 'render', cost: 60 }
];
// AxisDef<any> — testing-library's render() can't infer the generic.
const stageX: AxisDef = { value: 'stage', type: 'band', label: 'Stage' };

describe('Waterfall', () => {
	it('draws one bar per row, blanks included (the walk keeps its slots)', () => {
		const { container } = render(Waterfall, {
			props: { data: budget, x: stageX, value: 'cost', title: 'Budget' }
		});
		expect(container.querySelectorAll('.bars rect')).toHaveLength(5);
	});

	it('adds a total column for endTotal', () => {
		const { container } = render(Waterfall, {
			props: { data: budget, x: stageX, value: 'cost', endTotal: true, title: 'Budget' }
		});
		expect(container.querySelectorAll('.bars rect')).toHaveLength(6);
		// 180 + 90 - 35 + 0 + 60 = 295
		expect(container.innerHTML).toContain('aria-label="Total: 295 total"');
	});

	it('labels each bar with its signed contribution and the running total', () => {
		const { container } = render(Waterfall, {
			props: { data: budget, x: stageX, value: 'cost', title: 'Budget' }
		});
		const html = container.innerHTML;
		expect(html).toContain('aria-label="tls: +180 (total 180)"');
		expect(html).toContain('aria-label="query: +90 (total 270)"');
		expect(html).toContain('aria-label="cache: -35 (total 235)"'); // a fall
		expect(html).toContain('aria-label="middleware: no change (total 235)"'); // the blank
		expect(html).toContain('aria-label="render: +60 (total 295)"');
	});

	it('colors rises, falls and totals differently', () => {
		const { container } = render(Waterfall, {
			props: { data: budget, x: stageX, value: 'cost', endTotal: true, title: 'Budget' }
		});
		const fills = [...container.querySelectorAll('.bars rect')].map((r) =>
			r.getAttribute('fill')
		);
		expect(fills[0]).toContain('--chart-rise');
		expect(fills[2]).toContain('--chart-fall'); // the cache saving
		expect(fills[5]).toContain('--chart-total'); // the appended total
	});

	it('draws a step line between each adjacent pair, and none when off', () => {
		const { container } = render(Waterfall, {
			props: { data: budget, x: stageX, value: 'cost', title: 'Budget' }
		});
		expect(container.querySelectorAll('.steps .step')).toHaveLength(4); // 5 bars → 4 gaps

		const { container: bare } = render(Waterfall, {
			props: { data: budget, x: stageX, value: 'cost', connectors: false, title: 'Budget' }
		});
		expect(bare.querySelectorAll('.steps .step')).toHaveLength(0);
	});

	it('marks a zero-thickness bar flat so it stays visible', () => {
		const { container } = render(Waterfall, {
			props: { data: budget, x: stageX, value: 'cost', title: 'Budget' }
		});
		const flat = container.querySelectorAll('.bars rect.flat');
		expect(flat).toHaveLength(1); // the blank middleware stage
		expect(Number(flat[0].getAttribute('height'))).toBeGreaterThan(0);
	});

	it('honours isTotal rows and a seeded start', () => {
		const wins: Stage[] = [
			{ stage: 'old', cost: 0, check: true },
			{ stage: 'index', cost: -640 },
			{ stage: 'mid', cost: null, check: true }
		];
		const { container } = render(Waterfall, {
			props: {
				data: wins,
				x: { value: 'stage', type: 'band' } as AxisDef,
				value: 'cost',
				isTotal: 'check',
				start: 2100,
				title: 'Wins'
			}
		});
		const html = container.innerHTML;
		expect(html).toContain('aria-label="old: 2,100 total"'); // checkpoint at the seed
		expect(html).toContain('aria-label="index: -640 (total 1,460)"');
		expect(html).toContain('aria-label="mid: 1,460 total"'); // checkpoint, walk unmoved
	});

	it('is an accessible image with a title, description and axis labels', () => {
		const { container } = render(Waterfall, {
			props: {
				data: budget,
				x: stageX,
				value: 'cost',
				label: 'Cost',
				title: 'Where the time goes',
				description: 'a running total per stage'
			}
		});
		const svg = container.querySelector('svg');
		expect(svg?.getAttribute('role')).toBe('img');
		expect(svg?.getAttribute('aria-label')).toBe('Where the time goes');
		expect(container.querySelector('title')?.textContent).toBe('Where the time goes');
		expect(container.querySelector('desc')?.textContent).toBe('a running total per stage');
		expect(container.innerHTML).toContain('Stage'); // x axis label
		expect(container.innerHTML).toContain('Cost'); // y axis label
	});

	it('applies `format` to bar labels and y ticks', () => {
		const { container } = render(Waterfall, {
			props: {
				data: budget,
				x: stageX,
				value: 'cost',
				format: (v: number) => `${v} ms`,
				title: 'Budget'
			}
		});
		expect(container.innerHTML).toContain('aria-label="tls: +180 ms (total 180 ms)"');
	});

	it('renders a zero baseline and survives empty data', () => {
		const { container } = render(Waterfall, {
			props: { data: [], x: stageX, value: 'cost', title: 'Nothing yet' }
		});
		expect(container.querySelector('.zero-line')).not.toBeNull();
		expect(container.querySelectorAll('.bars rect')).toHaveLength(0);
		// no NaN leaks into the emitted geometry
		expect(container.innerHTML).not.toContain('NaN');
	});
});
