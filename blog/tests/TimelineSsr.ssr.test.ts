// @vitest-environment node
//
// True server-side render of Timeline / TimelineItem (svelte/server, no DOM). Both
// are purely declarative — no onMount, no browser APIs — so the whole timeline must
// come from props alone, which is what prerendering a slide does. There is no layout
// engine here, so what this locks in is the CONTRACT the stylesheet then reads: the
// list/side classes, each event's parts (time / title / body), the body's slot-vs-
// text escape hatch, the icon / active / colour markers, and the side a TimelineItem
// only learns from its parent Timeline over context.
import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';
import Timeline from '../src/lib/components/Timeline.svelte';
import TimelineItem from '../src/lib/components/TimelineItem.svelte';
import TimelineHost from './TimelineHost.svelte';

const host = (props: Record<string, unknown> = {}) => render(TimelineHost, { props }).body;

describe('Timeline (SSR)', () => {
	it('renders an ordered list, vertical spine-on-the-left (side="right") by default', () => {
		const { body } = render(Timeline, {});
		expect(body).toContain('<ol');
		expect(body).toContain('timeline');
		expect(body).toContain('orient-vertical');
		expect(body).toContain('side-right');
	});

	it('orientation="horizontal" switches the class and defaults the side to "below"', () => {
		const { body } = render(Timeline, { props: { orientation: 'horizontal' } });
		expect(body).toContain('orient-horizontal');
		expect(body).toContain('side-below');
		expect(body).toContain('--tl-band: 9em');
		expect(body).toContain('--tl-item: 12em');
	});

	it('horizontal side aliases: left→above, right/other→below; alternate passes through', () => {
		// side is deliberately loose here — the point is the runtime resolution of
		// aliases and junk, which the typed prop would otherwise forbid.
		const h = (side: string) =>
			render(Timeline, { props: { orientation: 'horizontal', side } as never }).body;
		expect(h('above')).toContain('side-above');
		expect(h('left')).toContain('side-above'); // vertical name aliases sensibly
		expect(h('below')).toContain('side-below');
		expect(h('right')).toContain('side-below');
		expect(h('alternate')).toContain('side-alternate');
		// A vertical-only alternate name is not a horizontal thing — falls to below.
		expect(h('sideways')).toContain('side-below');
	});

	it('drives the gap through a custom property', () => {
		const { body } = render(Timeline, { props: { gap: '2.4em' } });
		expect(body).toContain('--timeline-gap: 2.4em');
	});

	it('side left / alternate switch the class; an unknown side falls back to right', () => {
		expect(render(Timeline, { props: { side: 'left' } }).body).toContain('side-left');
		expect(render(Timeline, { props: { side: 'alternate' } }).body).toContain('side-alternate');
		// @ts-expect-error — exercising the runtime fallback on bad input
		const bad = render(Timeline, { props: { side: 'sideways' } }).body;
		expect(bad).toContain('side-right');
		expect(bad).not.toContain('side-sideways');
	});
});

describe('TimelineItem (SSR)', () => {
	it('renders time, title and a text body', () => {
		const { body } = render(TimelineItem, {
			props: { time: '2019', title: 'Founded', text: 'In a garage.' },
		});
		expect(body).toContain('>2019</div>');
		expect(body).toContain('>Founded</div>');
		expect(body).toContain('In a garage.');
		expect(body).toContain('class="marker'); // scope-hash follows the token
		expect(body).toContain('class="dot');
	});

	it('used standalone it defaults to the spine-on-the-left (side-right) layout', () => {
		const { body } = render(TimelineItem, { props: { title: 'x' } });
		expect(body).toContain('side-right');
	});

	it('omitting a part leaves no box for it (survivors close up)', () => {
		const onlyTitle = render(TimelineItem, { props: { title: 'Only' } }).body;
		expect(onlyTitle).toContain('>Only</div>');
		expect(onlyTitle).not.toContain('class="time'); // no empty time box
		expect(onlyTitle).not.toContain('class="body'); // no empty body box
	});

	it('an icon enlarges the dot and renders the glyph', () => {
		const { body } = render(TimelineItem, { props: { title: 'x', icon: '★' } });
		expect(body).toContain('has-icon');
		expect(body).toContain('>★</span>');
	});

	it('active adds the halo class; a colour retints via --tl-color', () => {
		const { body } = render(TimelineItem, {
			props: { title: 'x', active: true, color: '#f0a33e' },
		});
		expect(body).toContain('active');
		expect(body).toContain('--tl-color: #f0a33e');
	});

	it('a colourless, inactive event carries neither', () => {
		const { body } = render(TimelineItem, { props: { title: 'x' } });
		expect(body).not.toContain('--tl-color');
		expect(body).not.toContain('active');
	});
});

describe('Timeline + TimelineItem (SSR, via host)', () => {
	it('the side reaches the items over context (side="alternate")', () => {
		const body = host({ side: 'alternate' });
		// The list AND every item carry the alternate side class — proving context,
		// not a per-item prop, drives the layout.
		expect(body).toContain('timeline orient-vertical side-alternate');
		expect((body.match(/item orient-vertical side-alternate/g) ?? []).length).toBe(3);
	});

	it('orientation travels over context too — items go horizontal with the list', () => {
		const body = host({ orientation: 'horizontal', side: 'alternate' });
		expect(body).toContain('timeline orient-horizontal side-alternate');
		expect((body.match(/item orient-horizontal side-alternate/g) ?? []).length).toBe(3);
	});

	it('the default host renders vertical spine-on-the-left items with their parts', () => {
		const body = host();
		expect((body.match(/item orient-vertical side-right/g) ?? []).length).toBe(3);
		expect(body).toContain('>Founded</div>');
		expect(body).toContain('Ten million users.'); // slot body
		expect(body).toContain('has-icon'); // the ★ event
		expect(body).toContain('active'); // the "Here" event
	});
});
