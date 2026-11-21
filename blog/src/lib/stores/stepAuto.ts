import { get, writable, type Writable } from 'svelte/store';
import { browser } from '$app/environment';
import { persisted } from './persisted';
import { booleanCodec } from '$lib/utils/stateCore';
import { readAutoParam } from '$lib/auto/stepAutoCore';
import type { StepCountdown } from '$lib/auto/stepTimer';

// The viewer's side of the auto levels (auto/stepAutoCore.ts): do steps go on by
// themselves here, or are they held?
//
// `stepHold` is the stored choice — "pause". It is persisted, so it survives the full
// page load every page turn is, and a reload. `sync: false`: a second window of the same
// deck (the presenter console, another tab) keeps its own; one viewer holding a slide
// must not hold everybody's.
//
// The rest is live state of ONE slide, never stored: a hold left by a step back, the
// pointer resting on the hint, and the countdown SlideDeck's timer publishes for the
// hint to draw.

/** The viewer holds the steps (the "pause" level). */
export const stepHold = persisted('geekpresent:auto:hold', false, {
	codec: booleanCodec(),
	sync: false
});

/** A step BACK on this slide holds it until the viewer steps forward again. */
export const stepBackHold: Writable<boolean> = writable(false);

/** The pointer is on the hint: the countdown waits, with the time left kept. */
export const stepHoverFrozen: Writable<boolean> = writable(false);

/** The running countdown, or null when nothing is counting. */
export const stepCountdown: Writable<StepCountdown | null> = writable(null);

/**
 * Flip what the viewer sees: held → going on by itself, and back. A hold that came from
 * a step back is simply lifted; otherwise the stored choice flips.
 */
export function toggleStepHold(): void {
	if (get(stepBackHold)) {
		stepBackHold.set(false);
		stepHold.set(false);
	} else {
		stepHold.update((held) => !held);
	}
}

/**
 * Apply a slide URL's `?auto` flag to the stored choice: `off` holds, `steps` and `all`
 * release. Call ONCE per page load, not reactively — the hint's click must not be undone
 * by a URL that still says `?auto=off`. (`all` also starts the kiosk: stores/kiosk.ts.)
 */
export function applyAutoParam(url: URL): void {
	if (!browser) return;
	const auto = readAutoParam(url.searchParams);
	if (auto === null) return;
	stepHold.set(auto === 'off');
}
