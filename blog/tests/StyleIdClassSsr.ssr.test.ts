// @vitest-environment node
//
// The pass-through contract, asserted once for every author-facing component.
//
// A Svelte component forwards NOTHING it has not declared. So a slide that writes
// `<Hint style="font-size: 0.8em" />` against a component with no `style` prop gets
// no error and no effect — the attribute is silently dropped, which reads as "the
// style does not work" rather than "the style went nowhere". That is a bad failure
// mode to rediscover per component, so it is pinned here instead: every component an
// author places must accept `style`, `id` and `class`, and put them on its root.
//
// Asserted through svelte/server for the usual reason (tests/*.ssr.test.ts): the built
// deck HTML contains no slide markup, so prerendered output is the honest surface.
//
// The contract, per AGENTS.md:
//   style — LAST in the style attribute, so the author's declaration outranks the
//           component's own class rules without an !important anywhere.
//   id    — emitted only when set (no empty id="").
//   class — appended to the root's own classes. (Beware: a class defined in a slide's
//           scoped <style> will not match — that is global CSS's job. See AGENTS.md.)
import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';

import Block from '$lib/components/Block.svelte';
import Box from '$lib/components/Box.svelte';
import Callout from '$lib/components/Callout.svelte';
import Carousel from '$lib/components/Carousel.svelte';
import CodeDiff from '$lib/components/CodeDiff.svelte';
import Columns from '$lib/components/Columns.svelte';
import CssSnippet from '$lib/components/CssSnippet.svelte';
import Hint from '$lib/components/Hint.svelte';
import Kbd from '$lib/components/Kbd.svelte';
import Label from '$lib/components/Label.svelte';
import QRCode from '$lib/components/QRCode.svelte';
import QuickCode from '$lib/components/QuickCode.svelte';
import Quote from '$lib/components/Quote.svelte';
import ScrollDiv from '$lib/components/ScrollDiv.svelte';
import Stat from '$lib/components/Stat.svelte';
import StatGroup from '$lib/components/StatGroup.svelte';
import Steps from '$lib/components/Steps.svelte';
import Tabs from '$lib/components/Tabs.svelte';
import Terminal from '$lib/components/Terminal.svelte';
import Timeline from '$lib/components/Timeline.svelte';
import Video from '$lib/components/Video.svelte';
import WebSite from '$lib/components/WebSite.svelte';
import YouTube from '$lib/components/YouTube.svelte';
import Code from '$lib/components/Code.svelte';
import CodeBox from '$lib/components/CodeBox.svelte';
import Column from '$lib/components/Column.svelte';
import Fragment from '$lib/components/Fragment.svelte';
import Highlight from '$lib/components/Highlight.svelte';
import ImageBlock from '$lib/components/ImageBlock.svelte';
import JavaCode from '$lib/components/JavaCode.svelte';
import JavaCodeBox from '$lib/components/JavaCodeBox.svelte';
import SourceView from '$lib/components/SourceView.svelte';
import Tab from '$lib/components/Tab.svelte';
import TextPage from '$lib/components/TextPage.svelte';
import TimelineItem from '$lib/components/TimelineItem.svelte';
import VideoPage from '$lib/components/VideoPage.svelte';
import ViewSource from '$lib/components/ViewSource.svelte';
import WebPage from '$lib/components/WebPage.svelte';
import WideDiv from '$lib/components/WideDiv.svelte';
import ContentPage from '$lib/templates/ContentPage.svelte';
import TitlePage from '$lib/templates/TitlePage.svelte';
import StyleIdClassDrawHost from './StyleIdClassDrawHost.svelte';

// A marker no component would emit on its own, so finding it proves it came from us.
const STYLE = 'outline: 7px dotted magenta';
const ID = 'gp-probe-id';
const CLASS = 'gp-probe-class';

/** Each component with whatever else it needs to render at all. */
const COMPONENTS: Array<[string, any, Record<string, unknown>]> = [
	['Block', Block, { x: 10, y: 10, width: 100, height: 50 }],
	['Box', Box, {}],
	['Callout', Callout, { kind: 'tip' }],
	['Carousel', Carousel, {}],
	['CodeDiff', CodeDiff, { before: 'a', after: 'b' }],
	['Columns', Columns, {}],
	['CssSnippet', CssSnippet, { code: 'a{}' }],
	['Hint', Hint, { text: 'cue' }],
	['Kbd', Kbd, { keys: 'Mod+K' }],
	['Label', Label, { text: 'x' }],
	// Note is absent on purpose: it renders NOTHING on the server (a speaker note is
	// not part of the prerendered slide — it is gated on being visible), so there is no
	// root here to carry anything. It takes the three props like everything else; this
	// file just isn't the surface that can see them.
	['QRCode', QRCode, { value: 'https://example.test' }],
	['QuickCode', QuickCode, { code: 'x' }],
	['Quote', Quote, {}],
	['ScrollDiv', ScrollDiv, {}],
	['Stat', Stat, { value: '1' }],
	['StatGroup', StatGroup, {}],
	['Steps', Steps, {}],
	['Tabs', Tabs, {}],
	['Terminal', Terminal, { lines: [] }],
	['Timeline', Timeline, {}],
	['Video', Video, { src: 'x.mp4' }],
	['WebSite', WebSite, { url: 'https://example.test' }],
	// `youtubeId`, note — the video's id, which is NOT the DOM `id`. They coexist.
	['YouTube', YouTube, { youtubeId: 'abc123', thumbnail: 'thumb.png' }],
	['ContentPage', ContentPage, { title: 'T' }],
	['TitlePage', TitlePage, {}],
	['TextPage', TextPage, {}],

	// The children of the grouping components, which authors place directly.
	['Column', Column, {}],
	['Tab', Tab, { title: 't' }],
	['TimelineItem', TimelineItem, { title: 't' }],
	['Fragment', Fragment, {}],
	['Highlight', Highlight, {}],

	// The FORWARDERS: these own no root of their own, they hand the props to a child
	// component (ImageBlock → Block, WideDiv → ScrollDiv, CodeBox/JavaCodeBox → Box).
	// They are the likeliest of all of these to quietly swallow a prop, since "pass it
	// on" is a step that can simply be missing — so they are worth an assertion each.
	['ImageBlock', ImageBlock, { src: 'x.png', x: 0, y: 0, width: 10, height: 10 }],
	['WideDiv', WideDiv, {}],
	['CodeBox', CodeBox, { code: 'x' }],
	['JavaCodeBox', JavaCodeBox, { code: 'x' }],

	// Monaco-backed: the root is the div Monaco mounts INTO, and it is still ours.
	['Code', Code, { code: 'x' }],
	['JavaCode', JavaCode, { code: 'x' }],

	// The source viewers own the corner control they render, not the Box they pop.
	['ViewSource', ViewSource, { source: 'x', path: 'p' }],
	['SourceView', SourceView, { source: 'x', path: 'p' }],

	['WebPage', WebPage, { url: 'https://example.test' }],
	['VideoPage', VideoPage, { src: 'x.mp4' }]
];

/** The Draw primitives, which only exist inside a <Draw> surface. */
// CarouselItem joins these: it needs a parent for context, not a surface, but either
// way it cannot be rendered alone.
const HOSTED = ['Draw', 'CarouselItem', 'Rect', 'Ellipse', 'Line', 'Path', 'Polyline', 'Curve', 'Arc', 'Sprite', 'Connector', 'Cursor'];

describe('style / id / class reach every author-facing component', () => {
	for (const [name, Component, props] of COMPONENTS) {
		it(`${name} passes them to its root`, () => {
			const { body } = render(Component, {
				props: { ...props, style: STYLE, id: ID, class: CLASS }
			});

			expect(body, `${name} dropped style`).toContain(STYLE);
			expect(body, `${name} dropped class`).toContain(CLASS);
			expect(body, `${name} dropped id`).toContain(`id="${ID}"`);
		});
	}

	// The Draw primitives, through a <Draw> surface — an SVG shape's style/class/id are
	// as meaningful as a div's, and an author places these by hand like anything else.
	for (const shape of HOSTED) {
		it(`${shape} passes them to its root`, () => {
			const { body } = render(StyleIdClassDrawHost, {
				props: { which: shape, style: STYLE, id: ID, class: CLASS }
			});

			expect(body, `${shape} dropped style`).toContain(STYLE);
			expect(body, `${shape} dropped class`).toContain(CLASS);
			expect(body, `${shape} dropped id`).toContain(`id="${ID}"`);
		});
	}

	// Unset must stay unset: an empty id="" is markup noise, and would also make every
	// slide's components collide on the same (empty) id.
	it('emits no id attribute when none is given', () => {
		const { body } = render(Hint, { props: { text: 'cue' } });
		expect(body).not.toContain('id=""');
	});

	// The ordering rule, which is what makes `style` actually WIN: a plain declaration
	// on the element outranks any class selector, but only if it is the last word.
	it('puts the author’s style last, so it outranks the component’s own rules', () => {
		const { body } = render(Video, { props: { src: 'x.mp4', width: '640px', style: STYLE } });
		const attr = body.slice(body.indexOf('style="'));
		expect(attr.indexOf('640px')).toBeLessThan(attr.indexOf(STYLE));
	});
});
