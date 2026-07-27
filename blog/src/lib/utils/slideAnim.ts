// Web Animations helpers for a slide's finite CSS @keyframes animations — the
// shared core behind the presenter's ANIMATE control (which reads/drives the
// local slide's animations for its rail) and the audience-side applier that
// replays a relayed {playing, fraction} command onto its own slide. Mirrors the
// scoping/filtering AnimationBar does internally; kept pure of Svelte so both
// sides use one implementation.

/** The relayed animation state: is it playing, and where in its 0..1 envelope. */
export interface AnimState {
	playing: boolean;
	fraction: number;
}

/** Wall-clock end of an animation (delay + active duration [+ end delay]); 0 for
    anything without a finite, numeric end (filtered out — not seekable). */
export function endTimeOf(a: Animation): number {
	const e = a.effect?.getComputedTiming().endTime;
	return typeof e === 'number' && Number.isFinite(e) ? e : 0;
}

/** Every finite, seekable CSS @keyframes animation in `scope` — excluding CSS
    *transitions* (Box/WideDiv) and infinite loops, which have no playable timeline. */
export function collectFinite(scope: Element | Document): Animation[] {
	const all = scope.getAnimations({ subtree: true });
	return all.filter((a) => {
		if (typeof CSSTransition !== 'undefined' && a instanceof CSSTransition) return false;
		return endTimeOf(a) > 0;
	});
}

/** Envelope length in ms (max end time across the group). */
export function envelope(anims: Animation[]): number {
	return anims.reduce((m, a) => Math.max(m, endTimeOf(a)), 0);
}

/** Live playhead as a 0..1 fraction — the furthest-advanced animation, each capped
    at its own end so a short early one can't peg the bar before the long one ends. */
export function sampleFraction(anims: Animation[]): number {
	const dur = envelope(anims);
	if (dur <= 0) return 0;
	let t = 0;
	for (const a of anims) {
		const ct = typeof a.currentTime === 'number' ? a.currentTime : 0;
		t = Math.max(t, Math.min(ct, endTimeOf(a)));
	}
	return Math.max(0, Math.min(1, t / dur));
}

/** True while any animation in the group is attached to the clock and advancing. */
export function isPlaying(anims: Animation[]): boolean {
	return anims.some((a) => a.playState === 'running');
}

/**
 * Attach the group to the clock — WITHOUT rewinding the animations that have already
 * finished.
 *
 * This is the one subtlety in driving a group of staggered animations, and a bare
 * `for (const a of anims) a.play()` gets it wrong. Per the Web Animations spec, `play()`
 * on an animation whose `currentTime` has reached its end **auto-rewinds it to 0** and
 * runs it again. A slide's animations do not share an end: `drawDelay` staggers a Draw or
 * Connector reveal, and each line of a Terminal session types on its own schedule. So
 * resuming from a pause partway through would replay every animation that had already
 * completed, alongside the ones still going.
 *
 * A finished animation is left exactly where it is. Its fill-mode holds its final frame
 * on screen whether or not it is attached to a clock, so nothing vanishes.
 *
 * Callers that want a finished GROUP to replay must seek it to 0 first — then nothing is
 * finished any more, and every animation plays.
 */
export function playGroup(anims: Animation[]): void {
	for (const a of anims) {
		const ct = typeof a.currentTime === 'number' ? a.currentTime : 0;
		if (ct >= endTimeOf(a)) continue;
		a.play();
	}
}

/** Detach the whole group from the clock. */
export function pauseGroup(anims: Animation[]): void {
	for (const a of anims) a.pause();
}

/** Seek the group to `fraction` (each animation clamped to its own end so staggered
    delays settle coherently), then play or pause the whole group to match `playing`. */
export function applyState(anims: Animation[], state: AnimState): void {
	const dur = envelope(anims);
	const t = Math.max(0, Math.min(1, state.fraction)) * dur;
	for (const a of anims) a.currentTime = Math.min(t, endTimeOf(a));
	if (state.playing) playGroup(anims);
	else pauseGroup(anims);
}
