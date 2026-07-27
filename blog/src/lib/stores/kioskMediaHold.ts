/*
  Multi-owner "media is still playing" hold for the kiosk runner.

  Video registers while a playthrough is in progress; KioskRunner treats any
  holder as `mediaBusy` (wait — above reveal/note/page) and drives the indicator
  from the least-finished fraction. Same multi-owner idea as activeSteps, but a
  Map so two players on one slide both get to finish.
*/

import { derived, get, writable, type Readable } from 'svelte/store';
import { aggregateMediaFraction } from '$lib/utils/videoKioskCore';

export interface MediaHoldEntry {
	fraction: number;
	remainingMs: number;
}

const holders = writable<Map<object, MediaHoldEntry>>(new Map());

/** Publish or refresh this owner's hold. */
export function setKioskMediaHold(
	owner: object,
	entry: { fraction: number; remainingMs: number }
): void {
	const fraction = Number(entry.fraction);
	const remainingMs = Number(entry.remainingMs);
	holders.update((m) => {
		const next = new Map(m);
		next.set(owner, {
			fraction: Number.isFinite(fraction) ? Math.max(0, Math.min(1, fraction)) : 0,
			remainingMs: Number.isFinite(remainingMs) && remainingMs > 0 ? remainingMs : 0
		});
		return next;
	});
}

/** Drop this owner (ended, unmount, kioskHold off). */
export function clearKioskMediaHold(owner: object): void {
	holders.update((m) => {
		if (!m.has(owner)) return m;
		const next = new Map(m);
		next.delete(owner);
		return next;
	});
}

/** Drop every owner — kiosk Stop / session end. */
export function clearAllKioskMediaHold(): void {
	if (get(holders).size === 0) return;
	holders.set(new Map());
}

/** True while any Video (or future media) is holding the runner. */
export const kioskMediaBusy: Readable<boolean> = derived(holders, ($m) => $m.size > 0);

/** 0..1 — least-finished holder (1 only when every clip is done / none). */
export const kioskMediaProgress: Readable<number> = derived(holders, ($m) => {
	if ($m.size === 0) return 0;
	return aggregateMediaFraction([...$m.values()].map((e) => e.fraction));
});
