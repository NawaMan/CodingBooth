import { fireEvent, render, screen } from '@testing-library/svelte';
import { describe, expect, it } from 'vitest';
import CompositionHost from './CompositionHost.svelte';

// The Phase 3 payoff, as a test: a DataTable and a BarChart over ONE dataset and
// ONE shared state. Searching the table reshapes the chart's rects (the shared
// pure pipeline, no chart-specific filter code); selecting a row adds the
// highlight class to that region's bar.

const rects = (root: ParentNode) => Array.from(root.querySelectorAll('.bars rect'));
const rowCheckboxes = (root: ParentNode) =>
	Array.from(root.querySelectorAll('tbody input[type="checkbox"]')) as HTMLInputElement[];
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

describe('Composition — DataTable + BarChart share one dataset and state', () => {
	it('a search in the table reshapes the chart to the filtered subset', async () => {
		const { container } = render(CompositionHost);
		// three regions → three bars
		expect(rects(container)).toHaveLength(3);

		await fireEvent.input(screen.getByLabelText('Search'), { target: { value: 'us-east' } });
		await sleep(350); // the table's search is debounced

		const after = rects(container);
		expect(after).toHaveLength(1); // only the us-east region survives
		expect(after[0].getAttribute('aria-label')).toBe('us-east: 100');
	});

	it('selecting a row highlights that region’s bar and dims the rest', async () => {
		const { container } = render(CompositionHost);
		expect(container.querySelectorAll('.bars rect.hl')).toHaveLength(0); // nothing selected yet

		await fireEvent.click(rowCheckboxes(container)[0]); // select id 1 → region us-east

		const hl = Array.from(container.querySelectorAll('.bars rect.hl'));
		expect(hl).toHaveLength(1);
		expect(hl[0].getAttribute('aria-label')).toBe('us-east: 100');
		expect(container.querySelectorAll('.bars rect.dim')).toHaveLength(2); // the other regions dim
	});
});
