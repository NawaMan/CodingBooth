import { render } from '@testing-library/svelte';
import { get } from 'svelte/store';
import { tick } from 'svelte';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import Video from '../src/lib/components/Video.svelte';
import { activeSteps } from '../src/lib/stores/activeSteps';
import { kioskStatus, stopKiosk } from '../src/lib/stores/kiosk';
import {
	clearAllKioskMediaHold,
	kioskMediaBusy,
	kioskMediaProgress
} from '../src/lib/stores/kioskMediaHold';

// The interactive half of Video (the SSR half is in VideoSsr.ssr.test.ts). What
// carries the component:
//
//   BOOKMARKS — chapter buttons that seek, and a highlight that follows the
//   playhead. Written in any order, in seconds or clock strings.
//
//   THE TRACK — pointer-only click-to-seek. It is skipped by Tab and hidden from
//   assistive tech, because the deck owns →/← and a scrub bar cannot be driven
//   without them; a keyboard activation (which carries no coordinates) must not
//   silently rewind the video.
//
// jsdom has no real media element: `play`/`pause` are not implemented, and
// `duration` is a read-only NaN. Both are faked below, closely enough that Svelte's
// media bindings behave as they do in a browser (which sync off the media events,
// not off the property writes).

const BOOKMARKS = [
	{ at: '0:10', label: 'middle', tag: 'MID' },
	{ at: 3, label: 'first' },
	{ at: '0:27', label: 'last' }
];

const player = (root: ParentNode) => root.querySelector('video') as HTMLVideoElement;
const track = (root: ParentNode) => root.querySelector('.track') as HTMLButtonElement;
const rows = (root: ParentNode) => [...root.querySelectorAll('.marks li')] as HTMLLIElement[];
const stamps = (root: ParentNode) => [...root.querySelectorAll('.marks .ts')] as HTMLButtonElement[];
const btn = (root: ParentNode, aria: string) =>
	root.querySelector(`[aria-label="${aria}"]`) as HTMLButtonElement;
const timeText = (root: ParentNode) => root.querySelector('.time')!.textContent;
const activeRow = (root: ParentNode) => rows(root).findIndex((li) => li.classList.contains('active'));

/** Set a read-only media property, then fire the event Svelte's binding listens on. */
function fake(el: HTMLVideoElement, prop: 'duration' | 'paused', value: unknown, event: string) {
	Object.defineProperty(el, prop, { value, configurable: true });
	el.dispatchEvent(new Event(event));
}

/** Move the playhead the way a playing video does. */
function playTo(el: HTMLVideoElement, seconds: number) {
	el.currentTime = seconds;
	el.dispatchEvent(new Event('timeupdate'));
}

beforeEach(() => {
	// jsdom's play()/pause() are `notImplemented` stubs that never flip `paused` nor
	// fire the events Svelte's `bind:paused` reads back. Give them just enough body.
	HTMLMediaElement.prototype.play = vi.fn(function (this: HTMLVideoElement) {
		fake(this, 'paused', false, 'play');
		return Promise.resolve();
	});
	HTMLMediaElement.prototype.pause = vi.fn(function (this: HTMLVideoElement) {
		fake(this, 'paused', true, 'pause');
	});
	stopKiosk();
	clearAllKioskMediaHold();
});

afterEach(() => {
	stopKiosk();
	clearAllKioskMediaHold();
});

describe('Video — bookmarks', () => {
	it('sorts the chapters and formats each time, whatever the author wrote', () => {
		const { container } = render(Video, { props: { src: 'demo.mp4', bookmarks: BOOKMARKS } });
		expect(stamps(container).map((b) => b.textContent)).toEqual(['0:03', '0:10', '0:27']);
		expect(rows(container)[1].textContent).toContain('MID');
	});

	it('a chapter button seeks the video to its mark', async () => {
		const { container } = render(Video, { props: { src: 'demo.mp4', bookmarks: BOOKMARKS } });
		stamps(container)[2].click();
		await tick();
		expect(player(container).currentTime).toBe(27);
	});

	it('the active chapter is the last one the playhead has passed', async () => {
		const { container } = render(Video, { props: { src: 'demo.mp4', bookmarks: BOOKMARKS } });
		expect(activeRow(container)).toBe(-1); // opens on unlabelled footage

		playTo(player(container), 12);
		await tick();
		expect(activeRow(container)).toBe(1);

		playTo(player(container), 27);
		await tick();
		expect(activeRow(container)).toBe(2); // exactly on the mark: it counts
	});

	it('drops an unparseable bookmark rather than offering a button to nowhere', () => {
		const { container } = render(Video, {
			props: { src: 'demo.mp4', bookmarks: [{ at: 'oops' }, { at: 5, label: 'ok' }] }
		});
		expect(stamps(container)).toHaveLength(1);
		expect(stamps(container)[0].textContent).toBe('0:05');
	});

	it('chapters={false} keeps the bar but drops the list', () => {
		const { container } = render(Video, {
			props: { src: 'demo.mp4', bookmarks: BOOKMARKS, chapters: false }
		});
		expect(container.querySelector('.marks')).toBeNull();
		expect(track(container)).not.toBeNull();
	});
});

describe('Video — transport', () => {
	it('play/pause toggles the element and relabels itself', async () => {
		const { container } = render(Video, { props: { src: 'demo.mp4' } });
		expect(btn(container, 'Play')).not.toBeNull();

		btn(container, 'Play').click();
		await tick();
		expect(player(container).play).toHaveBeenCalled();
		expect(btn(container, 'Pause')).not.toBeNull();

		btn(container, 'Pause').click();
		await tick();
		expect(player(container).pause).toHaveBeenCalled();
		expect(btn(container, 'Play')).not.toBeNull();
	});

	it('restart rewinds to zero and plays', async () => {
		const { container } = render(Video, { props: { src: 'demo.mp4' } });
		playTo(player(container), 12);
		await tick();

		btn(container, 'Restart from the beginning').click();
		await tick();
		expect(player(container).currentTime).toBe(0);
		expect(player(container).play).toHaveBeenCalled();
	});

	it('the readout shows 0:00 / 0:00 until the duration lands', async () => {
		const { container } = render(Video, { props: { src: 'demo.mp4' } });
		expect(timeText(container)).toBe('0:00 / 0:00'); // duration is still NaN

		fake(player(container), 'duration', 74, 'durationchange');
		playTo(player(container), 3);
		await tick();
		expect(timeText(container)).toBe('0:03 / 1:14');
	});

	it('mute toggles, and starts muted only when autoplay needs it to', async () => {
		const { container } = render(Video, { props: { src: 'demo.mp4' } });
		expect(btn(container, 'Mute')).not.toBeNull(); // sound on

		btn(container, 'Mute').click();
		await tick();
		expect(player(container).muted).toBe(true);

		// A browser refuses to autoplay with sound, so autoplay implies muted.
		const auto = render(Video, { props: { src: 'demo.mp4', autoplay: true } });
		expect(btn(auto.container, 'Unmute')).not.toBeNull();

		// 'kiosk' can autoplay later — pre-mute so Start is not blocked.
		const kiosk = render(Video, { props: { src: 'demo.mp4', autoplay: 'kiosk' } });
		expect(btn(kiosk.container, 'Unmute')).not.toBeNull();
	});

	it('autoplay="kiosk" does not autoplay until kiosk is running', async () => {
		const { container } = render(Video, {
			props: { src: 'demo.mp4', autoplay: 'kiosk', kioskHold: false }
		});
		expect(player(container).hasAttribute('autoplay')).toBe(false);
		expect(player(container).paused).toBe(true);

		kioskStatus.set('running');
		await tick();
		expect(player(container).hasAttribute('autoplay')).toBe(true);
		// Our play stub flips paused via the binding path.
		expect(player(container).paused).toBe(false);
	});

	it('kioskHold plays during kiosk even without autoplay (and unregisters chapter steps)', async () => {
		// The bug: keys=global + bookmarks + kiosk sought the first mark every stepMs
		// on a paused tape. Hold must play the clip and drop activeSteps for the session.
		const { container } = render(Video, {
			props: { src: 'demo.mp4', bookmarks: BOOKMARKS, keys: 'global' }
		});
		expect(get(activeSteps)).not.toBeNull(); // presenter Space-stepping is on

		kioskStatus.set('running');
		await tick();
		expect(get(activeSteps)).toBeNull(); // no chapter seeks on the step clock
		expect(player(container).paused).toBe(false); // tape is rolling
		expect(get(kioskMediaBusy)).toBe(true);
	});

	it('registers a kiosk media hold while the clip is in a playthrough', async () => {
		const { container, unmount } = render(Video, {
			props: { src: 'demo.mp4', autoplay: 'kiosk' }
		});
		kioskStatus.set('running');
		await tick();
		fake(player(container), 'duration', 20, 'durationchange');
		playTo(player(container), 5);
		await tick();

		expect(get(kioskMediaBusy)).toBe(true);
		expect(get(kioskMediaProgress)).toBe(0.25);

		player(container).dispatchEvent(new Event('ended'));
		await tick();
		expect(get(kioskMediaBusy)).toBe(false);

		unmount();
		expect(get(kioskMediaBusy)).toBe(false);
	});

	it('kioskHold={false} never registers a hold and does not force play', async () => {
		const { container } = render(Video, {
			props: { src: 'demo.mp4', autoplay: false, kioskHold: false }
		});
		kioskStatus.set('running');
		await tick();
		expect(player(container).paused).toBe(true);
		fake(player(container), 'duration', 20, 'durationchange');
		playTo(player(container), 5);
		await tick();
		// Playing mid-clip with hold off still does not register
		expect(get(kioskMediaBusy)).toBe(false);
	});

	it('strips loop during a kiosk hold so one cycle can end (no infinite booth)', async () => {
		// video-component.html uses loop — HTML loop suppresses `ended`, which used
		// to pin kiosk forever. While holding, the element must not have loop on.
		const { container } = render(Video, {
			props: { src: 'demo.mp4', loop: true, autoplay: 'kiosk' }
		});
		expect(player(container).hasAttribute('loop')).toBe(true); // normal mode

		kioskStatus.set('running');
		await tick();
		expect(player(container).hasAttribute('loop')).toBe(false);
		expect(get(kioskMediaBusy)).toBe(true);

		// Natural end releases the hold.
		player(container).dispatchEvent(new Event('ended'));
		await tick();
		expect(get(kioskMediaBusy)).toBe(false);
	});


	it('start seeks once the metadata arrives, not before', async () => {
		const { container } = render(Video, { props: { src: 'demo.mp4', start: '0:10' } });
		expect(player(container).currentTime).toBe(0);

		player(container).dispatchEvent(new Event('loadedmetadata'));
		await tick();
		expect(player(container).currentTime).toBe(10);
	});
});

describe('Video — the progress track', () => {
	/** Render with a laid-out track (jsdom gives every element a zero-size rect). */
	function withTrack(props: Record<string, unknown> = {}) {
		const view = render(Video, { props: { src: 'demo.mp4', ...props } });
		fake(player(view.container), 'duration', 100, 'durationchange');
		track(view.container).getBoundingClientRect = () =>
			({ left: 100, width: 200 }) as DOMRect;
		return view;
	}

	it('a click seeks proportionally along it', async () => {
		const { container } = withTrack();
		track(container).dispatchEvent(new MouseEvent('click', { clientX: 150, detail: 1 }));
		await tick();
		expect(player(container).currentTime).toBe(25); // a quarter of the way in
	});

	it('a click past either end clamps instead of seeking out of the video', async () => {
		const { container } = withTrack();
		track(container).dispatchEvent(new MouseEvent('click', { clientX: 9999, detail: 1 }));
		await tick();
		expect(player(container).currentTime).toBe(100);
	});

	it('is invisible to the keyboard: no Tab stop, no seek from a coordinate-less click', async () => {
		const { container } = withTrack();
		expect(track(container).getAttribute('tabindex')).toBe('-1');
		expect(track(container).getAttribute('aria-hidden')).toBe('true');

		// What Enter/Space on a button dispatches: detail 0, clientX 0. Honouring it
		// would rewind the video to the start.
		track(container).click();
		await tick();
		expect(player(container).currentTime).toBe(0);

		playTo(player(container), 40);
		track(container).click();
		await tick();
		expect(player(container).currentTime).toBe(40); // untouched
	});

	it('ignores a click while the duration is unknown — there is nowhere to seek to', async () => {
		const { container } = render(Video, { props: { src: 'demo.mp4' } });
		track(container).getBoundingClientRect = () => ({ left: 0, width: 200 }) as DOMRect;
		track(container).dispatchEvent(new MouseEvent('click', { clientX: 100, detail: 1 }));
		await tick();
		expect(player(container).currentTime).toBe(0);
	});

	it('ticks sit at each chapter, and light as the playhead passes them', async () => {
		const { container } = withTrack({ bookmarks: [{ at: 25 }, { at: 50 }] });
		await tick();

		const ticks = [...container.querySelectorAll('.tick')] as HTMLElement[];
		expect(ticks.map((t) => t.style.left)).toEqual(['25%', '50%']);

		playTo(player(container), 60);
		await tick();
		expect(ticks[1].classList.contains('active')).toBe(true);
		expect(ticks[0].classList.contains('active')).toBe(false);
	});
});

describe('Video — Space-stepping the bookmarks', () => {
	/** What NavigationBar's listener would see on the window. `cancelable`, or
	    `preventDefault()` is a silent no-op and every assertion below is vacuous. */
	const press = (opts: KeyboardEventInit = {}) => {
		const event = new KeyboardEvent('keydown', {
			key: ' ',
			code: 'Space',
			bubbles: true,
			cancelable: true,
			...opts
		});
		window.dispatchEvent(event);
		return event;
	};

	afterEach(() => activeSteps.set(null));

	it('is off by default: Space is left for the deck to page with', async () => {
		const { container } = render(Video, { props: { src: 'demo.mp4', bookmarks: BOOKMARKS } });
		const event = press();
		await tick();
		expect(player(container).currentTime).toBe(0);
		expect(event.defaultPrevented).toBe(false); // untouched → NavigationBar pages
		expect(get(activeSteps)).toBeNull(); // and CONTINUE has no build to drive
	});

	it('keys="global": Space walks chapter to chapter', async () => {
		const { container } = render(Video, {
			props: { src: 'demo.mp4', bookmarks: BOOKMARKS, keys: 'global' }
		});

		expect(press().defaultPrevented).toBe(true); // ours: the deck must not page
		await tick();
		expect(player(container).currentTime).toBe(3);

		press();
		await tick();
		expect(player(container).currentTime).toBe(10);
		expect(activeRow(container)).toBe(1);
	});

	it('past the last chapter Space falls through, so the deck pages on', async () => {
		const { container } = render(Video, {
			props: { src: 'demo.mp4', bookmarks: BOOKMARKS, keys: 'global' }
		});
		playTo(player(container), 27); // sitting on the final chapter
		await tick();

		const event = press();
		await tick();
		expect(event.defaultPrevented).toBe(false); // handed back to NavigationBar
		expect(player(container).currentTime).toBe(27); // and we did not seek
	});

	it('Shift+Space walks back, and pages back from the first chapter', async () => {
		const { container } = render(Video, {
			props: { src: 'demo.mp4', bookmarks: BOOKMARKS, keys: 'global' }
		});
		playTo(player(container), 12); // chapter 2 (0:10) is active
		await tick();

		expect(press({ shiftKey: true }).defaultPrevented).toBe(true);
		await tick();
		expect(player(container).currentTime).toBe(3);

		// On the FIRST chapter there is no earlier one: hand Space back to the deck
		// rather than trap the presenter on a mark (which one at 0:00 would).
		const event = press({ shiftKey: true });
		await tick();
		expect(event.defaultPrevented).toBe(false);
		expect(player(container).currentTime).toBe(3);
	});

	it('leaves the arrow keys alone — →/← always page, build or no build', async () => {
		const { container } = render(Video, {
			props: { src: 'demo.mp4', bookmarks: BOOKMARKS, keys: 'global' }
		});
		for (const key of ['ArrowRight', 'ArrowLeft']) {
			const event = new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true });
			window.dispatchEvent(event);
			expect(event.defaultPrevented).toBe(false);
		}
		await tick();
		expect(player(container).currentTime).toBe(0);
	});

	it('ignores Space while a control has focus — the button keeps its native meaning', async () => {
		const { container } = render(Video, {
			props: { src: 'demo.mp4', bookmarks: BOOKMARKS, keys: 'global' }
		});
		const play = btn(container, 'Play');
		document.body.append(container); // focus needs the node in the document
		play.focus();

		play.dispatchEvent(
			new KeyboardEvent('keydown', { key: ' ', code: 'Space', bubbles: true })
		);
		await tick();
		expect(player(container).currentTime).toBe(0);
	});

	it('publishes itself as a build, so CONTINUE seeks and greys out on the last chapter', async () => {
		const { container } = render(Video, {
			props: { src: 'demo.mp4', bookmarks: BOOKMARKS, keys: 'global' }
		});
		expect(get(activeSteps)).toMatchObject({ hasNext: true, hasPrev: false });

		// Exactly what NavigationBar's CONTINUE button does.
		get(activeSteps)!.next();
		await tick();
		expect(player(container).currentTime).toBe(3);
		expect(get(activeSteps)).toMatchObject({ hasNext: true, hasPrev: false });

		playTo(player(container), 27);
		await tick();
		expect(get(activeSteps)).toMatchObject({ hasNext: false, hasPrev: true });
	});

	it('a bookmark-less video never claims Space, however it is keyed', async () => {
		render(Video, { props: { src: 'demo.mp4', keys: 'global' } });
		expect(get(activeSteps)).toBeNull();
		expect(press().defaultPrevented).toBe(false);
	});

	it('hands the build back on unmount, and stops listening', async () => {
		const { unmount } = render(Video, {
			props: { src: 'demo.mp4', bookmarks: BOOKMARKS, keys: 'global' }
		});
		expect(get(activeSteps)).not.toBeNull();

		unmount();
		expect(get(activeSteps)).toBeNull();
		expect(press().defaultPrevented).toBe(false); // no stale window listener
	});
});

describe('Video — native controls', () => {
	it('native={true} hands the bar to the browser and renders none of ours', () => {
		const { container } = render(Video, {
			props: { src: 'demo.mp4', native: true, bookmarks: BOOKMARKS }
		});
		expect(player(container).hasAttribute('controls')).toBe(true);
		expect(container.querySelector('.bar')).toBeNull();
		// The chapters are ours, not the browser's — they stay.
		expect(stamps(container)).toHaveLength(3);
	});

	it('controls={false} drops our bar without conscripting the browser’s', () => {
		const { container } = render(Video, { props: { src: 'demo.mp4', controls: false } });
		expect(container.querySelector('.bar')).toBeNull();
		expect(player(container).hasAttribute('controls')).toBe(false);
	});
});
