// recordBus — the wire between a deck's slides window and the VOD Recorder window.
//
// See specs/VOD-RECORD-1.md ("Protocol"). One BroadcastChannel for every deck; every
// message names its deck and every party ignores the others. The Recorder's STATE also
// rides localStorage with a timestamp, because a slides window that has just loaded (and
// the deck reloads on every page turn) must know at once whether it is being recorded —
// before any message could reach it — and a Recorder that closed sends no farewell, so a
// state older than STATUS_TTL_MS reads idle.
//
// The deck side is three calls: `reportAction` (a no-op unless this window is the one
// being recorded), `onRecorderCommand` (replay), and `announceHere` (I have loaded, here
// is my slide). Everything else is the Recorder's.

import { browser } from '$app/environment';
import { derived, get, writable, type Readable } from 'svelte/store';
import { relativeHref, type TimelineAction } from './timelineCore';

export const RECORDER_CHANNEL = 'geekpresent:recorder';
export const STATUS_TTL_MS = 5000;
export const STATUS_BEAT_MS = 1000;

export type RecorderState = 'idle' | 'armed' | 'recording' | 'replaying';

export interface HereInfo {
	/** The slide's full href (with query), as the window shows it. */
	href: string;
	/** Its pathname without a trailing slash — what replay compares a `goto` against. */
	path: string;
	width: number;
	height: number;
	title: string;
}

export type RecorderMessage =
	| { type: 'hello'; deck: string }
	| { type: 'here'; deck: string; here: HereInfo }
	| { type: 'leaving'; deck: string }
	| { type: 'status'; deck: string; state: RecorderState }
	| { type: 'action'; deck: string; action: TimelineAction }
	| { type: 'cmd'; deck: string; action: TimelineAction };

const statusKey = (deck: string) => `geekpresent:recorder:${deck}`;

/** Read the stored Recorder state for a deck, judging staleness against `now`. Pure. */
export function readStoredState(raw: string | null | undefined, now: number, ttl = STATUS_TTL_MS): RecorderState {
	if (!raw) return 'idle';
	try {
		const v = JSON.parse(raw) as { state?: unknown; ts?: unknown };
		const ok = v.state === 'armed' || v.state === 'recording' || v.state === 'replaying';
		if (!ok || typeof v.ts !== 'number' || !Number.isFinite(v.ts)) return 'idle';
		return now - v.ts <= ttl ? (v.state as RecorderState) : 'idle';
	} catch {
		return 'idle';
	}
}

/** Is this a message of ours, for this deck? */
export function isRecorderMessage(data: unknown, deck: string): data is RecorderMessage {
	if (!data || typeof data !== 'object') return false;
	const m = data as { type?: unknown; deck?: unknown };
	return m.deck === deck && typeof m.type === 'string' && ['hello', 'here', 'leaving', 'status', 'action', 'cmd'].includes(m.type);
}

let channel: BroadcastChannel | null = null;
function bus(): BroadcastChannel | null {
	if (!browser || typeof BroadcastChannel === 'undefined') return null;
	if (!channel) channel = new BroadcastChannel(RECORDER_CHANNEL);
	return channel;
}

export function post(msg: RecorderMessage): void {
	try {
		bus()?.postMessage(msg);
	} catch {
		/* a closed channel, or a payload that will not clone — best-effort */
	}
}

/** Listen to every message for `deck`. Returns an unsubscribe. */
export function listen(deck: string, cb: (msg: RecorderMessage) => void): () => void {
	const b = bus();
	if (!b) return () => {};
	const on = (e: MessageEvent) => {
		if (isRecorderMessage(e.data, deck)) cb(e.data);
	};
	b.addEventListener('message', on);
	return () => b.removeEventListener('message', on);
}

// --- The Recorder side -------------------------------------------------------------------

/** Publish the Recorder's state (message + stored copy). Call on change and on a beat. */
export function publishState(deck: string, state: RecorderState): void {
	if (!browser) return;
	try {
		if (state === 'idle') localStorage.removeItem(statusKey(deck));
		else localStorage.setItem(statusKey(deck), JSON.stringify({ state, ts: Date.now() }));
	} catch {
		/* storage refused — the message still goes */
	}
	post({ type: 'status', deck, state });
}

// --- The slides-window side --------------------------------------------------------------

/** The Recorder's state as THIS deck window sees it. */
export const recorderState = writable<RecorderState>('idle');
/** True while a take is running (recording or replaying) — the bars tuck away and the
    slide shows FITTED, so the video is the slide and nothing else. */
export const recordingLook: Readable<boolean> = derived(recorderState, (s) => s === 'recording' || s === 'replaying');
/** True while REPLAY drives this window — local input and console relays are ignored. */
export const replaying: Readable<boolean> = derived(recorderState, (s) => s === 'replaying');

let reportingDeck: string | null = null;

/** Called by SlideDeck: this window is (or stops being) the deck's slides window — the
    top-level, non-console window whose actions a recording should hear. */
export function setReportingDeck(deck: string | null): void {
	reportingDeck = deck;
}

/** Report an action this window just performed. A no-op unless this is the slides window
    of a deck that is being recorded right now — so the hooks can call it unconditionally. */
export function reportAction(action: TimelineAction): void {
	if (!reportingDeck || get(recorderState) !== 'recording') return;
	post({ type: 'action', deck: reportingDeck, action });
}

/** Report a page turn: `href` as navigate() was handed it, named relative to the deck. */
export function reportGoto(href: string, back: boolean, end: boolean): void {
	if (!reportingDeck || get(recorderState) !== 'recording') return;
	const action: TimelineAction = { kind: 'goto', href: relativeHref(href, reportingDeck, window.location.href) };
	if (back) action.back = true;
	if (end) action.end = true;
	reportAction(action);
}

/** Say the page is about to unload, so the Recorder can freeze the video on the slide
    still showing until the next one says `here`. Only during a take (or its start). */
export function reportLeaving(): void {
	if (!reportingDeck || get(recorderState) === 'idle') return;
	post({ type: 'leaving', deck: reportingDeck });
}

/** Seed `recorderState` from storage and follow the Recorder (messages + a staleness poll).
    Returns a stop. */
export function followRecorder(deck: string): () => void {
	if (!browser) return () => {};
	let lastBeat = Date.now();
	const read = () => {
		try {
			return readStoredState(localStorage.getItem(statusKey(deck)), Date.now());
		} catch {
			return 'idle' as RecorderState;
		}
	};
	recorderState.set(read());
	const stop = listen(deck, (m) => {
		if (m.type === 'status') {
			lastBeat = Date.now();
			recorderState.set(m.state);
		}
	});
	const poll = window.setInterval(() => {
		if (Date.now() - lastBeat > STATUS_TTL_MS && get(recorderState) !== 'idle') recorderState.set(read());
	}, STATUS_BEAT_MS);
	return () => {
		stop();
		window.clearInterval(poll);
		recorderState.set('idle');
	};
}
