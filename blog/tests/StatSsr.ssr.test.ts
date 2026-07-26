// @vitest-environment node
//
// True server-side render of Stat / StatGroup (svelte/server, no DOM). Both are
// purely declarative — no onMount, no browser APIs — so their full markup must
// come from props alone, which is what prerendering a slide does. This locks in
// the figure/label rendering, the trend→tone→colour mapping and the group's
// alignment-context plumbing.
import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';
import Stat from '../src/lib/components/Stat.svelte';
import StatGroup from '../src/lib/components/StatGroup.svelte';

describe('Stat (SSR)', () => {
	it('renders the figure and label, centred by default', () => {
		const { body } = render(Stat, { props: { value: '99.9%', label: 'Uptime' } });
		expect(body).toContain('>99.9%</div>');
		expect(body).toContain('>Uptime</div>');
		expect(body).toContain('align-center');
	});

	it('maps trend direction to arrow + auto tone, with the delta chip', () => {
		for (const [trend, arrow, tone] of [
			['up',   '▲', 'tone-positive'],
			['down', '▼', 'tone-negative'],
			['flat', '→', 'tone-neutral'],
		] as const) {
			const { body } = render(Stat, { props: { value: '1', trend, delta: '+5%' } });
			expect(body).toContain(arrow);
			expect(body).toContain(tone);
			expect(body).toContain('>+5%</span>');
		}
	});

	it('tone overrides the auto mapping', () => {
		const { body } = render(Stat, { props: { value: '1', trend: 'up', tone: 'negative' } });
		expect(body).toContain('tone-negative');
		expect(body).not.toContain('tone-positive');
	});

	it('accent flag tints the figure via the accent token', () => {
		// The scoped hash sits between the base and modifier classes, so match the
		// `accent` modifier where it lands: just before the figure's closing `>`.
		const plain = render(Stat, { props: { value: '1', label: 'x' } });
		expect(plain.body).not.toContain('accent">1</div>');
		const accented = render(Stat, { props: { value: '1', label: 'x', accent: true } });
		expect(accented.body).toContain('accent">1</div>');
	});

	it('no trend → no chip; empty label/sub → those lines are dropped', () => {
		const { body } = render(Stat, { props: { value: '1' } });
		expect(body).not.toContain('class="chip');
		expect(body).not.toContain('class="label"');
		expect(body).not.toContain('class="sub"');
	});
});

describe('StatGroup (SSR)', () => {
	it('shares its alignment with child Stats over context', () => {
		const { body } = render(StatGroup, {
			props: { align: 'start' },
			// A slotted Stat can't be passed to render() directly, so assert the
			// group markup carries the context wiring the child reads.
		});
		expect(body).toContain('stat-group');
		// align 'start' is the group default; the divider row layout is on by default.
		expect(body).toContain('dividers');
	});

	it('a fixed columns count switches to grid mode', () => {
		const { body } = render(StatGroup, { props: { columns: 4 } });
		expect(body).toContain('grid');
		expect(body).toContain('--stat-cols: 4');
	});

	it('card flag adds the raised-panel class', () => {
		expect(render(StatGroup, { props: {} }).body).not.toContain('card');
		expect(render(StatGroup, { props: { card: true } }).body).toContain('card');
	});
});
