import { render } from '@testing-library/svelte';
import { describe, expect, it } from 'vitest';
import ColumnsHost from './ColumnsHost.svelte';

// The LIVE half of Columns/Column (the static contract — tracks, spans, alignment —
// is in ColumnsSsr.ssr.test.ts). jsdom has no grid layout engine, so nothing here
// measures a column. What it CAN see is the thing a server render never will: the
// group's track count reaches its Columns over a *store*, not a plain context value,
// so a Column re-clamps its span when the group's shape changes under it. Pass a
// snapshot instead and that link is silently one-way — the first render would be
// right and every one after it stale.

const first = (root: ParentNode) => root.querySelector('.gp-column') as HTMLElement;
const span = (el: HTMLElement) => el.style.getPropertyValue('--column-span');

describe('Columns (live)', () => {
	it('re-clamps a Column’s span when the group grows or shrinks its tracks', async () => {
		// span=3 in a 2-track group is clamped to 2 — grid would otherwise grow a third
		// column to fit it rather than complain.
		const { container, rerender } = render(ColumnsHost, { props: { span: 3, columns: 2 } });
		expect(span(first(container))).toBe('2');

		await rerender({ span: 3, columns: 3 });
		expect(span(first(container))).toBe('3');

		await rerender({ span: 3, columns: 1 });
		// Clamped back to the single track, so the inline var is gone entirely.
		expect(span(first(container))).toBe('');
	});

	it('stack collapses a spanning Column to one track, and restores it', async () => {
		const { container, rerender } = render(ColumnsHost, { props: { span: 2, columns: 2 } });
		expect(span(first(container))).toBe('2');

		await rerender({ span: 2, columns: 2, stack: true });
		expect(span(first(container))).toBe('');

		await rerender({ span: 2, columns: 2, stack: false });
		expect(span(first(container))).toBe('2');
	});

	it('turning the divider off withdraws the rule from every column', async () => {
		const { container, rerender } = render(ColumnsHost, { props: { divider: true } });
		const columns = () => Array.from(container.querySelectorAll('.gp-column'));
		expect(columns().every((el) => el.classList.contains('divided'))).toBe(true);

		await rerender({ divider: false });
		expect(columns().some((el) => el.classList.contains('divided'))).toBe(false);
	});
});
