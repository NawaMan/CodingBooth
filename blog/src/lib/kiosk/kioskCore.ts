/*
  Kiosk / auto-advance — pure decision layer.

  A booth screen, lobby loop, or unattended demo: dwell on steps, then the page,
  then advance (Space semantics: reveal a build first, page only when spent).
  Geometry and timing stay total and NaN-safe so a bad override cannot freeze the
  runner on `NaN` ms or crash the deck.

  Precedence for offering the control (same shape as ANNOTATE / CAPTURE):

    vite dev > sticky ?kiosk / ?kiosk=off > SlideDeck `kiosk` prop > off

  Sticky only decides whether the menu is offered. *Running* is a separate
  session flag (see stores/kiosk): ?kiosk starts it; Stop / ?kiosk=off ends it.
*/

import { readSticky, type Choice } from '$lib/adjust/adjustAccessCore';

export { readSticky };
export type { Choice };

/** Default dwell between in-slide build steps (Space-style reveals). */
export const DEFAULT_STEP_MS = 2000;
/** Default dwell on a finished slide before paging. */
export const DEFAULT_PAGE_MS = 6000;
/** Words-per-minute used when speaker notes drive page dwell. */
export const DEFAULT_WPM = 150;
/** Floor / ceiling for authored or dialog paces (ms). */
export const MIN_PACE_MS = 250;
export const MAX_PACE_MS = 120_000;

/** Interpret a slide URL's `?kiosk` flag.

    `?kiosk`, `?kiosk=on`, `?kiosk=1` enable; `?kiosk=off`, `?kiosk=false`,
    `?kiosk=0` disable. Absent → `null` (do not revoke a sticky offer). */
export function readKioskParam(search: URLSearchParams | null | undefined): Choice {
	if (!search || !search.has('kiosk')) return null;
	const v = (search.get('kiosk') ?? '').trim().toLowerCase();
	return v !== 'off' && v !== 'false' && v !== '0';
}

/** Is the Kiosk control offered here? (Offered ≠ running.) */
export function resolveCanKiosk(dev: boolean, sticky: Choice, deckWide: boolean): boolean {
	if (dev === true) return true;
	if (sticky !== null) return sticky;
	return deckWide === true;
}

/** Coerce a pace to a finite ms in [MIN, MAX], else `fallback`. */
export function clampPaceMs(value: unknown, fallback: number): number {
	const n = typeof value === 'number' ? value : Number(value);
	if (!Number.isFinite(n)) return clampPaceMs(fallback, DEFAULT_PAGE_MS);
	const base = Number.isFinite(fallback) ? fallback : DEFAULT_PAGE_MS;
	return Math.min(MAX_PACE_MS, Math.max(MIN_PACE_MS, Math.round(n > 0 ? n : base)));
}

/** Count words in free text (speaker notes). Empty / junk → 0. */
export function wordsIn(text: string | null | undefined): number {
	if (text == null) return 0;
	const s = String(text).trim();
	if (!s) return 0;
	return s.split(/\s+/).filter(Boolean).length;
}

/** Estimated speaking time for note text at `wpm` (ms). 0 words → 0. */
export function noteDwellMs(
	text: string | null | undefined,
	wpm: number = DEFAULT_WPM
): number {
	const words = wordsIn(text);
	if (words <= 0) return 0;
	const rate = Number.isFinite(wpm) && wpm > 0 ? wpm : DEFAULT_WPM;
	// minutes → ms; at least one tick so a single word still holds briefly
	return Math.max(MIN_PACE_MS, Math.round((words / rate) * 60_000));
}

/** Effective page dwell when notes are *not* stepped one-by-one (legacy / no items). */
export function pageDwellMs(opts: {
	pageMs: number;
	useNotes: boolean;
	noteText?: string | null;
	wpm?: number;
}): number {
	const floor = clampPaceMs(opts.pageMs, DEFAULT_PAGE_MS);
	if (!opts.useNotes) return floor;
	const fromNotes = noteDwellMs(opts.noteText, opts.wpm ?? DEFAULT_WPM);
	return Math.max(floor, fromNotes);
}

/**
 * Dwell for one note item: at least the step pace, longer if the line needs a
 * ~wpm read (so a long bullet is not blinked away at 2s).
 */
export function noteItemDwellMs(
	text: string | null | undefined,
	stepMs: number,
	wpm: number = DEFAULT_WPM
): number {
	const floor = clampPaceMs(stepMs, DEFAULT_STEP_MS);
	return Math.max(floor, noteDwellMs(text, wpm));
}

/** What the auto-advance runner should do right now. */
export type KioskAction = 'wait' | 'reveal' | 'note' | 'page';

/**
 * Decide the next kiosk action.
 *
 * 1. Finite slide animations still running → wait.
 * 2. Media (e.g. Video) still in a playthrough → wait (same gate; runner labels it).
 * 3. A build still has a step (`activeSteps.hasNext`) → reveal (Space).
 * 4. Speaker notes still have an item to show → note (one line at a time).
 * 5. Otherwise → page (or loop to first — the runner picks the href).
 *
 * Media sits *above* reveal so a full-bleed video is watched to its end rather
 * than seeked chapter-to-chapter on the step clock.
 */
export function kioskAction(state: {
	animBusy: boolean;
	/** True while a Video (or similar) is holding for its natural runtime. */
	mediaBusy?: boolean;
	hasNextStep: boolean;
	/** True while useNotes and the current note index is still within items. */
	hasNoteItem?: boolean;
}): KioskAction {
	if (state.animBusy === true) return 'wait';
	if (state.mediaBusy === true) return 'wait';
	if (state.hasNextStep === true) return 'reveal';
	if (state.hasNoteItem === true) return 'note';
	return 'page';
}

/** Normalize one note-line's text. */
export function normalizeNoteLine(text: string | null | undefined): string {
	if (text == null) return '';
	return String(text).replace(/\s+/g, ' ').trim();
}

/**
 * Split a `.note` element into ordered items (direct element children — the same
 * "lines" the presenter checklist uses). Empty children dropped. If there are no
 * element children with text, the whole note is one item (when non-empty).
 */
export function noteItemsFrom(noteEl: Element | null | undefined): string[] {
	if (!noteEl) return [];
	const kids = Array.from(noteEl.children)
		.filter((c): c is HTMLElement => c instanceof HTMLElement)
		.map((el) => normalizeNoteLine(el.textContent))
		.filter((t) => t.length > 0);
	if (kids.length > 0) return kids;
	const whole = normalizeNoteLine(noteEl.textContent);
	return whole ? [whole] : [];
}

/** Seconds ↔ ms helpers for the setup dialog (display in whole or .1 s). */
export function msToSeconds(ms: number): number {
	const n = clampPaceMs(ms, DEFAULT_PAGE_MS);
	return Math.round(n / 100) / 10; // one decimal
}

export function secondsToMs(sec: unknown, fallbackMs: number): number {
	const n = typeof sec === 'number' ? sec : Number(sec);
	if (!Number.isFinite(n) || n <= 0) return clampPaceMs(fallbackMs, DEFAULT_PAGE_MS);
	return clampPaceMs(n * 1000, fallbackMs);
}

/** Read speaker-note text from a slide root (`.note` under the content tree). */
export function noteTextFrom(root: ParentNode | null | undefined): string {
	if (!root || typeof (root as Element).querySelector !== 'function') return '';
	const el = (root as Element).querySelector?.('.note');
	if (!el) return '';
	return normalizeNoteLine(el.textContent);
}

/** Note items from a slide root (delegates to `noteItemsFrom` on `.note`). */
export function noteItemsFromRoot(root: ParentNode | null | undefined): string[] {
	if (!root || typeof (root as Element).querySelector !== 'function') return [];
	const el = (root as Element).querySelector?.('.note');
	return noteItemsFrom(el ?? null);
}

/** 1-based position string "2 / 5"; empty items → "". */
export function noteProgressLabel(index0: number, total: number): string {
	const t = Number(total);
	const i = Number(index0);
	if (!Number.isFinite(t) || t <= 0) return '';
	if (!Number.isFinite(i) || i < 0) return `1 / ${Math.round(t)}`;
	const pos = Math.min(Math.round(t), Math.max(1, Math.floor(i) + 1));
	return `${pos} / ${Math.round(t)}`;
}

/** Progress 0..1 for the indicator ring (elapsed / dwell). Total ≤ 0 → 0. */
export function dwellProgress(elapsedMs: number, totalMs: number): number {
	const total = Number(totalMs);
	const elapsed = Number(elapsedMs);
	if (!Number.isFinite(total) || total <= 0) return 0;
	if (!Number.isFinite(elapsed) || elapsed <= 0) return 0;
	return Math.max(0, Math.min(1, elapsed / total));
}
