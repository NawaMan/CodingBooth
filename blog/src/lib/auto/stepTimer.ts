// The clock behind "normal": one countdown, which takes the build's next step when it
// runs out. SlideDeck owns one and feeds it the current state on every change; the hint
// (<StepDots>) only DRAWS what this publishes, so the number on screen and the moment the
// step is taken cannot disagree.
//
// It can be frozen (the pointer is on the hint) and thawed with the time that was left —
// no jump, the same bargain the kiosk panel makes.
//
// DOM-free apart from setTimeout, and the clock is injectable, so it runs under fake timers.

/** What the hint draws. `at` is when `leftMs` was true, on the same clock as `now()`. */
export type StepCountdown = {
	/** The whole wait. */
	totalMs: number;
	/** What was left at `at`. */
	leftMs: number;
	/** Counting down, or frozen at `leftMs`. */
	running: boolean;
	at: number;
	/** Changes each time a new countdown starts — a key to restart an animation on. */
	seq: number;
};

export type StepTimerState = {
	/** Should a countdown exist at all? (auto/stepAutoCore.stepTimerArmed) */
	armed: boolean;
	/** The wait, in ms. */
	waitMs: number;
	/** Hold the countdown where it is. */
	frozen?: boolean;
	/** Identity of the stop being waited at: a new value starts the wait afresh. */
	key?: unknown;
	/** Take the step. */
	fire: () => void;
};

export function createStepTimer(
	publish: (countdown: StepCountdown | null) => void,
	now: () => number = () => Date.now()
) {
	let timer: ReturnType<typeof setTimeout> | undefined;
	let live = false; // a countdown exists (running or frozen)
	let running = false;
	let total = 0;
	let left = 0;
	let at = 0;
	let key: unknown;
	let seq = 0;
	let fire: () => void = () => {};

	function clear() {
		if (timer !== undefined) clearTimeout(timer);
		timer = undefined;
	}
	function emit() {
		publish(live ? { totalMs: total, leftMs: left, running, at, seq } : null);
	}
	function drop() {
		clear();
		const was = live;
		live = false;
		running = false;
		if (was) emit();
	}
	function expire() {
		const take = fire;
		drop();
		take();
	}

	return {
		/** Bring the clock in line with the state. Safe to call on every change. */
		set(state: StepTimerState) {
			fire = state.fire;
			const wait = Number.isFinite(state.waitMs) && state.waitMs > 0 ? state.waitMs : 0;
			if (!state.armed || wait === 0) {
				drop();
				return;
			}
			const fresh = !live || state.key !== key || wait !== total;
			if (fresh) {
				clear();
				live = true;
				running = false;
				key = state.key;
				total = left = wait;
				seq++;
			}
			const frozen = state.frozen === true;
			if (frozen && running) {
				clear();
				left = Math.max(0, left - (now() - at));
				at = now();
				running = false;
				emit();
			} else if (!frozen && !running) {
				at = now();
				running = true;
				timer = setTimeout(expire, left);
				emit();
			} else if (fresh) {
				at = now();
				emit();
			}
		},
		/** Drop any countdown (the deck is going away). */
		stop: drop
	};
}

/** What is left of a countdown at `t`. */
export function countdownLeft(c: StepCountdown | null | undefined, t: number): number {
	if (!c) return 0;
	return Math.max(0, c.running ? c.leftMs - (t - c.at) : c.leftMs);
}
