import { render } from '@testing-library/svelte';
import { tick } from 'svelte';
import { get } from 'svelte/store';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import TerminalHost from './TerminalHost.svelte';
import { activeSteps } from '../src/lib/stores/activeSteps';

// The DOM half of Terminal. (The schedule and stepping arithmetic is in
// terminalCore.test.ts; the prerendered transcript in TerminalSsr.ssr.test.ts.)
//
// Two things are worth defending here.
//
// 1. The typing is CSS and nothing else: no timer fills the text in, so the transcript is
//    complete on the first frame and a scrub cannot desynchronise it from the DOM.
// 2. The Terminal owns ONE clock. It holds the session at frame 0 behind a play button,
//    Space plays it forward to the end of the next command and stops dead there, and once
//    the last command is behind the playhead Space stops claiming the key so the deck can
//    page. That handoff runs through the shared `activeSteps` store.
//
// jsdom implements no Web Animations, so the clock is faked below — closely enough that
// the component's own seek/sample/pause logic is exercised for real. Component styles are
// not injected in this project's DOM setup, so assertions are on markup and state.

// The reference session (host timing: charMs 10, startMs 100, pauseMs 50, outMs 20):
//   markers = [ {start:100, end:190}, {start:190, end:280} ], envelope 280.
const SESSION = [{ cmd: 'ab' }, { out: 'one' }, { cmd: 'cd' }, { out: 'two' }];
const ENVELOPE = 280;
const CHECKPOINT_1 = 190;
const CHECKPOINT_2 = 280;

/** A CSS animation's observable surface, as Terminal uses it. */
class FakeAnimation {
	currentTime = 0;
	playState: 'running' | 'paused' = 'running';
	effect: { getComputedTiming: () => { endTime: number } };
	constructor(readonly endTime: number) {
		this.effect = { getComputedTiming: () => ({ endTime }) };
	}
	play() {
		// AUTO-REWIND, per the Web Animations spec: play() on an animation that has reached
		// its end restarts it from 0. Modelling this is the point — without it, the fake
		// cannot show a finished command re-typing itself when the session resumes.
		if (this.currentTime >= this.endTime) this.currentTime = 0;
		this.playState = 'running';
	}
	pause() { this.playState = 'paused'; }
}

// The session is NOT one animation: every line has its own, with its own end. That is
// exactly why resuming is delicate. Ends mirror the real schedule (host timing):
//   cmd 'ab'  types 100→120      out 'one' lands 170→190
//   cmd 'cd'  types 190→210      out 'two' lands 260→280      resting caret 280→281
const LINE_ENDS = [120, 190, 210, 280, ENVELOPE + 1];

let clock: FakeAnimation[] = [];
let blink: FakeAnimation;
/** The longest animation — its clock is the session's playhead. */
const anim = () => clock[clock.length - 1];
/** The animation that types the Nth command (0-based). */
const cmdAnim = (n: number) => clock[n === 0 ? 0 : 2];

function installClock() {
	clock = LINE_ENDS.map((end) => new FakeAnimation(end));
	// The blink is infinite — a computed endTime of Infinity, which `endTimeOf` reports as
	// 0. Terminal must filter it out, or pausing the session would freeze the caret.
	blink = new FakeAnimation(Infinity);
	(Element.prototype as unknown as { getAnimations: () => Animation[] }).getAnimations = () =>
		[...clock, blink] as unknown as Animation[];
}
function removeClock() {
	delete (Element.prototype as unknown as { getAnimations?: unknown }).getAnimations;
}

/** Let the component's rAF sampling loop run once. */
async function frame() {
	vi.advanceTimersByTime(20);
	await tick();
}

// jsdom lays nothing out, so the rail gets a real geometry: 100px wide, starting at x=0.
// A clientX therefore reads directly as a percentage of the envelope.
const RAIL_PX = 100;

/**
 * A pointer event jsdom will accept (it has no PointerEvent constructor).
 *
 * `detail` defaults to 0 because that is what a REAL pointerdown carries — the property
 * is a click count, meaningful on `click`/`mousedown` and always 0 on a pointer event.
 * Forging a 1 here once hid a bug that made the whole rail dead in a browser.
 */
function pointer(
	type: string,
	clientX: number,
	opts: { detail?: number; button?: number; isPrimary?: boolean } = {}
) {
	const ev = new MouseEvent(type, {
		bubbles: true,
		cancelable: true,
		clientX,
		detail: opts.detail ?? 0,
		button: opts.button ?? 0
	});
	Object.defineProperty(ev, 'pointerId', { value: 1 });
	Object.defineProperty(ev, 'isPrimary', { value: opts.isPrimary ?? true });
	return ev;
}

/** Press the rail at `clientX` (as the knob's grab strip would receive it). */
async function down(root: ParentNode, clientX: number) {
	(root.querySelector('.track') as HTMLElement).dispatchEvent(pointer('pointerdown', clientX));
	await tick();
}

/** Seek to a time by pressing the rail at the matching point. */
async function seekVia(root: ParentNode, ms: number) {
	await down(root, (ms / ENVELOPE) * RAIL_PX);
}

function press(key: string, opts: { shiftKey?: boolean } = {}) {
	const ev = new KeyboardEvent('keydown', {
		key,
		code: key === ' ' ? 'Space' : key,
		shiftKey: opts.shiftKey ?? false,
		bubbles: true,
		cancelable: true
	});
	document.body.dispatchEvent(ev);
	return ev;
}

const terminal = (root: ParentNode) => root.querySelector('.terminal') as HTMLElement;
const rows = (root: ParentNode) => Array.from(root.querySelectorAll('.line')) as HTMLElement[];
const gates = (root: ParentNode) => Array.from(root.querySelectorAll('.gate')) as HTMLElement[];
const ticks = (root: ParentNode) => Array.from(root.querySelectorAll('.tick')) as HTMLButtonElement[];
const overlay = (root: ParentNode) => root.querySelector('.overlay') as HTMLButtonElement | null;
const transport = (root: ParentNode) => root.querySelector('.transport');

let rectSpy: ReturnType<typeof vi.spyOn>;

beforeEach(() => {
	vi.useFakeTimers();
	installClock();
	activeSteps.set(null);
	rectSpy = vi.spyOn(Element.prototype, 'getBoundingClientRect').mockReturnValue({
		left: 0,
		width: RAIL_PX
	} as DOMRect);
});
afterEach(() => {
	vi.useRealTimers();
	removeClock();
	rectSpy.mockRestore();
});

describe('Terminal — transcript', () => {
	it('renders the whole transcript on the first frame; no timer types it in', () => {
		const { container } = render(TerminalHost, { props: { lines: SESSION } });
		const typed = Array.from(container.querySelectorAll('.typed')).map((n) => n.textContent);
		expect(typed).toEqual(['ab', 'cd']);
		const out = rows(container).filter((r) => r.classList.contains('out'));
		expect(out.map((r) => r.textContent)).toEqual(['one', 'two']);
	});

	it('puts the schedule on the elements as plain CSS: delay, duration, steps', () => {
		const { container } = render(TerminalHost, { props: { lines: SESSION } });
		const typed = container.querySelector('.typed') as HTMLElement;
		expect(typed.style.animationDelay).toBe('100ms');
		expect(typed.style.animationDuration).toBe('20ms'); // 2 chars x 10ms
		expect(typed.style.animationTimingFunction).toBe('steps(2, end)');
		expect(typed.style.getPropertyValue('--n')).toBe('2');

		const out = rows(container).filter((r) => r.classList.contains('out'));
		expect(out[0].style.animationDelay).toBe('170ms'); // 100 + 20 typing + 50 beat
	});

	it('the resting caret and its row both wait out the envelope', () => {
		const { container } = render(TerminalHost, { props: { lines: SESSION } });
		const rest = rows(container).at(-1) as HTMLElement;
		expect(rest.classList.contains('rest')).toBe(true);
		// Without an explicit delay the row's `terminal-in` would run at duration 0s under
		// fill-mode `both` — already finished — parking a bare `$` under a blank transcript.
		expect(rest.style.animationDelay).toBe(`${ENVELOPE}ms`);
		expect((container.querySelector('.rest-gate') as HTMLElement).style.animationDelay).toBe(`${ENVELOPE}ms`);
	});
});

describe('Terminal — the clock', () => {
	it('holds the session at frame 0 behind a play button', async () => {
		const { container } = render(TerminalHost, { props: { lines: SESSION } });
		await tick();

		expect(anim().playState).toBe('paused');
		expect(anim().currentTime).toBe(0);
		expect(overlay(container)).not.toBeNull();
		expect(transport(container)).not.toBeNull();
	});

	it('excludes the infinite blink from the clock, so the caret keeps blinking when paused', async () => {
		render(TerminalHost, { props: { lines: SESSION } });
		await tick();
		// The session is held...
		expect(anim().playState).toBe('paused');
		// ...but the caret was never touched. A frozen caret on a paused prompt is wrong:
		// a real prompt blinks while it waits.
		expect(blink.playState).toBe('running');
		expect(blink.currentTime).toBe(0); // never seeked either
	});

	it('autoplay runs it straight away — no play button', async () => {
		const { container } = render(TerminalHost, { props: { lines: SESSION, autoplay: true } });
		await tick();
		expect(anim().playState).toBe('running');
		expect(overlay(container)).toBeNull();
	});

	it('the play button starts the session and then unmounts, releasing focus', async () => {
		const { container } = render(TerminalHost, { props: { lines: SESSION } });
		await tick();

		overlay(container)!.click();
		await tick();

		expect(anim().playState).toBe('running');
		// It must go away: a focused <button> keeps Space's native meaning, so a lingering
		// play button would swallow the presenter's first step.
		expect(overlay(container)).toBeNull();
	});

	it('the ticks are drawn AT the stops Space walks, not at the commands\' starts', async () => {
		// The reported bug: ticks sat at command starts (100, 190) while Space stopped at
		// command ends (190, 280). The first Space therefore appeared to skip the first tick
		// and land on the second. The marks must be the stops.
		const { container } = render(TerminalHost, { props: { lines: SESSION } });
		await tick();

		const t = ticks(container);
		expect(t).toHaveLength(2); // two commands, two stops, two ticks
		expect(t[0].style.left).toBe(`${(CHECKPOINT_1 / ENVELOPE) * 100}%`);
		expect(t[1].style.left).toBe('100%'); // the last stop is the end of the session
		expect(t[0].style.left).not.toBe(`${(100 / ENVELOPE) * 100}%`); // not the command's start
	});

	it('a Space step parks the knob exactly on the next tick', async () => {
		const { container } = render(TerminalHost, { props: { lines: SESSION, keys: 'global' } });
		await tick();

		press(' ');
		anim().currentTime = CHECKPOINT_1;
		await frame();

		const knob = container.querySelector('.knob') as HTMLElement;
		expect(knob.style.left).toBe(ticks(container)[0].style.left);
	});

	it('ticks are inert marks that light as the playhead passes them', async () => {
		const { container } = render(TerminalHost, { props: { lines: SESSION } });
		await tick();

		const t = ticks(container);
		// Marks, not targets: a <button> here would sit under the knob (Space parks the
		// playhead ON a tick) and eat the press meant to grab it.
		expect(t.every((el) => el.tagName === 'DIV')).toBe(true);
		expect(t[0].getAttribute('aria-hidden')).toBe('true');

		expect(t.map((el) => el.classList.contains('active'))).toEqual([false, false]);
		await seekVia(container, 200); // past the first stop, short of the second
		expect(ticks(container).map((el) => el.classList.contains('active'))).toEqual([true, false]);
		await seekVia(container, ENVELOPE);
		expect(ticks(container).map((el) => el.classList.contains('active'))).toEqual([true, true]);
	});
});

describe('Terminal — click to seek, drag to scrub', () => {
	it('a click on the rail seeks there, and pauses (the playhead follows the pointer now)', async () => {
		const { container } = render(TerminalHost, { props: { lines: SESSION, autoplay: true } });
		await tick();
		expect(anim().playState).toBe('running');

		await down(container, 50); // halfway along a 100px rail
		expect(anim().currentTime).toBe(ENVELOPE / 2);
		expect(anim().playState).toBe('paused');
	});

	it('pressing the knob drags: the circle is pointer-transparent, so the press hits the rail', async () => {
		const { container } = render(TerminalHost, { props: { lines: SESSION } });
		await tick();

		const track = container.querySelector('.track') as HTMLElement;
		await down(container, 25);
		expect(anim().currentTime).toBe(70);

		// ...and the pointer keeps dragging it.
		track.dispatchEvent(pointer('pointermove', 75));
		await tick();
		expect(anim().currentTime).toBe(210);

		track.dispatchEvent(pointer('pointerup', 75));
		await tick();

		// The drag is over: a stray move no longer moves the playhead.
		track.dispatchEvent(pointer('pointermove', 10));
		await tick();
		expect(anim().currentTime).toBe(210);
	});

	it('a tick cannot block the press that grabs the knob parked on it', async () => {
		const { container } = render(TerminalHost, { props: { lines: SESSION, keys: 'global' } });
		await tick();

		// Step once: the playhead parks exactly on the second command's tick (190).
		press(' ');
		anim().currentTime = CHECKPOINT_1;
		await frame();
		expect(anim().currentTime).toBe(190);

		// Press right there — on the tick, where the knob now sits. The event must reach the
		// track (the tick has no handler and no pointer-events) and start a scrub.
		const t = ticks(container)[0];
		t.dispatchEvent(pointer('pointerdown', (CHECKPOINT_1 / ENVELOPE) * 100));
		await tick();
		expect(anim().playState).toBe('paused');

		const track = container.querySelector('.track') as HTMLElement;
		track.dispatchEvent(pointer('pointermove', 90));
		await tick();
		expect(anim().currentTime).toBe(252); // dragged on, not stuck on the tick
	});

	it('a seek near a tick snaps onto the command it marks', async () => {
		const { container } = render(TerminalHost, { props: { lines: SESSION } });
		await tick();

		// 67px → 187.6ms, a hair before the second command's start (190).
		await down(container, 67);
		expect(anim().currentTime).toBe(190);

		// Well clear of any tick → left exactly where the pointer put it.
		await down(container, 50);
		expect(anim().currentTime).toBe(140);
	});

	it('a real pointerdown carries detail 0 and MUST still seek', async () => {
		// Regression. Video guards its CLICK handler with `!event.detail` (0 = a keyboard
		// activation, no coordinates). On a POINTER event `detail` is always 0, so copying
		// that guard onto pointerdown rejected every real press and the rail went dead —
		// while a test forging `detail: 1` passed happily.
		const { container } = render(TerminalHost, { props: { lines: SESSION } });
		await tick();

		const track = container.querySelector('.track') as HTMLElement;
		const ev = pointer('pointerdown', 50);
		expect(ev.detail).toBe(0); // exactly what a browser sends
		track.dispatchEvent(ev);
		await tick();

		expect(anim().currentTime).toBe(140);
	});

	it('the rail ignores the secondary button and a second finger', async () => {
		const { container } = render(TerminalHost, { props: { lines: SESSION } });
		await tick();

		await down(container, 50);
		expect(anim().currentTime).toBe(140);

		const track = container.querySelector('.track') as HTMLElement;
		expect(track.tabIndex).toBe(-1); // the deck owns the arrow keys; this is pointer-only
		expect(track.getAttribute('aria-hidden')).toBe('true');

		// A right-click is not a seek.
		track.dispatchEvent(pointer('pointerdown', 0, { button: 2 }));
		await tick();
		expect(anim().currentTime).toBe(140);

		// Neither is the second finger of a pinch.
		track.dispatchEvent(pointer('pointerdown', 0, { isPrimary: false }));
		await tick();
		expect(anim().currentTime).toBe(140);
	});
});

describe('Terminal — Space stepping (keys="global")', () => {
	const step = { lines: SESSION, keys: 'global' as const };

	it('registers as the slide\'s build, so CONTINUE and Space agree', async () => {
		render(TerminalHost, { props: step });
		await tick();

		const build = get(activeSteps);
		expect(build).not.toBeNull();
		expect(build!.hasNext).toBe(true);
		expect(build!.hasPrev).toBe(false); // at the top, Shift+Space pages back
	});

	it('Space plays FORWARD to the end of the next command, then stops dead', async () => {
		render(TerminalHost, { props: step });
		await tick();

		press(' ');
		await tick();
		// It plays — it does not jump. That is the whole point: you watch it type.
		expect(anim().playState).toBe('running');
		expect(anim().currentTime).toBe(0);

		// The clock reaches the checkpoint; the sampling loop must halt exactly on it.
		anim().currentTime = CHECKPOINT_1 + 0.4; // a real clock overshoots
		await frame();

		expect(anim().playState).toBe('paused');
		expect(anim().currentTime).toBe(CHECKPOINT_1); // snapped back, so stops never drift
		expect(get(activeSteps)!.hasNext).toBe(true);
		expect(get(activeSteps)!.hasPrev).toBe(true);
	});

	it('resuming at a checkpoint does not re-type the commands already typed', async () => {
		// The reported bug: `play()` on an animation that has reached its end REWINDS it to 0
		// (spec'd auto-rewind). Every line is its own animation, so resuming at a checkpoint
		// replayed command 1 from scratch alongside command 2 — both typing at once.
		render(TerminalHost, { props: step });
		await tick();

		press(' '); // step to the first checkpoint
		anim().currentTime = CHECKPOINT_1;
		await frame();

		// Command 1's animation ended at 120; it is finished and holding its text.
		expect(cmdAnim(0).currentTime).toBe(120);
		expect(cmdAnim(1).currentTime).toBe(CHECKPOINT_1); // command 2 has not begun typing

		press(' '); // resume toward the second checkpoint
		await tick();

		// Command 1 must be left exactly where it finished — not rewound, not restarted.
		expect(cmdAnim(0).currentTime).toBe(120);
		expect(cmdAnim(0).playState).toBe('paused');
		// ...while command 2, which has not finished, is the one now running.
		expect(cmdAnim(1).playState).toBe('running');
	});

	it('a finished session still replays from the top on Play', async () => {
		// The flip side: skipping finished animations must not make Play a no-op at the end.
		const { container } = render(TerminalHost, { props: { lines: SESSION } });
		await tick();

		await seekVia(container, ENVELOPE);
		expect(anim().currentTime).toBe(ENVELOPE);

		(container.querySelector('.transport .icon') as HTMLButtonElement).click();
		await tick();

		expect(anim().currentTime).toBe(0);
		expect(anim().playState).toBe('running');
		expect(cmdAnim(0).playState).toBe('running'); // rewound with the rest
	});

	it('the last command spent, Space stops claiming the key so the deck pages', async () => {
		render(TerminalHost, { props: step });
		await tick();

		press(' ');
		anim().currentTime = CHECKPOINT_1;
		await frame();

		const second = press(' ');
		expect(second.defaultPrevented).toBe(true); // we took this one
		anim().currentTime = CHECKPOINT_2;
		await frame();
		expect(anim().currentTime).toBe(CHECKPOINT_2);
		expect(get(activeSteps)!.hasNext).toBe(false);

		// Spent. Terminal must NOT preventDefault now, or NavigationBar could never page.
		const spare = press(' ');
		expect(spare.defaultPrevented).toBe(false);
		expect(anim().playState).toBe('paused');
		expect(anim().currentTime).toBe(CHECKPOINT_2);
	});

	it('from the first checkpoint, Shift+Space rewinds to the beginning — it does NOT page', async () => {
		// The reported bug: stepping back off the first command paged the deck away instead
		// of rewinding, because backward walked command STARTS while forward walked their
		// ENDS. From the first command's start there was nothing earlier at all.
		render(TerminalHost, { props: step });
		await tick();

		press(' '); // forward to the first checkpoint
		anim().currentTime = CHECKPOINT_1;
		await frame();
		expect(anim().currentTime).toBe(CHECKPOINT_1);

		const back = press(' ', { shiftKey: true });
		await tick();
		expect(back.defaultPrevented).toBe(true); // we took it — the deck must not page
		expect(anim().currentTime).toBe(0); // all the way back to a blank console
		expect(anim().playState).toBe('paused');

		// Only NOW is there nothing behind it: hand Shift+Space to NavigationBar.
		const spare = press(' ', { shiftKey: true });
		expect(spare.defaultPrevented).toBe(false);
		expect(anim().currentTime).toBe(0);
	});

	it('Shift+Space undoes Space, stop for stop', async () => {
		render(TerminalHost, { props: step });
		await tick();

		press(' ');
		anim().currentTime = CHECKPOINT_1;
		await frame();
		press(' ');
		anim().currentTime = CHECKPOINT_2;
		await frame();
		expect(anim().currentTime).toBe(CHECKPOINT_2);

		// Back down the same ladder: 280 → 190 → 0.
		press(' ', { shiftKey: true });
		await tick();
		expect(anim().currentTime).toBe(CHECKPOINT_1);

		press(' ', { shiftKey: true });
		await tick();
		expect(anim().currentTime).toBe(0);
	});

	it('a scrubbed playhead rewinds to the stop behind it, not off the slide', async () => {
		const { container } = render(TerminalHost, { props: step });
		await tick();

		await down(container, 89); // ~249ms, inside the second command
		const back = press(' ', { shiftKey: true });
		await tick();
		expect(back.defaultPrevented).toBe(true);
		expect(anim().currentTime).toBe(CHECKPOINT_1);
	});

	it('the presenter console\'s CONTINUE pulse takes the same step', async () => {
		render(TerminalHost, { props: step });
		await tick();

		window.dispatchEvent(new Event('gp:continue'));
		await tick();
		expect(anim().playState).toBe('running');
	});

	it('withdraws from the store on unmount', async () => {
		const { unmount } = render(TerminalHost, { props: step });
		await tick();
		expect(get(activeSteps)).not.toBeNull();
		unmount();
		expect(get(activeSteps)).toBeNull();
	});
});

describe('Terminal — degradation', () => {
	it('with no Web Animations there is no transport, and Space never traps the deck', async () => {
		removeClock(); // a browser (or jsdom) without getAnimations
		const { container } = render(TerminalHost, { props: { lines: SESSION, keys: 'global' } });
		await tick();

		// Nothing to drive → no chrome that pretends otherwise, and no build registered...
		expect(transport(container)).toBeNull();
		expect(overlay(container)).toBeNull();
		expect(get(activeSteps)).toBeNull();
		// ...so Space falls straight through to NavigationBar, which pages the slide.
		expect(press(' ').defaultPrevented).toBe(false);
	});

	it('text mode prints the session whole — a reader cannot wait for a typewriter', async () => {
		const { container } = render(TerminalHost, { props: { lines: SESSION, mode: 'text' } });
		await tick();

		expect(terminal(container).classList.contains('anim')).toBe(false);
		expect(transport(container)).toBeNull();
		expect(overlay(container)).toBeNull();
		expect(rows(container)).toHaveLength(5); // 4 lines + the resting prompt
		// Only the resting caret survives; CSS shows it outright when nothing animates.
		expect(gates(container)).toHaveLength(1);
		expect(gates(container)[0].classList.contains('rest-gate')).toBe(true);
	});

	it('typing={false} is the same stillness inside a presentation', async () => {
		const { container } = render(TerminalHost, { props: { lines: SESSION, typing: false } });
		await tick();
		expect(terminal(container).classList.contains('anim')).toBe(false);
		expect(transport(container)).toBeNull();
	});

	it('controls={false} hands the clock back — no transport, and it runs itself', async () => {
		// Nothing else could ever start it (no controls, no keys, no autoplay), so rather
		// than freeze at frame 0 it plays: degrade, never blank.
		const { container } = render(TerminalHost, { props: { lines: SESSION, controls: false } });
		await tick();
		expect(transport(container)).toBeNull();
		expect(overlay(container)).toBeNull();
		expect(anim().playState).toBe('running');
	});

	it('controls={false} with keys still holds, because Space can start it', async () => {
		const { container } = render(TerminalHost, {
			props: { lines: SESSION, controls: false, keys: 'global' }
		});
		await tick();
		expect(transport(container)).toBeNull();
		expect(anim().playState).toBe('paused');
		expect(get(activeSteps)!.hasNext).toBe(true);
	});

	it('caret={false} removes every caret, resting one included', async () => {
		const { container } = render(TerminalHost, { props: { lines: SESSION, caret: false } });
		await tick();
		expect(gates(container)).toHaveLength(0);
		expect(container.querySelector('.rest')).toBeNull();
	});

	it('malformed entries are dropped rather than rendered as blank rows', async () => {
		const lines = [{ cmd: 'ab' }, null, 7, {}, { out: 'ok' }] as never;
		const { container } = render(TerminalHost, { props: { lines } });
		await tick();
		expect(rows(container)).toHaveLength(3); // 1 command + 1 output + resting prompt
	});
});
