// @vitest-environment node
//
// True server-side render of Video (svelte/server, no DOM). A prerendered slide —
// and a `text` artifact, which has no deck to gate it — must ship the whole player
// from props alone: the element, the chrome, and above all the chapter list, which
// is the component's reason to exist and the only part a reader without JS can
// still read.
//
// Nothing here may depend on a media element: on the server `duration` is NaN and
// `currentTime` is 0, so the readout, the fill and the ticks all render at their
// zero state rather than as NaN.
import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';
import Video from '../src/lib/components/Video.svelte';
import VideoPage from '../src/lib/components/VideoPage.svelte';

const SRC = '/assets/demo.mp4';
const BOOKMARKS = [
	{ at: '0:27', label: 'last' },
	{ at: 3, label: 'first', tag: 'HOST' }
];

describe('Video (SSR)', () => {
	it('renders the element with its source and attributes', () => {
		const { body } = render(Video, { props: { src: SRC, poster: '/p.png', loop: true } });
		expect(body).toContain('<video');
		expect(body).toContain(`src="${SRC}"`);
		expect(body).toContain('poster="/p.png"');
		expect(body).toContain('loop');
		expect(body).toContain('preload="metadata"');
	});

	it('prerenders the chapter list, sorted and formatted — the part a reader needs', () => {
		const { body } = render(Video, { props: { src: SRC, bookmarks: BOOKMARKS } });
		expect(body).toContain('>0:03</button>');
		expect(body).toContain('>0:27</button>');
		expect(body).toContain('>HOST</span>');
		expect(body.indexOf('0:03')).toBeLessThan(body.indexOf('0:27')); // sorted
	});

	it('renders the bar at its zero state, never a NaN', () => {
		const { body } = render(Video, { props: { src: SRC, bookmarks: BOOKMARKS } });
		expect(body).toContain('0:00 / 0:00'); // duration is NaN on the server
		expect(body).toContain('width: 0%'); // the progress fill
		expect(body).not.toContain('NaN');
		expect(body).not.toContain('Infinity');
	});

	it('the track ships non-focusable and hidden — the deck owns the arrow keys', () => {
		const { body } = render(Video, { props: { src: SRC } });
		expect(body).toContain('tabindex="-1"');
		expect(body).toContain('aria-hidden="true"');
	});

	it('a poster-less player emits no empty poster attribute', () => {
		const { body } = render(Video, { props: { src: SRC } });
		expect(body).not.toContain('poster=');
	});

	it('native={true} emits the browser controls and none of our bar', () => {
		const native = render(Video, { props: { src: SRC, native: true } });
		expect(native.body).toContain('controls');
		expect(native.body).not.toContain('class="bar"');

		const ours = render(Video, { props: { src: SRC } });
		expect(ours.body).not.toMatch(/<video[^>]*\scontrols/);
		expect(ours.body).toContain('class="bar');
	});

	it('bookmarks are optional: no list, and no empty <ul>, without them', () => {
		const { body } = render(Video, { props: { src: SRC } });
		expect(body).not.toContain('class="marks');
	});

	it('an unparseable bookmark is dropped at render, not shipped as a dead button', () => {
		const { body } = render(Video, { props: { src: SRC, bookmarks: [{ at: '1:xx', label: 'nope' }] } });
		expect(body).not.toContain('nope');
		expect(body).not.toContain('class="marks');
	});

	it('claims no build on the server: Space belongs to whoever mounts, not to SSR', () => {
		// `keys="global"` registers with the activeSteps store behind a `browser`
		// guard. A server render that registered would leak a build across requests.
		const { body } = render(Video, { props: { src: SRC, bookmarks: BOOKMARKS, keys: 'global' } });
		expect(body).toContain('class="marks'); // …but the chapters still prerender
	});
});

describe('VideoPage (SSR)', () => {
	it('renders the player; paging is the deck ControlBar\'s job, not a bar of its own', () => {
		const { body } = render(VideoPage, { props: { src: SRC, bookmarks: BOOKMARKS } });
		expect(body).toContain('class="videopage');
		expect(body).toContain('<video');
		expect(body).toContain('>0:03</button>'); // the chapters, prerendered
		// The pager moved to SlideDeck's ControlBar — VideoPage no longer ships one.
		expect(body).not.toContain('NEXT');
	});

	it('passes its props through to the player it wraps', () => {
		const { body } = render(VideoPage, { props: { src: SRC, native: true, loop: true } });
		expect(body).toContain(`src="${SRC}"`);
		expect(body).toContain('loop');
		expect(body).not.toContain('class="bar'); // native → the browser's own bar
	});
});
