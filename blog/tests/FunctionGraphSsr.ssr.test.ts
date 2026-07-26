// @vitest-environment node
//
// True server-side render (svelte/server, no DOM) of a mathematical function
// plotted with sampleFunction() + the existing LineChart — proving a math graph
// prerenders its complete SVG from props alone, with NO new component. Mirrors
// ChartSsr.ssr.test.ts; this is the prerender guarantee for the
// function-graph.html slide (whose content SlideDeck otherwise gates behind
// onMount).
import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';
import FunctionGraphSsrHost from './FunctionGraphSsrHost.svelte';

describe('Function plot via sampleFunction + LineChart (SSR)', () => {
	const { body } = render(FunctionGraphSsrHost, { props: {} });

	// Both charts render into one body: sin + cos (chart 1) and tan (chart 2) →
	// three `.line` paths, in order.
	const lines = [...body.matchAll(/class="line[^"]*"[^>]*d="([^"]*)"/g)].map((m) => m[1]);

	it('renders sin x and cos x as two continuous single sub-path lines', () => {
		expect(body).toContain('<title>sin and cos</title>');
		expect(lines).toHaveLength(3); // sin, cos, tan across both charts
		// sin & cos are finite everywhere on [-2π, 2π] → each is one unbroken sub-path
		expect(lines[0].match(/M/g)).toHaveLength(1);
		expect(lines[1].match(/M/g)).toHaveLength(1);
	});

	it('breaks tan x into multiple sub-paths at its clamped asymptotes', () => {
		expect(body).toContain('<title>tan x</title>');
		const tan = lines[2]; // the second chart's single series
		// four poles inside (-2π, 2π): ±π/2, ±3π/2 → the pen lifts, several M sub-paths
		expect((tan.match(/M/g) ?? []).length).toBeGreaterThan(1);
	});

	it('never emits NaN or Infinity in any coordinate', () => {
		expect(body).not.toContain('NaN');
		expect(body).not.toContain('Infinity');
	});
});
