import { render } from '@testing-library/svelte';
import { tick } from 'svelte';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import AnimationBar from '../src/lib/components/AnimationBar.svelte';

// AnimationBar drives a slide's staggered CSS animations through the Web Animations API.
// jsdom implements none of it, so the clock is faked — including the one behaviour that
// matters here: `play()` on an animation that has reached its end REWINDS it to 0.
//
// A slide's animations do not share an end (`drawDelay` staggers a Draw/Connector reveal),
// so at any playhead mid-timeline some are finished and some are not. Pausing and
// resuming there must not redraw the shapes that already drew themselves.

class FakeAnimation {
	currentTime = 0;
	playState: 'idle' | 'running' | 'paused' | 'finished' = 'idle';
	effect: { getComputedTiming: () => { endTime: number } };
	constructor(readonly endTime: number) {
		this.effect = { getComputedTiming: () => ({ endTime }) };
	}
	play() {
		if (this.currentTime >= this.endTime) this.currentTime = 0; // spec: auto-rewind
		this.playState = 'running';
	}
	pause() { this.playState = 'paused'; }
}

// Three shapes drawing one after another, as staggered `drawDelay`s produce.
let clock: FakeAnimation[] = [];

function installClock() {
	clock = [new FakeAnimation(100), new FakeAnimation(200), new FakeAnimation(300)];
	const get = () => clock as unknown as Animation[];
	(Element.prototype as unknown as { getAnimations: () => Animation[] }).getAnimations = get;
	(Document.prototype as unknown as { getAnimations: () => Animation[] }).getAnimations = get;
}
function removeClock() {
	delete (Element.prototype as unknown as { getAnimations?: unknown }).getAnimations;
	delete (Document.prototype as unknown as { getAnimations?: unknown }).getAnimations;
}

const btn = (root: ParentNode, label: string) =>
	root.querySelector(`button[aria-label="${label}"]`) as HTMLButtonElement;

beforeEach(() => {
	vi.useFakeTimers();
	installClock();
});
afterEach(() => {
	vi.useRealTimers();
	removeClock();
});

/** A bar already open and held at frame 0, as `startPaused` gives. */
async function mount() {
	const r = render(AnimationBar, { props: { startPaused: true } });
	await tick();
	await tick();
	return r;
}

describe('AnimationBar', () => {
	it('holds the slide at frame 0 and shows its transport', async () => {
		const { container } = await mount();
		expect(clock.every((a) => a.playState === 'paused')).toBe(true);
		expect(clock.every((a) => a.currentTime === 0)).toBe(true);
		expect(btn(container, 'Play')).not.toBeNull();
	});

	it('resuming mid-timeline does not redraw the shapes that already finished', async () => {
		// The bug: a bare `for (const a of anims) a.play()` rewinds every finished animation.
		// Shape 1 ends at 100ms, so at the halfway mark it is done while 2 and 3 are not.
		const { container, component } = await mount();

		component.seekFraction(0.5); // 150ms of a 300ms envelope
		await tick();
		expect(clock.map((a) => a.currentTime)).toEqual([100, 150, 150]);

		btn(container, 'Play').click();
		await tick();

		expect(clock[0].currentTime).toBe(100); // held at its final frame, NOT rewound
		expect(clock[0].playState).toBe('paused'); // never re-attached to the clock
		expect(clock[1].currentTime).toBe(150);
		expect(clock[1].playState).toBe('running');
		expect(clock[2].playState).toBe('running');
	});

	it('a slide scrubbed to the end still replays from the top on Play', async () => {
		// The flip side, and the reason "spent" is judged on the PLAYHEAD, not on playState:
		// scrubbing to the end leaves the animations *paused* at their ends, never
		// 'finished', and playGroup will not restart a finished animation.
		const { container, component } = await mount();

		component.seekFraction(1);
		await tick();
		expect(clock.map((a) => a.currentTime)).toEqual([100, 200, 300]);
		expect(clock.every((a) => a.playState === 'paused')).toBe(true);

		btn(container, 'Play').click();
		await tick();

		expect(clock.every((a) => a.currentTime === 0)).toBe(true);
		expect(clock.every((a) => a.playState === 'running')).toBe(true);
	});

	it('pause detaches the whole group; restart rewinds and runs it', async () => {
		const { container, component } = await mount();

		btn(container, 'Play').click();
		await tick();
		btn(container, 'Pause').click();
		await tick();
		expect(clock.every((a) => a.playState === 'paused')).toBe(true);

		component.seekFraction(0.5);
		await tick();
		btn(container, 'Restart').click();
		await tick();

		expect(clock.every((a) => a.currentTime === 0)).toBe(true);
		expect(clock.every((a) => a.playState === 'running')).toBe(true);
	});

	it('renders nothing at all on a slide with no finite animation', async () => {
		clock = []; // no seekable animations
		const { container } = render(AnimationBar);
		await tick();
		vi.advanceTimersByTime(20); // the one rAF retry
		await tick();
		expect(container.querySelector('.anim-bar')).toBeNull();
	});
});
