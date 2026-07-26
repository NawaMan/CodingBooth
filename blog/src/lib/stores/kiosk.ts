/*
  Kiosk session state — offered vs running, paces, pause, notes-for-timing.

  Offered (canKiosk) follows the same sticky-URL pattern as ANNOTATE / CAPTURE.
  Running is a *session* preference: OK in the dialog or `?kiosk` starts it and
  survives full-page slide loads (`kioskWantsRun` in **sessionStorage**); Stop /
  `?kiosk=off` clears it. It must NOT live in localStorage — that made a past
  Start resurrect kiosk on every later visit ("started by default"). Session
  storage keeps a mid-loop full-page nav running, and clears when the tab closes.
  Paces and the notes toggle are remembered across reloads so a booth keeps its
  tuning; they do not cross-tab-sync (a second tab editing paces should not yank
  the lobby screen mid-loop — same bargain as displayMode).
*/

import { derived, get, writable, type Readable, type Writable } from 'svelte/store';
import { browser } from '$app/environment';
import { persisted } from '$lib/stores/persisted';
import { booleanCodec, jsonCodec } from '$lib/utils/stateCore';
import {
	DEFAULT_PAGE_MS,
	DEFAULT_STEP_MS,
	clampPaceMs,
	readKioskParam,
	readSticky,
	resolveCanKiosk,
	type Choice
} from '$lib/kiosk/kioskCore';
import { clearAllKioskMediaHold } from '$lib/stores/kioskMediaHold';

export type KioskStatus = 'off' | 'running' | 'paused';

/** Is the Kiosk menu offered? (Not the same as running.) */
export const canKiosk: Writable<boolean> = writable(false);

/** Live status for the indicator and runner. */
export const kioskStatus: Writable<KioskStatus> = writable('off');

/** True while status is running or paused — notes may mount for measurement. */
export const kioskActive: Readable<boolean> = derived(
	kioskStatus,
	($s) => $s === 'running' || $s === 'paused'
);

/** True while the pointer sits over the panel. Freezes KioskRunner's clock (the
    dwell countdown stops advancing) WITHOUT touching `kioskStatus` — the play/pause
    icon, aria-label and `.paused` styling must keep reporting the real, explicit
    mode. Transient (not persisted): driven live by mouseenter/mouseleave in
    KioskIndicator, reset by `stopKiosk()` so a stale `true` can't survive into the
    next session if the panel unmounts mid-hover (Stop while hovering fires no
    mouseleave — the element is simply removed). */
export const kioskHoverFrozen: Writable<boolean> = writable(false);

/** Survives full-page nav in this tab so a non-ViewTransition deck keeps
    auto-advancing — sessionStorage, not localStorage (see file header). */
export const kioskWantsRun = persisted('geekpresent:kiosk:wantsRun', false, {
	codec: booleanCodec(),
	sync: false,
	storage: 'session'
});

// Drop a leftover localStorage flag from older builds so it cannot confuse
// debugging (or a future reader that mistakes the key for still being active).
if (browser) {
	try {
		localStorage.removeItem('geekpresent:kiosk:wantsRun');
	} catch {
		/* private mode */
	}
}

export interface KioskPaces {
	stepMs: number;
	pageMs: number;
	useNotes: boolean;
}

const defaultPaces = (): KioskPaces => ({
	stepMs: DEFAULT_STEP_MS,
	pageMs: DEFAULT_PAGE_MS,
	useNotes: false
});

/** Session overrides for paces / notes. `null` fields mean "use deck prop". */
export interface KioskPaceOverride {
	stepMs?: number;
	pageMs?: number;
	useNotes?: boolean;
}

export const kioskPaceOverride = persisted<KioskPaceOverride>(
	'geekpresent:kiosk:paces',
	{},
	{ codec: jsonCodec<KioskPaceOverride>(), sync: false }
);

/** Dialog open (setup / reconfigure). */
export const kioskDialogOpen: Writable<boolean> = writable(false);

/** Deck defaults pushed from SlideDeck props each render. */
export const kioskDeckDefaults: Writable<KioskPaces> = writable(defaultPaces());

/** Effective paces: override wins when set, else deck default. */
export const kioskPaces: Readable<KioskPaces> = derived(
	[kioskPaceOverride, kioskDeckDefaults],
	([$o, $d]) => ({
		stepMs: clampPaceMs($o.stepMs ?? $d.stepMs, $d.stepMs),
		pageMs: clampPaceMs($o.pageMs ?? $d.pageMs, $d.pageMs),
		useNotes: typeof $o.useNotes === 'boolean' ? $o.useNotes : $d.useNotes
	})
);

/** Indicator: fraction 0..1 of the current dwell (runner updates). */
export const kioskDwellFraction: Writable<number> = writable(0);

/** Indicator label: 'step' | 'page' | 'wait' | '' */
export const kioskPhaseLabel: Writable<string> = writable('');

/** Ordered note lines for the current slide (Note publishes; caption + runner read). */
export const kioskNoteItems: Writable<string[]> = writable([]);

/** 0-based index of the note line currently shown (and being dwelt on). */
export const kioskNoteIndex: Writable<number> = writable(0);

/** Panel position (viewport px). Remembered while the session runs. */
export interface KioskNotesPos {
	left: number;
	top: number;
}
export const kioskNotesPos: Writable<KioskNotesPos | null> = writable(null);

/** Forced-visible pin — overrides the panel's idle opacity so a speaker can reveal
    it without a mouse (Alt+. K while a kiosk is live; see chromeArmCore). Persisted
    like chromePin's bar pins, `sync: false` for the same reason: a console window
    and the audience window each keep their own reveal state. */
export const kioskPanelPinned = persisted<boolean>('geekpresent:kiosk:pinned', false, {
	codec: booleanCodec(),
	sync: false
});

/** Replace the note list for this slide. Resets the index only when the list changes
    (MutationObserver re-publishes often; we must not rewind mid-step). */
export function setKioskNoteItems(items: string[]): void {
	const list = Array.isArray(items)
		? items.map((t) => String(t).trim()).filter((t) => t.length > 0)
		: [];
	const prev = get(kioskNoteItems);
	const same = prev.length === list.length && prev.every((t, i) => t === list[i]);
	if (same) return;
	kioskNoteItems.set(list);
	kioskNoteIndex.set(0);
}

/** Clear note state (kiosk off or note source unmounted). */
export function clearKioskNotes(): void {
	kioskNoteItems.set([]);
	kioskNoteIndex.set(0);
}

/**
 * Advance to the next note item. Returns true if there is still an item to show
 * after the advance (or we were already mid-list); false if we left the last item
 * (caller should page).
 */
export function advanceKioskNote(): boolean {
	const items = get(kioskNoteItems);
	const i = get(kioskNoteIndex);
	if (items.length === 0) return false;
	if (i + 1 < items.length) {
		kioskNoteIndex.set(i + 1);
		return true;
	}
	// Past the end — index === length so hasNoteItem goes false (no re-dwell).
	kioskNoteIndex.set(items.length);
	return false;
}

export function setCanKiosk(offered: boolean): void {
	canKiosk.set(!!offered);
}

/** Persist sticky offer from `?kiosk` / `?kiosk=off`. Does NOT start/stop —
    call `bootKioskFromUrl` once on mount for that (avoids a Stop being undone by
    a reactive re-apply while the URL still says `?kiosk`). */
export function applyKioskParam(url: URL): void {
	if (!browser) return;
	const choice = readKioskParam(url.searchParams);
	if (choice !== null) {
		try {
			localStorage.setItem('canKiosk', String(choice));
		} catch {
			/* private mode */
		}
	}
}

/**
 * One-shot boot: `?kiosk` starts, `?kiosk=off` stops, absent restores a session
 * that still wants to run (full-page nav mid-loop).
 */
export function bootKioskFromUrl(url: URL): void {
	if (!browser) return;
	const choice = readKioskParam(url.searchParams);
	applyKioskParam(url);
	if (choice === true) startKiosk();
	else if (choice === false) stopKiosk();
	else restoreKioskIfWanted();
}

export function resolveOffered(dev: boolean, deckWide: boolean): boolean {
	if (!browser) return dev || deckWide;
	let sticky = readSticky(localStorage.getItem('canKiosk'));
	// Live URL flag also counts as an offer for this page (before sticky is written).
	const live = readKioskParam(
		typeof window !== 'undefined' ? new URL(window.location.href).searchParams : null
	);
	if (live !== null) sticky = live;
	return resolveCanKiosk(dev, sticky, deckWide);
}

export function openKioskDialog(): void {
	kioskDialogOpen.set(true);
}

export function closeKioskDialog(): void {
	kioskDialogOpen.set(false);
}

/** Commit dialog paces and start (or resume) running. */
export function confirmKiosk(paces: KioskPaces): void {
	kioskPaceOverride.set({
		stepMs: clampPaceMs(paces.stepMs, DEFAULT_STEP_MS),
		pageMs: clampPaceMs(paces.pageMs, DEFAULT_PAGE_MS),
		useNotes: !!paces.useNotes
	});
	startKiosk();
	kioskDialogOpen.set(false);
}

export function startKiosk(): void {
	kioskWantsRun.set(true);
	kioskStatus.set('running');
	kioskDwellFraction.set(0);
}

export function pauseKiosk(): void {
	if (get(kioskStatus) === 'running') kioskStatus.set('paused');
}

export function resumeKiosk(): void {
	if (get(kioskStatus) === 'paused') kioskStatus.set('running');
}

export function toggleKioskPause(): void {
	const s = get(kioskStatus);
	if (s === 'running') kioskStatus.set('paused');
	else if (s === 'paused') kioskStatus.set('running');
}

export function stopKiosk(): void {
	kioskWantsRun.set(false);
	kioskStatus.set('off');
	kioskDwellFraction.set(0);
	kioskPhaseLabel.set('');
	kioskDialogOpen.set(false);
	kioskHoverFrozen.set(false);
	clearKioskNotes();
	clearAllKioskMediaHold();
}

/** After a full page load: resume if the session still wants to run. */
export function restoreKioskIfWanted(): void {
	if (!browser) return;
	if (get(kioskWantsRun) && get(kioskStatus) === 'off') {
		kioskStatus.set('running');
	}
}
