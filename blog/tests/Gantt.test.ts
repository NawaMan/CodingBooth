import { render } from '@testing-library/svelte';
import { describe, expect, it } from 'vitest';
import Gantt from '../src/lib/chart/Gantt.svelte';

// Structure-only smoke tests (no pixels): span/milestone/arrow counts, lanes kept
// for undated rows, aria-labels carrying the span and duration. The span and
// dependency math is covered exhaustively in chartCore.test.ts (ganttBars /
// ganttLinks); these prove the component wires it up.

type Phase = {
	phase: string;
	from: string;
	to?: string | null;
	done?: number;
	after?: string | string[];
};

const plan: Phase[] = [
	{ phase: 'audit', from: '2026-03-02', to: '2026-03-16', done: 100 },
	{ phase: 'dual-write', from: '2026-03-09', to: '2026-03-27', done: 70, after: 'audit' },
	{ phase: 'cutover', from: '2026-04-20', after: 'dual-write' }, // no end → milestone
	{ phase: 'unscheduled', from: '', to: '' } // no dates → lane only
];

// ISO dates make the labels deterministic regardless of the calendar ladder the
// default formatter would pick for this span.
const iso = (d: Date) => d.toISOString().slice(0, 10);
const base = { task: 'phase', start: 'from', end: 'to', dateFormat: iso, title: 'Plan' };

describe('Gantt', () => {
	it('draws a span per dated range, and no bar for an undated row', () => {
		const { container } = render(Gantt, { props: { data: plan, ...base } });
		expect(container.querySelectorAll('.spans rect.span')).toHaveLength(2);
		expect(container.querySelectorAll('.milestones path.milestone')).toHaveLength(1);
	});

	it('keeps the LANE of an undated row on the y axis', () => {
		const { container } = render(Gantt, { props: { data: plan, ...base } });
		// all four task names label a band, including the one with no bar
		for (const name of ['audit', 'dual-write', 'cutover', 'unscheduled']) {
			expect(container.innerHTML).toContain(name);
		}
	});

	it('labels each span with its dates and duration', () => {
		const { container } = render(Gantt, { props: { data: plan, ...base } });
		const html = container.innerHTML;
		expect(html).toContain('aria-label="audit: 2026-03-02 – 2026-03-16 (14 days)"');
		expect(html).toContain('aria-label="dual-write: 2026-03-09 – 2026-03-27 (18 days)"');
	});

	it('adds the completion percentage to the label only when progress is read', () => {
		const { container } = render(Gantt, {
			props: { data: plan, ...base, progress: 'done' }
		});
		const html = container.innerHTML;
		expect(html).toContain('aria-label="audit: 2026-03-02 – 2026-03-16 (14 days), 100% complete"');
		expect(html).toContain(
			'aria-label="dual-write: 2026-03-09 – 2026-03-27 (18 days), 70% complete"'
		);
	});

	it('labels a milestone as a moment and an undated row as having none', () => {
		const { container } = render(Gantt, {
			props: { data: plan, ...base, progress: 'done' }
		});
		expect(container.innerHTML).toContain('aria-label="cutover: 2026-04-20 (milestone)"');
		// the undated row draws nothing at all, so it carries no bar label
		expect(container.innerHTML).not.toContain('unscheduled: ');
	});

	it('shades progress as a second rect only where progress > 0', () => {
		const { container } = render(Gantt, {
			props: { data: plan, ...base, progress: 'done' }
		});
		const done = container.querySelectorAll('.spans rect.done');
		expect(done).toHaveLength(2); // audit 100%, dual-write 70%
		const [full, partial] = [...done].map((r) => Number(r.getAttribute('width')));
		expect(full).toBeGreaterThan(partial); // 100% shades the whole bar

		const { container: bare } = render(Gantt, { props: { data: plan, ...base } });
		expect(bare.querySelectorAll('.spans rect.done')).toHaveLength(0);
	});

	it('draws a dependency arrow per resolved edge, with an arrowhead marker', () => {
		const { container } = render(Gantt, {
			props: { data: plan, ...base, dependsOn: 'after' }
		});
		const links = container.querySelectorAll('.links path.link');
		expect(links).toHaveLength(2); // audit→dual-write, dual-write→cutover
		expect(links[0].getAttribute('marker-end')).toMatch(/^url\(#chart-gantt-arrow-/);
		expect(container.querySelector('marker')).not.toBeNull();
		// elbow paths are horizontal/vertical runs, never diagonal
		expect(links[0].getAttribute('d')).toMatch(/^M [\d.]+ [\d.]+ H /);
	});

	it('dashes the arrow whose dates contradict the dependency, and only that one', () => {
		// In this fixture dual-write (from 03-09) declares it waits for audit, which
		// only ends on 03-16 — impossible. cutover→dual-write is clean.
		const { container } = render(Gantt, {
			props: { data: plan, ...base, dependsOn: 'after' }
		});
		const links = [...container.querySelectorAll('.links path.link')];
		const bad = links.filter((l) => l.classList.contains('violated'));
		expect(bad).toHaveLength(1);
		// it says WHY, rather than just looking different
		expect(bad[0].querySelector('title')?.textContent).toBe(
			'audit → dual-write: starts before its dependency ends'
		);
		// and it gets the warn arrowhead, not the neutral one
		expect(bad[0].getAttribute('marker-end')).toMatch(/^url\(#chart-gantt-arrow-warn-/);

		const good = links.filter((l) => !l.classList.contains('violated'));
		expect(good).toHaveLength(1);
		expect(good[0].querySelector('title')).toBeNull();
		expect(good[0].getAttribute('marker-end')).toMatch(/^url\(#chart-gantt-arrow-[a-z0-9]/);
	});

	it('draws no arrows without dependsOn', () => {
		const { container } = render(Gantt, { props: { data: plan, ...base } });
		expect(container.querySelectorAll('.links path.link')).toHaveLength(0);
	});

	it('draws a today rule only when the date is usable', () => {
		const { container } = render(Gantt, {
			props: { data: plan, ...base, today: '2026-03-20' }
		});
		expect(container.querySelector('line.today')).not.toBeNull();

		const { container: junk } = render(Gantt, {
			props: { data: plan, ...base, today: 'whenever' }
		});
		expect(junk.querySelector('line.today')).toBeNull();

		const { container: none } = render(Gantt, { props: { data: plan, ...base } });
		expect(none.querySelector('line.today')).toBeNull();
	});

	it('uses the calendar formatter when no dateFormat is given', () => {
		const { container } = render(Gantt, {
			props: { data: plan, task: 'phase', start: 'from', end: 'to', title: 'Plan' }
		});
		// the default labeler writes "Mar 2"-style dates, not ISO or raw ms
		expect(container.innerHTML).toMatch(/aria-label="audit: \w{3} \d+ – \w{3} \d+ \(14 days\)"/);
	});

	it('is an accessible image with a title, description and axis label', () => {
		const { container } = render(Gantt, {
			props: { data: plan, ...base, xLabel: '2026', description: 'the migration plan' }
		});
		const svg = container.querySelector('svg');
		expect(svg?.getAttribute('role')).toBe('img');
		expect(svg?.getAttribute('aria-label')).toBe('Plan');
		expect(container.querySelector('desc')?.textContent).toBe('the migration plan');
		expect(container.innerHTML).toContain('2026');
	});

	it('survives empty data with no NaN in the emitted geometry', () => {
		const { container } = render(Gantt, { props: { data: [], ...base } });
		expect(container.querySelectorAll('.spans rect.span')).toHaveLength(0);
		expect(container.innerHTML).not.toContain('NaN');
	});

	it('emits no NaN for a plan where nothing is placeable', () => {
		const { container } = render(Gantt, {
			props: { data: [{ phase: 'tbd', from: '', to: '' }], ...base }
		});
		expect(container.innerHTML).not.toContain('NaN');
	});
});
