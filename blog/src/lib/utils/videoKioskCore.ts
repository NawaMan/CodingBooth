/*
  Pure decisions for Video ↔ Kiosk.

  - When should a player auto-start? (`true` always, `'kiosk'` only while the
    session is active, `false` never.)
  - When should muted default on? (Any mode that may autoplay — browsers refuse
    autoplay with sound.)
  - When should kiosk *hold* for this playthrough? (Until the first natural end
    of the cycle; loop restarts the element but must not trap the runner.)
  - Progress for the kiosk indicator while holding.
*/

/** Author-facing autoplay prop: always, never, or only in a kiosk session. */
export type VideoAutoplay = boolean | 'kiosk';

/** Normalize a loose prop value into a known mode. Junk → never. */
export function normalizeAutoplay(value: unknown): VideoAutoplay {
	if (value === true || value === 'true' || value === 1 || value === '1') return true;
	if (value === 'kiosk') return 'kiosk';
	return false;
}

/** Should the media element be trying to play right now (prop-only)? */
export function wantsAutoplay(autoplay: unknown, kioskActive: boolean): boolean {
	const mode = normalizeAutoplay(autoplay);
	if (mode === true) return true;
	if (mode === 'kiosk') return kioskActive === true;
	return false;
}

/**
 * Full play intent: authored autoplay, **or** kiosk is running a content hold.
 *
 * A `kioskHold` video must actually play during kiosk — otherwise the runner falls
 * through to `activeSteps` chapter seeks on a *paused* playhead (jump to the first
 * bookmark and sit there). Hold-driven play is one cycle (`cycleDone` ends it).
 */
export function wantsPlay(state: {
	autoplay: unknown;
	kioskActive: boolean;
	kioskHold: boolean;
	cycleDone: boolean;
}): boolean {
	if (wantsAutoplay(state.autoplay, state.kioskActive)) return true;
	if (state.kioskActive === true && state.kioskHold === true && state.cycleDone !== true) {
		return true;
	}
	return false;
}

/**
 * Default for `muted` when the author left it unset. Any mode that *can* autoplay
 * starts muted so a later kiosk Start still satisfies the browser policy.
 * (Hold-driven kiosk play mutes at Start time in the component — not here — so a
 * normal Video does not ship muted just because kioskHold defaults true.)
 */
export function defaultMutedForAutoplay(autoplay: unknown): boolean {
	const mode = normalizeAutoplay(autoplay);
	return mode === true || mode === 'kiosk';
}

/**
 * While kiosk runs, a content video must not publish chapter steps — the runner
 * would seek bookmark-to-bookmark on the step clock instead of watching the tape.
 * Presenter Space-stepping (`keys="global"`) returns when kiosk ends.
 */
export function shouldDriveChapterSteps(state: {
	keysGlobal: boolean;
	hasMarks: boolean;
	kioskActive: boolean;
}): boolean {
	if (state.keysGlobal !== true) return false;
	if (state.hasMarks !== true) return false;
	if (state.kioskActive === true) return false;
	return true;
}

/**
 * Should this player register a kiosk media hold?
 *
 * Holds while the session is active, the author allows it, the cycle is not yet
 * done, and the clip is in a playthrough (playing, paused mid-clip, or about to
 * autoplay from the start). An unstarted, non-autoplay clip at 0:00 does not hold
 * — that would freeze the booth on a poster forever.
 */
export function shouldHoldForKiosk(state: {
	kioskHold: boolean;
	kioskActive: boolean;
	cycleDone: boolean;
	/** Effective autoplay right now (after mode + session). */
	wantPlay: boolean;
	paused: boolean;
	currentTime: number;
	duration: number;
}): boolean {
	if (state.kioskHold !== true) return false;
	if (state.kioskActive !== true) return false;
	if (state.cycleDone === true) return false;

	const t = Number(state.currentTime);
	const d = Number(state.duration);
	const time = Number.isFinite(t) && t > 0 ? t : 0;
	const hasDuration = Number.isFinite(d) && d > 0;
	// Past the end (or exactly at end) with a known length → not holding.
	if (hasDuration && time >= d - 1e-3) return false;

	if (state.paused !== true) return true; // playing
	if (time > 0) return true; // paused mid-clip
	if (state.wantPlay === true) return true; // waiting to / about to autoplay
	return false;
}

/** Played fraction 0..1 for the indicator. Unknown duration → 0. */
export function mediaHoldFraction(currentTime: number, duration: number): number {
	const d = Number(duration);
	const t = Number(currentTime);
	if (!Number.isFinite(d) || d <= 0) return 0;
	if (!Number.isFinite(t) || t <= 0) return 0;
	return Math.max(0, Math.min(1, t / d));
}

/** Remaining ms of the clip (0 when unknown or finished). */
export function mediaHoldRemainingMs(currentTime: number, duration: number): number {
	const d = Number(duration);
	const t = Number(currentTime);
	if (!Number.isFinite(d) || d <= 0) return 0;
	const played = Number.isFinite(t) && t > 0 ? t : 0;
	return Math.max(0, Math.round((d - played) * 1000));
}

/**
 * Aggregate progress across every holder: use the *least* finished clip so the
 * indicator only reaches 1 when every video on the slide is done.
 */
export function aggregateMediaFraction(fractions: number[]): number {
	if (!fractions.length) return 0;
	let min = 1;
	for (const f of fractions) {
		const n = Number(f);
		if (!Number.isFinite(n)) continue;
		min = Math.min(min, Math.max(0, Math.min(1, n)));
	}
	return min === 1 && fractions.every((f) => !Number.isFinite(Number(f))) ? 0 : min;
}

/**
 * Effective `loop` on the media element during a kiosk hold.
 *
 * The HTML `loop` attribute **suppresses** the `ended` event — the playhead wraps
 * silently and a hold waiting on `ended` never releases (stuck forever on a
 * looping demo). While kiosk is holding for one playthrough, force `loop` off so
 * `ended` fires; after `cycleDone` (or outside kiosk) the author's `loop` returns.
 */
export function effectiveMediaLoop(state: {
	loop: boolean;
	kioskActive: boolean;
	kioskHold: boolean;
	cycleDone: boolean;
}): boolean {
	if (state.loop !== true) return false;
	// One-shot hold in progress → strip loop so the cycle can end.
	if (
		state.kioskActive === true &&
		state.kioskHold === true &&
		state.cycleDone !== true
	) {
		return false;
	}
	return true;
}

/**
 * Playhead wrapped because of `loop` (ended never fired). Used as a belt-and-
 * braces release if loop was not stripped in time.
 *
 * True when time jumps backwards by a meaningful amount after having advanced —
 * not a tiny scrub glitch.
 */
export function isLoopWrap(prevTime: number, nextTime: number, duration: number): boolean {
	const prev = Number(prevTime);
	const next = Number(nextTime);
	if (!Number.isFinite(prev) || !Number.isFinite(next)) return false;
	if (prev < 0.5) return false; // never really started
	// Jump back by at least 1s, and not a tiny decoder blip near the same point.
	if (next >= prev - 1) return false;
	const d = Number(duration);
	if (Number.isFinite(d) && d > 0) {
		// Prefer "was near the end" — avoids treating a chapter seek as a wrap.
		return prev >= d * 0.5 || prev >= d - 2;
	}
	return prev - next >= 1;
}
