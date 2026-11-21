// How much of a deck moves by itself. Three levels, the viewer's choice within what the
// deck's author switched on:
//
//   kiosk    steps and pages are automatic, and the deck loops (stores/kiosk.ts)
//   normal   a build that has stopped for Space takes its next step after a wait;
//            the page turn stays manual
//   pause    nothing moves without the viewer
//
// "Normal" only means anything where the author gave a wait: `stepTimeoutMs` on
// <SlideDeck>, the same key on a pages.ts entry, or `timeoutMs` on one <Steps>. With no
// wait the level is `manual`: the deck behaves as it always has, and there is no
// countdown to show and nothing to toggle.
//
// Pure and total: junk in, a harmless value out. The clock is auto/stepTimer.ts.

/** What `?auto=…` asks for: `all` (kiosk), `steps` (normal), `off` (pause). */
export type AutoParam = 'all' | 'steps' | 'off';

/** Read a slide URL's `?auto` flag. Absent, bare or unknown → `null` (change nothing). */
export function readAutoParam(search: URLSearchParams | null | undefined): AutoParam | null {
	if (!search || !search.has('auto')) return null;
	const v = (search.get('auto') ?? '').trim().toLowerCase();
	return v === 'all' || v === 'steps' || v === 'off' ? v : null;
}

/**
 * The wait before a stopped build steps by itself, in ms; 0 = wait for ever.
 *
 * The narrowest level that SAYS something wins: the build, then the slide, then the
 * deck. Saying `0` (or anything not above zero) is saying "not here", which is how a
 * slide or a build opts out of a wider default. Only a number counts as saying
 * something; anything else falls through to the next level.
 */
export function resolveStepWait(levels: {
	deck?: unknown;
	slide?: unknown;
	build?: unknown;
}): number {
	for (const value of [levels?.build, levels?.slide, levels?.deck]) {
		if (typeof value !== 'number') continue;
		return Number.isFinite(value) && value > 0 ? value : 0;
	}
	return 0;
}

/**
 * The level in force on this slide.
 *
 * - `kiosk`  a kiosk session is live; it has its own pace and its own panel.
 * - `normal` the author gave a wait and nothing holds it: the countdown runs.
 * - `pause`  the author gave a wait and the viewer holds it. Click (or Alt+. H) resumes.
 * - `manual` no wait here, or this window must not move by itself (a recording, a
 *            replay, a live presenter console, `?shot`, ADJUST): nothing to count
 *            and nothing to toggle.
 */
export type StepAuto = 'kiosk' | 'normal' | 'pause' | 'manual';

export function stepAutoLevel(state: {
	/** A kiosk session is running or paused. */
	kiosk?: boolean;
	/** The author's wait for this build (`resolveStepWait`). */
	waitMs?: number;
	/** This window may not move by itself, whatever anyone chose. */
	forced?: boolean;
	/** The viewer holds the steps: their stored choice, or a step back on this slide. */
	held?: boolean;
}): StepAuto {
	if (state?.kiosk === true) return 'kiosk';
	const wait = typeof state?.waitMs === 'number' && state.waitMs > 0;
	if (!wait || state?.forced === true) return 'manual';
	return state?.held === true ? 'pause' : 'normal';
}

/**
 * Should the countdown be running? Only in `normal`, only while a step REMAINS (so it
 * never turns the page), and only once the step before it has finished playing — the
 * wait counts from when the build settles.
 */
export function stepTimerArmed(
	level: StepAuto,
	build: { hasNext?: boolean; busy?: boolean } | null | undefined
): boolean {
	return level === 'normal' && build?.hasNext === true && build?.busy !== true;
}

/**
 * Did the build just step BACK? Then the viewer wants to look at what came before, and
 * the slide holds until they step forward again. `undefined` = no opinion (first sight
 * of a build, or the index did not move).
 */
export function backHoldAfter(prevIndex: unknown, index: unknown): boolean | undefined {
	if (typeof prevIndex !== 'number' || typeof index !== 'number') return undefined;
	if (index < prevIndex) return true;
	if (index > prevIndex) return false;
	return undefined;
}

/** The whole seconds left, as the countdown shows them: 4.2 s reads "5", 0 reads "0". */
export function secondsLeft(leftMs: unknown): number {
	return typeof leftMs === 'number' && Number.isFinite(leftMs) && leftMs > 0
		? Math.ceil(leftMs / 1000)
		: 0;
}

/** The hint's tooltip in each toggleable level. */
export const STEP_AUTO_HOLD = 'Goes on by itself. Click to hold.';
export const STEP_AUTO_RESUME = 'Held. Click to go on by itself.';
