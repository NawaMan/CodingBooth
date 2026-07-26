// @vitest-environment node
//
// True server-side render of Tabs / Tab (svelte/server, no DOM). The interactive
// parts (the roving keyboard, focus) can't and shouldn't prerender, but the
// STRUCTURE must: the tablist strip, one button per registered tab (with its label
// and icon), the tabpanels, and the initial selection. The load-bearing bit is that
// the strip's {#each $tabs} sits AFTER <slot/> in the template, so a Tab registering
// its label during slot render is visible to the strip in a single SSR pass — the
// same ordering Carousel's dot row relies on. If that broke, the strip would render
// empty here.
import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';
import Tab from '../src/lib/components/Tab.svelte';
import TabsHost from './TabsHost.svelte';

const host = (props: Record<string, unknown> = {}) => render(TabsHost, { props }).body;

describe('Tabs + Tab (SSR)', () => {
	it('draws a tablist with one button per registered tab, labels and all', () => {
		const body = host();
		expect(body).toContain('role="tablist"');
		// One <button role="tab"> per Tab, in document order.
		expect((body.match(/role="tab"/g) ?? []).length).toBe(3);
		expect(body).toContain('JavaScript');
		expect(body).toContain('Python');
		expect(body).toContain('Go');
	});

	it('renders a tabpanel per Tab (the content survives the server render)', () => {
		const body = host();
		expect((body.match(/role="tabpanel"/g) ?? []).length).toBe(3);
		expect(body).toContain('const a = 1;');
		expect(body).toContain('a = 1');
	});

	it('the first tab is selected by default — aria-selected and the active panel', () => {
		const body = host();
		expect(body).toContain('aria-selected="true"');
		// Exactly one selected tab, and exactly one panel that isn't aria-hidden
		// (the scope hash sits between `panel` and `active`, so match on the panels'
		// hidden state instead of the class-name pair).
		expect((body.match(/aria-selected="true"/g) ?? []).length).toBe(1);
		expect((body.match(/aria-hidden="true"/g) ?? []).length).toBe(2); // 2 of 3 hidden
	});

	it('start selects a later tab (clamped, off a disabled one)', () => {
		// start=1 → the Python tab is active.
		const body = host({ start: 1 });
		expect(body).toContain('aria-label="Python"');
		// The active panel is the Python one; its aria-hidden is absent while the
		// others carry it.
		expect((body.match(/aria-hidden="true"/g) ?? []).length).toBe(2);
	});

	it('a disabled tab renders a disabled button and is never the initial selection', () => {
		// start=2 lands on the disabled Go tab → nudged back to the first enabled one.
		const body = host({ start: 2 });
		expect(body).toContain('disabled');
		// Selection fell to JavaScript (index 0), not the disabled Go: the active
		// button is the first one, and its label follows the aria-selected marker.
		const firstSelected = body.indexOf('aria-selected="true"');
		expect(body.slice(firstSelected, firstSelected + 200)).toContain('JavaScript');
	});

	it('an icon renders before its label in the strip', () => {
		expect(host()).toContain('🐍');
	});

	it('align reaches the group class; transition="none" zeroes the fade duration', () => {
		expect(host({ align: 'center' })).toContain('align-center');
		// Unknown align falls back to start rather than emitting a dead class.
		expect(host({ align: 'sideways' })).toContain('align-start');
		expect(host({ transition: 'none' })).toContain('--tabs-dur: 0s');
	});

	it('a Tab used standalone (no Tabs) just shows its content', () => {
		const { body } = render(Tab, { props: { label: 'Lonely' } });
		// No context → the panel is simply active/visible; it does not throw.
		expect(body).toContain('role="tabpanel"');
	});

	it('text mode drops the strip and shows every panel in flow under its label', () => {
		const body = host({ mode: 'text' });
		// No tablist / tab buttons — a reader can't click a tab.
		expect(body).not.toContain('role="tablist"');
		expect(body).not.toContain('role="tab"');
		// Every panel is present, each carrying its label as a heading.
		expect((body.match(/panel-label/g) ?? []).length).toBe(3);
		expect(body).toContain('JavaScript');
		expect(body).toContain('Python');
		expect(body).toContain('const a = 1;');
		expect(body).toContain('a = 1'); // the Python panel's body, also shown
	});
});
