import { writable } from 'svelte/store';
import { browser } from '$app/environment';
import type { AnimState } from '$lib/utils/slideAnim';
import { mayFollow, parseAnnouncement, type RelayRole } from '$lib/utils/relayCore';

// Presenter View — a second window (opened with ?present) that mirrors the
// audience deck: it shows the current slide's <Note>, big NAV buttons, a clock
// and elapsed timer, and a preview of the next slide. The two windows page in
// lock-step through a single localStorage value + `storage` events — the same
// cross-window channel the deck already uses for displayMode/displayFactor.

/** True in a window showing the presenter console (loaded with ?present). Set by
    SlideDeck; read by <Note> (so a note renders as the presenter panel, not only
    in SCALED mode) and by NavigationBar (so paging keeps the ?present flag). */
export const presenterMode = writable<boolean>(false);

/** True in an AUDIENCE window when a ?present console for the same deck is currently
    live (heartbeating — see publishConsoleAlive / the console channel below). Set by
    SlideDeck's audience branch; read by <Note> so the redundant below-slide SCALED
    note yields once the console is carrying the notes. Defaults false, so a deck with
    no console open (and every prerender) keeps the below-slide note as the fallback. */
export const consoleLive = writable<boolean>(false);

/** The deck a slide belongs to, as its route prefix — the sync namespace, so two
    decks (/slides/ vs /portrait/) never cross-drive each other. Examples:
    "/slides/intro.html" -> "/slides/", "/slides/intro.html/" -> "/slides/". */
export function deckKeyFromPath(pathname: string): string {
	const noTrail = pathname.replace(/\/+$/, ''); // drop trailing slash(es)
	return noTrail.slice(0, noTrail.lastIndexOf('/') + 1) || '/';
}

const keyFor = (deckKey: string) => `geekpresent:current:${deckKey}`;

/** Announce that THIS window is now showing `path` (the bare slide path from
    pages.ts, e.g. "intro.html" — no flag). Written to localStorage; the OTHER
    window hears it via a `storage` event. Re-writing the same path with a fresh
    `ts` still fires the event, so re-selecting the current slide re-broadcasts.
    Best-effort and a no-op off-browser.

    `role` TAGS the announcement with the kind of window that sent it, which is what
    lets the listener decide whether it may be driven by this sender at all — see
    utils/relayCore. It is optional and defaults to 'audience' so an older caller
    (and every existing test) keeps its meaning. */
export function publishCurrentSlide(
	deckKey: string,
	path: string,
	role: RelayRole = 'audience'
): void {
	if (!browser || !path) return;
	try {
		localStorage.setItem(keyFor(deckKey), JSON.stringify({ path, ts: Date.now(), role }));
	} catch {
		// localStorage can throw (private mode / quota); sync is best-effort.
	}
}

/** Subscribe to the OTHER window's current-slide announcements for this deck.
    Calls `cb(path)` with the bare slide path. `storage` events never fire in the
    window that wrote them, so a publisher never hears its own write — the caller
    still guards `path !== mine` to stop the follow ping-pong from looping.
    Returns an unsubscribe; a no-op unsubscribe off-browser.

    `me` is THIS window's role, and it is the fix for the multi-tab lock-step bug:
    an announcement is delivered only when its sender's role DIFFERS from `me`, so
    the console and its audience cross-drive while two ordinary audience tabs of one
    deck ignore each other. Defaults to 'audience'; a sender that predates roles is
    read as 'audience' too (relayCore.asRole), so this stays the old broadcast only
    between two untagged windows. */
export function subscribeCurrentSlide(
	deckKey: string,
	cb: (path: string) => void,
	me: RelayRole = 'audience'
): () => void {
	if (!browser) return () => {};
	const key = keyFor(deckKey);
	const onStorage = (e: StorageEvent) => {
		if (e.key !== key) return;
		const announcement = parseAnnouncement(e.newValue);
		if (!announcement) return; // absent, malformed, or pathless — ignore
		if (!mayFollow(announcement.role, me)) return; // not our driver
		cb(announcement.path);
	};
	window.addEventListener('storage', onStorage);
	return () => window.removeEventListener('storage', onStorage);
}

// ANIMATE relay — a second channel, same mechanism. The presenter's animation
// control emits {playing, fraction} here; the audience window applies it to its
// live slide (see utils/slideAnim.applyState). One-directional (presenter drives).
const animKeyFor = (deckKey: string) => `geekpresent:anim:${deckKey}`;

/** Relay an animation command to the OTHER window for this deck. */
export function publishAnimCommand(deckKey: string, cmd: AnimState): void {
	if (!browser) return;
	try {
		localStorage.setItem(animKeyFor(deckKey), JSON.stringify({ ...cmd, ts: Date.now() }));
	} catch {
		// best-effort
	}
}

/** Subscribe to relayed animation commands for this deck. Returns an unsubscribe. */
export function subscribeAnimCommand(deckKey: string, cb: (cmd: AnimState) => void): () => void {
	if (!browser) return () => {};
	const key = animKeyFor(deckKey);
	const onStorage = (e: StorageEvent) => {
		if (e.key !== key || !e.newValue) return;
		try {
			const { playing, fraction } = JSON.parse(e.newValue) as Partial<AnimState>;
			if (typeof playing === 'boolean' && typeof fraction === 'number') cb({ playing, fraction });
		} catch {
			// ignore malformed payloads
		}
	};
	window.addEventListener('storage', onStorage);
	return () => window.removeEventListener('storage', onStorage);
}

// CONTINUE relay — a pulse channel. CONTINUE is an in-slide action (the deck's
// onContinue hook), not a navigation, so the presenter can't page to it; instead
// its CONTINUE button fires a pulse here and the audience window turns it into a
// `gp:continue` DOM event (SlideDeck) that NavigationBar routes to onContinue.
const contKeyFor = (deckKey: string) => `geekpresent:continue:${deckKey}`;

/** Fire a CONTINUE pulse to the OTHER window for this deck. */
export function publishContinue(deckKey: string): void {
	if (!browser) return;
	try {
		// A fresh ts each press so re-pressing the same slide always fires the event.
		localStorage.setItem(contKeyFor(deckKey), JSON.stringify({ ts: Date.now() }));
	} catch {
		// best-effort
	}
}

/** Subscribe to CONTINUE pulses for this deck. Returns an unsubscribe. */
export function subscribeContinue(deckKey: string, cb: () => void): () => void {
	if (!browser) return () => {};
	const key = contKeyFor(deckKey);
	const onStorage = (e: StorageEvent) => {
		if (e.key === key && e.newValue) cb();
	};
	window.addEventListener('storage', onStorage);
	return () => window.removeEventListener('storage', onStorage);
}

// HIGHLIGHT relay — the note-driven spotlight. A <Note> line covered in the console
// publishes the target Block's `name` (or `null` to clear) here; the audience window
// hears it (SlideDeck) and calls `setHighlight`, so <Spotlight> rings that box on the
// live slide. A STATE channel (which box is lit), unlike CONTINUE's pulse — but it
// still carries a fresh `ts` so re-lighting the same box after a clear re-fires the
// `storage` event (which only fires when the stored VALUE changes).
const highlightKeyFor = (deckKey: string) => `geekpresent:highlight:${deckKey}`;

/** Publish the spotlight target (a Block `name`, or `null` to clear) to the OTHER
    window for this deck. */
export function publishHighlight(deckKey: string, name: string | null): void {
	if (!browser) return;
	try {
		localStorage.setItem(highlightKeyFor(deckKey), JSON.stringify({ name: name ?? null, ts: Date.now() }));
	} catch {
		// best-effort
	}
}

/** Subscribe to spotlight-target changes for this deck. `cb` gets the name or null.
    Returns an unsubscribe. */
export function subscribeHighlight(deckKey: string, cb: (name: string | null) => void): () => void {
	if (!browser) return () => {};
	const key = highlightKeyFor(deckKey);
	const onStorage = (e: StorageEvent) => {
		if (e.key !== key || !e.newValue) return;
		try {
			const { name } = JSON.parse(e.newValue) as { name: string | null };
			cb(typeof name === 'string' && name ? name : null);
		} catch {
			// A malformed value clears rather than throws.
			cb(null);
		}
	};
	window.addEventListener('storage', onStorage);
	return () => window.removeEventListener('storage', onStorage);
}

// TRIGGER relay — the note-driven "start this" pulse. A <Note> line's
// checkbox, when checked and carrying `data-trigger="name"`, publishes that
// name here; the audience window hears it (SlideDeck) and calls
// `fireTrigger`, so any listener (a <Cursor startOn="name">, today) reacts.
// A PULSE channel like CONTINUE, not a persistent state like HIGHLIGHT — a
// note check is a one-off "now", so every publish carries a fresh `ts` and
// the receiver is handed the name on every fire, including a repeat of the
// same name (re-checking a line replays it).
const triggerKeyFor = (deckKey: string) => `geekpresent:trigger:${deckKey}`;

/** Fire a named trigger pulse to the OTHER window for this deck. */
export function publishTrigger(deckKey: string, name: string): void {
	if (!browser || !name) return;
	try {
		localStorage.setItem(triggerKeyFor(deckKey), JSON.stringify({ name, ts: Date.now() }));
	} catch {
		// best-effort
	}
}

/** Subscribe to trigger pulses for this deck. `cb` gets the fired name.
    Returns an unsubscribe. */
export function subscribeTrigger(deckKey: string, cb: (name: string) => void): () => void {
	if (!browser) return () => {};
	const key = triggerKeyFor(deckKey);
	const onStorage = (e: StorageEvent) => {
		if (e.key !== key || !e.newValue) return;
		try {
			const { name } = JSON.parse(e.newValue) as { name: string };
			if (typeof name === 'string' && name) cb(name);
		} catch {
			// A malformed payload is ignored, never thrown.
		}
	};
	window.addEventListener('storage', onStorage);
	return () => window.removeEventListener('storage', onStorage);
}

// CONSOLE PRESENCE — a heartbeat, so an audience window can tell whether a ?present
// console is actually open (and thus already showing the notes) vs one that was
// closed. Same publish/subscribe + fresh `ts` shape as the relays above, but it is
// a LIVENESS beat, not a command: the console re-stamps it on an interval while it
// lives, and the audience judges staleness with consoleLiveCore (a missed beat goes
// stale rather than lying live forever). There is no farewell write on close — a
// force-quit would skip it — so absence-of-beats, not an event, is what marks it gone.
const consoleKeyFor = (deckKey: string) => `geekpresent:console:${deckKey}`;

/** Stamp THIS window's console as alive for `deckKey` (call on an interval while the
    ?present console is open). Best-effort; a no-op off-browser. */
export function publishConsoleAlive(deckKey: string): void {
	if (!browser) return;
	try {
		localStorage.setItem(consoleKeyFor(deckKey), JSON.stringify({ ts: Date.now() }));
	} catch {
		// best-effort
	}
}

/** The last console heartbeat ms for `deckKey`, or 0 if none/garbage. Read once on
    mount so the audience knows a console is already live before the first `storage`
    event (which only fires on the NEXT beat). */
export function loadConsoleBeat(deckKey: string): number {
	if (!browser) return 0;
	try {
		const raw = localStorage.getItem(consoleKeyFor(deckKey));
		const ts = raw ? (JSON.parse(raw) as { ts?: unknown }).ts : 0;
		return typeof ts === 'number' && Number.isFinite(ts) && ts > 0 ? ts : 0;
	} catch {
		return 0;
	}
}

/** Subscribe to console heartbeats for `deckKey`; `cb` gets each beat's ms. `storage`
    only fires cross-window, so a console never hears its own beat. Returns an
    unsubscribe; a no-op off-browser. */
export function subscribeConsoleAlive(deckKey: string, cb: (beatMs: number) => void): () => void {
	if (!browser) return () => {};
	const key = consoleKeyFor(deckKey);
	const onStorage = (e: StorageEvent) => {
		if (e.key !== key || !e.newValue) return;
		try {
			const ts = (JSON.parse(e.newValue) as { ts?: unknown }).ts;
			if (typeof ts === 'number' && Number.isFinite(ts) && ts > 0) cb(ts);
		} catch {
			// ignore malformed payloads
		}
	};
	window.addEventListener('storage', onStorage);
	return () => window.removeEventListener('storage', onStorage);
}

// NOTE: annotation ink has NO relay here, deliberately. It used to — a publishInk /
// subscribeInk pair sat exactly at this spot, mirroring the highlight channel. Persisting
// the ink made it redundant: `stores/annotation.inkBook` is a persisted(sync: true) store,
// so localStorage IS the channel, the `storage` event does the mirroring, and the presenter
// console can RESET the ink by writing to the same store. Two mechanisms for one job is one
// too many, and the relay was the one that could drift.

// Durable presenter timer — the elapsed clock must survive both Ctrl+R AND slide
// navigation (which pages the console with a full document load). Persisting the
// START time per deck makes the elapsed value reload-proof; only an explicit reset
// moves it.
const timerKeyFor = (deckKey: string) => `geekpresent:timerStart:${deckKey}`;

/** The persisted timer start for this deck, initialising it to "now" on first use. */
export function presenterTimerStart(deckKey: string): number {
	if (!browser) return 0;
	const stored = Number(localStorage.getItem(timerKeyFor(deckKey)));
	if (Number.isFinite(stored) && stored > 0) return stored;
	const now = Date.now();
	try { localStorage.setItem(timerKeyFor(deckKey), String(now)); } catch { /* best-effort */ }
	return now;
}

/** Set this deck's timer start (and persist), returning it. Defaults to "now" (a
    plain reset); pass an explicit ms epoch to SET the elapsed — e.g.
    `Date.now() - 300_000` makes the clock read 05:00 and count up from there. */
export function resetPresenterTimer(deckKey: string, startMs?: number): number {
	if (!browser) return 0;
	const start = startMs ?? Date.now();
	try { localStorage.setItem(timerKeyFor(deckKey), String(start)); } catch { /* best-effort */ }
	return start;
}

// Durable pause — when the elapsed clock is paused, the epoch at which it froze is
// stored (per deck), so a reload/navigation resumes still paused at the same value.
// null = running.
const pauseKeyFor = (deckKey: string) => `geekpresent:timerPaused:${deckKey}`;

/** The persisted pause epoch, or null if the timer is running. */
export function loadPresenterPause(deckKey: string): number | null {
	if (!browser) return null;
	const v = Number(localStorage.getItem(pauseKeyFor(deckKey)));
	return Number.isFinite(v) && v > 0 ? v : null;
}

/** Persist the pause epoch (or clear it with null to mark the timer running). */
export function savePresenterPause(deckKey: string, pausedAt: number | null): void {
	if (!browser) return;
	try {
		if (pausedAt == null) localStorage.removeItem(pauseKeyFor(deckKey));
		else localStorage.setItem(pauseKeyFor(deckKey), String(pausedAt));
	} catch { /* best-effort */ }
}

// Durable presenter split — the draggable divider between the previews and the
// notes panel (the --gp-split CSS var). A global UI preference (deck-agnostic),
// persisted so it survives reloads/navigation. Stored as a 0..1 fraction of the
// window width.
const SPLIT_KEY = 'geekpresent:presenterSplit';

/** The persisted split fraction (0..1), or null if unset/invalid. */
export function loadPresenterSplit(): number | null {
	if (!browser) return null;
	const v = Number(localStorage.getItem(SPLIT_KEY));
	return Number.isFinite(v) && v > 0 && v < 1 ? v : null;
}

/** Persist the split fraction (0..1). */
export function savePresenterSplit(fraction: number): void {
	if (!browser) return;
	try { localStorage.setItem(SPLIT_KEY, String(fraction)); } catch { /* best-effort */ }
}

// Per-line note check-off state — persisted per deck + slide, so ticks survive
// reload/navigation. Stored as a boolean[] (one per note line).
const checksKeyFor = (deckKey: string, slidePath: string) =>
	`geekpresent:checks:${deckKey}:${slidePath}`;

/** The saved check states for a slide's note lines (empty if none). */
export function loadChecks(deckKey: string, slidePath: string): boolean[] {
	if (!browser) return [];
	try {
		const raw = localStorage.getItem(checksKeyFor(deckKey, slidePath));
		const arr = raw ? JSON.parse(raw) : null;
		if (Array.isArray(arr)) return arr.map(Boolean);
	} catch { /* ignore */ }
	return [];
}

/** Persist a slide's check states; removes the key when nothing is checked. */
export function saveChecks(deckKey: string, slidePath: string, checks: boolean[]): void {
	if (!browser) return;
	try {
		if (checks.some(Boolean)) localStorage.setItem(checksKeyFor(deckKey, slidePath), JSON.stringify(checks));
		else localStorage.removeItem(checksKeyFor(deckKey, slidePath));
	} catch { /* best-effort */ }
}

/** Clear the checks for ONE slide (reset this page). */
export function clearSlideChecks(deckKey: string, slidePath: string): void {
	if (!browser) return;
	try { localStorage.removeItem(checksKeyFor(deckKey, slidePath)); } catch { /* best-effort */ }
}

/** Clear the checks for EVERY slide in a deck (start over). */
export function clearDeckChecks(deckKey: string): void {
	if (!browser) return;
	try {
		const prefix = `geekpresent:checks:${deckKey}:`;
		const doomed: string[] = [];
		for (let i = 0; i < localStorage.length; i++) {
			const k = localStorage.key(i);
			if (k && k.startsWith(prefix)) doomed.push(k);
		}
		doomed.forEach((k) => localStorage.removeItem(k));
	} catch { /* best-effort */ }
}

/** Open (or re-focus) the presenter console for this deck. Uses a per-deck window
    name so a second click focuses/reloads the existing console instead of spawning
    another. Must be called from a user gesture (a click) or a popup blocker may
    refuse — returns the Window (or null if blocked / off-browser). */
export function openPresenterWindow(currentHref: string, deckKey: string): Window | null {
	if (!browser) return null;
	const url = new URL(currentHref);
	url.searchParams.set('present', '');
	return window.open(url.toString(), `gp-presenter:${deckKey}`, 'popup,width=960,height=680');
}
