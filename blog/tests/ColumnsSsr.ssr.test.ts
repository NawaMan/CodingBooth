// @vitest-environment node
//
// True server-side render of Columns / Column (svelte/server, no DOM). Both are
// purely declarative — no onMount, no browser APIs — so the whole layout must come
// from props alone, which is what prerendering a slide does. There is no layout
// engine here, so what these lock in is the CONTRACT the stylesheet then reads: the
// track template, the clamped span, the alignment, and the divider wiring a Column
// only learns from its parent over context.
import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';
import Column from '../src/lib/components/Column.svelte';
import Columns from '../src/lib/components/Columns.svelte';
import ColumnsHost from './ColumnsHost.svelte';

const host = (props: Record<string, unknown> = {}) => render(ColumnsHost, { props }).body;

describe('Columns (SSR)', () => {
	it('lays two even, blowout-guarded tracks by default', () => {
		const body = host();
		expect(body).toContain('--columns-tracks: minmax(0, 1fr) minmax(0, 1fr)');
		expect(body).toContain('--columns-align: stretch');
	});

	it('a count builds that many even tracks', () => {
		expect(host({ columns: 3 })).toContain(
			'--columns-tracks: minmax(0, 1fr) minmax(0, 1fr) minmax(0, 1fr)'
		);
	});

	it('widths are the split: an array of weights, or the author’s own template', () => {
		expect(host({ widths: [3, 2] })).toContain('--columns-tracks: 3fr 2fr');
		expect(host({ widths: ['360px', 1] })).toContain('--columns-tracks: 360px 1fr');
		expect(host({ widths: 'repeat(4, 1fr)' })).toContain('--columns-tracks: repeat(4, 1fr)');
	});

	it('stack collapses to one track and drops the rules', () => {
		const body = host({ stack: true, columns: 3, divider: true });
		expect(body).toContain('--columns-tracks: minmax(0, 1fr)');
		expect(body).not.toContain('minmax(0, 1fr) minmax(0, 1fr)');
		expect(body).not.toContain('divided');
	});

	it('divider reaches the columns over context, not a class on the group', () => {
		expect(host({ divider: true })).toContain('divided');
		expect(host()).not.toContain('divided');
	});

	it('an unrecognized alignment falls back rather than emitting an unknown value', () => {
		expect(host({ align: 'center' })).toContain('--columns-align: center');
		expect(host({ align: 'middle' })).toContain('--columns-align: stretch');
	});

	it('emits a gap only when one is set, so the theme token keeps its say', () => {
		expect(host()).not.toContain('--columns-gap');
		expect(host({ gap: '4em' })).toContain('--columns-gap: 4em');
	});

	it('renders no text-mode class outside a Text artifact', () => {
		// getMode() defaults to 'presentation', where the width media query must not
		// apply: the canvas is transform-scaled, so the window's width says nothing.
		expect(render(Columns, { props: {} }).body).not.toMatch(/class="columns[^"]*\btext\b/);
	});

	it('never prerenders a drag handle, even when resizable', () => {
		// The handles are placed from a MEASUREMENT (getComputedStyle resolves `1fr` to
		// used px), which no server has. A prerendered grip would sit at x=0 and drag
		// nothing — the same reason Terminal's transport doesn't prerender.
		const body = host({ resizable: true, divider: true });
		expect(body).not.toContain('role="separator"');
		expect(body).not.toContain('class="handle');
		// ...and the decorative rule DOES prerender, so the gutter is never bare.
		expect(body).toContain('divided');
		expect(body).not.toContain('--columns-rule: none');
	});
});

describe('Column (SSR)', () => {
	it('a plain column carries no span and no alignment of its own', () => {
		const body = host();
		expect(body).toContain('gp-column');
		expect(body).not.toContain('--column-span');
		expect(body).not.toContain('--column-align');
	});

	it('clamps a span to the group’s tracks — grid would silently add a column', () => {
		expect(host({ span: 3, columns: 2 })).toContain('--column-span: 2;');
		expect(host({ span: 2, columns: 3 })).toContain('--column-span: 2;');
	});

	it('trusts the span when the group’s tracks cannot be counted', () => {
		expect(host({ span: 3, widths: 'repeat(4, 1fr)' })).toContain('--column-span: 3;');
	});

	it('overrides the group alignment for itself, ignoring an unknown value', () => {
		expect(host({ columnAlign: 'center' })).toContain('--column-align: center');
		expect(host({ columnAlign: 'middle' })).not.toContain('--column-align');
	});

	it('renders standalone, outside any Columns: no span, no rule, no complaint', () => {
		const { body } = render(Column, { props: { span: 4 } });
		expect(body).toContain('gp-column');
		expect(body).not.toContain('divided');
		expect(body).not.toContain('--column-span');
	});
});
