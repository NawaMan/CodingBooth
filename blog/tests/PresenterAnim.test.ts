import { render } from '@testing-library/svelte';
import { tick } from 'svelte';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import PresenterAnim from '../src/lib/components/PresenterAnim.svelte';
import { applyState, type AnimState } from '../src/lib/utils/slideAnim';

// PresenterAnim is the presenter console's ANIMATE control. It drives the presenter's own
// (invisible) slide animations to power its rail, and relays {playing, fraction} to the
// audience window, which replays it through slideAnim.applyState.
//
// So the contract worth defending is the RELAY: whatever this component emits must, when
// applied to the audience's own animations, land them in the presenter's visual state.
// The tests below therefore drive the presenter and then feed each emitted command to a
// second, independent group of animations — the stand-in audience.
//
// jsdom implements no Web Animations, so the clock is faked, including the one behaviour
// that matters: `play()` on an animation that has reached its end REWINDS it to 0.

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

/** Three shapes drawing one after another, as staggered `drawDelay`s produce. */
const stagger = () => [new FakeAnimation(100), new FakeAnimation(200), new FakeAnimation(300)];
const as = (a: FakeAnimation[]) => a as unknown as Animation[];

const RAIL_PX = 100;

let clock: FakeAnimation[] = [];
let commands: AnimState[] = [];
const lastCommand = () => commands[commands.length - 1];

function installClock() {
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
const rail = (root: ParentNode) => root.querySelector('.track') as HTMLElement;

/** A pointer event jsdom will accept (it has no PointerEvent constructor). */
function pointer(type: string, clientX: number) {
	const ev = new MouseEvent(type, { bubbles: true, cancelable: true, clientX });
	Object.defineProperty(ev, 'pointerId', { value: 1 });
	return ev;
}

let rectSpy: ReturnType<typeof vi.spyOn>;

beforeEach(() => {
	vi.useFakeTimers();
	clock = stagger();
	commands = [];
	installClock();
	rectSpy = vi.spyOn(Element.prototype, 'getBoundingClientRect').mockReturnValue({
		left: 0,
		width: RAIL_PX
	} as DOMRect);
	// No setPointerCapture shim: jsdom implements none, and the component must call it
	// optionally (as it does for release). Scrubbing works without it — capture only helps
	// a drag that leaves the rail.
	expect('setPointerCapture' in Element.prototype).toBe(false);
});
afterEach(() => {
	vi.useRealTimers();
	removeClock();
	rectSpy.mockRestore();
});

async function mount() {
	const r = render(PresenterAnim, { props: { onCommand: (c: AnimState) => commands.push({ ...c }) } });
	await tick();
	return r;
}

describe('PresenterAnim — rendering', () => {
	it('renders nothing on a slide with no finite, seekable animation', async () => {
		clock = [];
		const { container } = render(PresenterAnim, { props: { onCommand: () => {} } });
		await tick();
		vi.advanceTimersByTime(20); // the one rAF retry
		await tick();
		expect(container.querySelector('.anim')).toBeNull();
	});

	it('shows the transport once it finds an animation, and reads the live playhead', async () => {
		const { container } = await mount();
		expect(btn(container, 'Play')).not.toBeNull();
		expect(btn(container, 'Restart')).not.toBeNull();
		expect(rail(container).getAttribute('aria-valuenow')).toBe('0');
	});
});

describe('PresenterAnim — driving the local slide', () => {
	it('resuming mid-timeline does not redraw the shapes that already finished', async () => {
		// Shape 1 ends at 100ms, so at the halfway mark it is done while 2 and 3 are not.
		const { container } = await mount();

		rail(container).dispatchEvent(pointer('pointerdown', 50)); // scrub to 150ms
		await tick();
		expect(clock.map((a) => a.currentTime)).toEqual([100, 150, 150]);

		btn(container, 'Play').click();
		await tick();

		expect(clock[0].currentTime).toBe(100); // held at its final frame, NOT rewound
		expect(clock[0].playState).toBe('paused');
		expect(clock[1].playState).toBe('running');
		expect(clock[2].playState).toBe('running');
	});

	it('a slide scrubbed to the end still replays from the top on Play', async () => {
		// "Spent" must be judged on the playhead: scrubbing to the end leaves the animations
		// *paused* at their ends, never 'finished', and playGroup will not restart those.
		const { container } = await mount();

		rail(container).dispatchEvent(pointer('pointerdown', RAIL_PX));
		await tick();
		expect(clock.map((a) => a.currentTime)).toEqual([100, 200, 300]);

		btn(container, 'Play').click();
		await tick();

		expect(clock.every((a) => a.currentTime === 0)).toBe(true);
		expect(clock.every((a) => a.playState === 'running')).toBe(true);
	});

	it('scrubs without pointer capture, which not every environment implements', async () => {
		// The component must call setPointerCapture OPTIONALLY (as it does for release).
		// An unguarded call throws inside the listener — and jsdom swallows that, reporting
		// it as a window `error` rather than failing the dispatch, so the seek above it still
		// lands and every other assertion here would pass. Catch the exception explicitly.
		const { container } = await mount();
		const errors: unknown[] = [];
		const onError = (e: ErrorEvent) => { errors.push(e.error ?? e.message); e.preventDefault(); };
		window.addEventListener('error', onError);

		rail(container).dispatchEvent(pointer('pointerdown', 50));
		await tick();

		window.removeEventListener('error', onError);
		expect(errors).toEqual([]);
	});

	it('a scrub pauses and follows the pointer; restart rewinds and runs', async () => {
		const { container } = await mount();

		btn(container, 'Play').click();
		await tick();
		expect(clock.every((a) => a.playState === 'running')).toBe(true);

		rail(container).dispatchEvent(pointer('pointerdown', 25)); // 75ms
		await tick();
		expect(clock.every((a) => a.playState === 'paused')).toBe(true); // a scrub detaches
		expect(clock[0].currentTime).toBe(75);

		rail(container).dispatchEvent(pointer('pointermove', 75)); // drag on to 225ms
		await tick();
		expect(clock.map((a) => a.currentTime)).toEqual([100, 200, 225]);

		rail(container).dispatchEvent(pointer('pointerup', 75));
		await tick();
		rail(container).dispatchEvent(pointer('pointermove', 10)); // drag is over
		await tick();
		expect(clock[2].currentTime).toBe(225);

		btn(container, 'Restart').click();
		await tick();
		expect(clock.every((a) => a.currentTime === 0)).toBe(true);
		expect(clock.every((a) => a.playState === 'running')).toBe(true);
	});
});

describe('PresenterAnim — the relay to the audience', () => {
	it('emits {playing, fraction} on play, pause and every scrub', async () => {
		const { container } = await mount();

		btn(container, 'Play').click();
		await tick();
		expect(lastCommand()).toEqual({ playing: true, fraction: 0 });

		btn(container, 'Pause').click();
		await tick();
		expect(lastCommand().playing).toBe(false);

		rail(container).dispatchEvent(pointer('pointerdown', 50));
		await tick();
		expect(lastCommand()).toEqual({ playing: false, fraction: 0.5 });

		rail(container).dispatchEvent(pointer('pointermove', 75));
		await tick();
		expect(lastCommand()).toEqual({ playing: false, fraction: 0.75 });
	});

	it('a relayed mid-timeline play lands the audience in the presenter\'s exact state', async () => {
		// The whole point of the component. Drive the presenter, then replay each command
		// onto an INDEPENDENT group — the audience window's own animations.
		const { container } = await mount();
		const audience = stagger();

		rail(container).dispatchEvent(pointer('pointerdown', 50)); // presenter scrubs to 150ms
		await tick();
		btn(container, 'Play').click(); // ...and plays on from there
		await tick();

		applyState(as(audience), lastCommand());

		// Same visual state, shape for shape — and the finished shape was NOT redrawn.
		expect(audience.map((a) => a.currentTime)).toEqual(clock.map((a) => a.currentTime));
		expect(audience[0].currentTime).toBe(100);
		expect(audience[0].playState).not.toBe('running');
		expect(audience[1].playState).toBe('running');
		expect(audience[2].playState).toBe('running');
	});

	it('a relayed pause parks the audience at the presenter\'s fraction', async () => {
		const { container } = await mount();
		const audience = stagger();

		rail(container).dispatchEvent(pointer('pointerdown', 75)); // 225ms, paused
		await tick();

		applyState(as(audience), lastCommand());

		expect(audience.map((a) => a.currentTime)).toEqual([100, 200, 225]);
		expect(audience.every((a) => a.playState === 'paused')).toBe(true);
	});

	it('a relayed restart rewinds the audience and runs it from the top', async () => {
		const { container } = await mount();
		const audience = stagger();
		applyState(as(audience), { playing: false, fraction: 1 }); // audience already at the end

		btn(container, 'Restart').click();
		await tick();

		expect(lastCommand()).toEqual({ playing: true, fraction: 0 });
		applyState(as(audience), lastCommand());

		expect(audience.every((a) => a.currentTime === 0)).toBe(true);
		expect(audience.every((a) => a.playState === 'running')).toBe(true);
	});
});
