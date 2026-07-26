import { writable, derived, get } from 'svelte/store';
import { browser } from '$app/environment';
import { persisted } from './persisted';
import { booleanCodec } from '$lib/utils/stateCore';
import { readSticky, readAnnotateParam, resolveCanAnnotate } from '$lib/annotate/annotateAccessCore';
import {
	barPosCodec,
	inkBookCodec,
	isStaleInk,
	INK_STALE_AFTER_MS,
	type AnnotateMode,
	type AnnotateTool,
	type BarPos,
	type InkBook,
	type SlideInk,
	type Stroke
} from '$lib/annotate/annotateCore';

// ANNOTATE mode — a SPEAKER aid, not an authoring one. When on, a canvas-spanning ink
// surface arms itself and the speaker draws freehand on the live slide: circle the term,
// underline the line of code, cross out the wrong branch. <Spotlight> can already ring a
// Block, but only one the AUTHOR anticipated and named; annotation is for the thing the
// speaker decides to point at while answering a question.
//
//   - annotationMode: is the pen currently ARMED? Persisted; per-window (sync: false).
//   - canAnnotate:    is the ANNOTATE control OFFERED here? dev > sticky ?annotate > the
//     deck's `annotate` prop > off. Precedence in annotate/annotateAccessCore — one tier
//     shorter than ADJUST's, because a speaker tool takes no instruction from the slide it
//     happens to be standing on.
//   - inkBook:        the ink itself, per slide, PERSISTED.
//
// Offered is not active: the mode still starts OFF, so a deck that ships the pen still
// opens as an ordinary slide.

const MODE_KEY = 'annotationMode';
const CAN_KEY = 'canAnnotate';
const INK_KEY = 'geekpresent:ink';

/** What the DECK declares (SlideDeck's `annotate` prop). */
let deckWide = false;

function sticky() {
	return browser ? readSticky(localStorage.getItem(CAN_KEY)) : null;
}

function recompute(): void {
	canAnnotate.set(resolveCanAnnotate(import.meta.env.DEV, sticky(), deckWide));
}

/** Is the pen armed? `booleanCodec` and not `jsonCodec<boolean>` for the reason ADJUST
    uses it: a corrupt key must read as OFF, and JSON would hand back a truthy object for
    `{"x":1}` — arming a pen over someone's slide that nobody asked for.

    `sync: false` keeps each window's mode its own: the speaker arming the pen here must
    not arm it on the audience's screen, where a stray click would then draw. What crosses
    windows is the INK, not the mode. */
export const annotationMode = persisted<boolean>(MODE_KEY, false, {
	codec: booleanCodec(),
	sync: false
});

/** DERIVED (dev + the sticky ?annotate flag + the deck's prop). Reads CAN_KEY but never
    mirrors itself to it, so — like canAdjust — it stays a hand-rolled writable. */
export const canAnnotate = writable<boolean>(
	resolveCanAnnotate(import.meta.env.DEV, sticky(), deckWide)
);

/** THE INK — every slide's strokes, keyed by full pathname, remembered across reloads.
    Ink now OUTLIVES the slide, which is a reversal of the original design (it used to be
    a laser-pointer trail that died on navigation). Three consequences, all of them the
    point:
      - You can mark up a deck during prep and still have it during the talk.
      - The book can therefore go STALE, so `staleInk` below offers to clear it.
      - There must be a way out: resetSlideInk / resetAllInk, in the bar AND in the
        presenter console.

    `sync: true`, and that is load-bearing: localStorage IS the cross-window channel.
    Both deck windows are the same origin, so the audience window's copy of this store
    hears the speaker's every stroke through the `storage` event — no bespoke relay, and
    the presenter console (which has no canvas of its own) can RESET by writing here and
    have both windows follow. It is also why the console's next-slide <iframe> is harmless
    now: ink is keyed BY SLIDE, so a preview of a different slide shows that slide's ink,
    which is exactly right.

    SSR: `persisted` degrades to a plain writable holding `{}` on the server (no window, no
    listener), so a prerendered page ships no ink no matter what is in anyone's browser. */
export const inkBook = persisted<InkBook>(INK_KEY, {}, { codec: inkBookCodec(), sync: true });

/** Which slide's ink we are looking at — its full pathname. Set by SlideDeck on every
    slide change. Not persisted: it is a pointer INTO the book, not part of it. */
export const inkPath = writable<string>('');

/** The current slide's strokes. Derived, so every window that hears a `storage` event
    re-renders without anyone wiring an update. */
export const strokes = derived([inkBook, inkPath], ([$book, $path]) => $book[$path]?.strokes ?? []);

/** The current slide's ink entry, timestamp and all (the stale check reads this). */
export const slideInk = derived([inkBook, inkPath], ([$book, $path]) => $book[$path]);

/** Which bar mode is selected — a DRAW tool, or the ERASER (which removes strokes rather
    than adding one). Not persisted: a pen is the right thing to wake up holding, and a
    speaker who left the highlighter (or, worse, the eraser) selected three talks ago would
    be surprised by what the next gesture does. */
export const annotateTool = writable<AnnotateMode>('pen');

/** The colour the next stroke uses, per tool. `null` means "whatever the theme says" —
    the `--annot-*` role token — which is the default, so ink follows a re-theme instead
    of freezing today's hex into every mark. Only an explicit pick overrides it. */
export const annotateColor = writable<Record<AnnotateTool, string | null>>({
	pen: null,
	line: null,
	arrow: null,
	rectangle: null,
	highlighter: null,
	text: null
});

/** Where the speaker parked the pen's bar, in canvas px — `null` until they drag it, so an
    un-dragged bar stores no coordinates and a deck is free to move the default later.

    Persisted, because a bar you have to re-park on every slide is worse than one that never
    moved. `sync: false`: this is one speaker's idea of where the tools should sit, not a
    property of the deck — the audience window has no bar to move, and the presenter's choice
    should not shove anything on theirs.

    It survives paging ONLY while the pen stays armed — see the reset just below. Close the
    pen and it forgets: the next time it opens, here or on another slide, it starts fresh at
    its resting spot, rather than a position chosen for a slide the speaker has left behind. */
export const barPos = persisted<BarPos>('annotationBarPos', null, {
	codec: barPosCodec(),
	sync: false
});

/** Closing the pen resets where its bar was parked. A bar dragged out of the way stays put
    for as long as the speaker keeps paging with the pen ARMED — `annotationMode` is itself
    persisted, so that survives the full-page reload a slide change usually is — but the
    moment it goes false, the position goes with it.

    Only a LIVE transition counts. `wasArmed` starts `false` on every fresh page load, so the
    very first callback below — which may well report `true`, read back from a PRIOR session
    that left the pen armed — can never look like "just closed": there is nothing to compare
    it against yet. Only an actual true→false seen WITHIN this page's lifetime (the speaker
    clicking ANNOTATE off, or `?annotate=off`) resets the bar. */
let wasArmed = false;
annotationMode.subscribe((armed) => {
	if (wasArmed && !armed) barPos.set(null);
	wasArmed = armed;
});

/** Has the speaker dismissed the stale-ink prompt for THIS visit? Not persisted, and
    reset on every slide change: dismissing it is "not now", not "never again". */
export const staleDismissed = writable<boolean>(false);

/** How old ink must be before we mention it. Overridable per deck (SlideDeck's
    `inkStaleAfter`, in hours) — a daily-standup deck and a conference talk have very
    different ideas of "old". */
export const inkStaleAfterMs = writable<number>(INK_STALE_AFTER_MS);

/** Should we prompt about this slide's ink right now? */
export const staleInk = derived(
	[slideInk, staleDismissed, inkStaleAfterMs],
	([$ink, $dismissed, $max]) => {
		if ($dismissed || !browser) return null;
		// Date.now() is read HERE rather than in the core so the core stays pure and
		// directly testable against a supplied clock (see isStaleInk).
		return isStaleInk($ink, Date.now(), $max) ? $ink : null;
	}
);

/** Point the ink at a slide, and forget any "not now" the speaker said on the last one. */
export function setInkPath(path: string): void {
	if (get(inkPath) === path) return;
	inkPath.set(path || '');
	staleDismissed.set(false);
}

/** Write the current slide's strokes back into the book, stamped with the time.

    An EMPTY list deletes the slide's entry rather than storing `[]` — so the book holds
    only slides that actually carry ink, "has this slide got ink?" stays answerable by
    looking, and undoing your last stroke leaves no trace behind to go stale. */
function writeSlide(next: Stroke[]): Stroke[] {
	const path = get(inkPath);
	if (!path) return next;
	inkBook.update((book) => {
		const copy = { ...book };
		if (next.length === 0) delete copy[path];
		else copy[path] = { strokes: next, ts: Date.now() };
		return copy;
	});
	staleDismissed.set(true); // ink you just touched is yours; don't nag about it
	return next;
}

/** Append a finished stroke. */
export function addStroke(stroke: Stroke): Stroke[] {
	return writeSlide([...get(strokes), stroke]);
}

/** Patch one mark in place, by id — how the TEXT tool re-commits an edited label and how a
    drag drops it at a new anchor, without disturbing the rest of the slide's ink. A no-op
    (no write, no timestamp bump) if the id is not on this slide, so a stale edit target does
    not stamp the book. */
export function updateStroke(id: string, patch: Partial<Stroke>): Stroke[] {
	const current = get(strokes);
	let changed = false;
	const next = current.map((s) => {
		if (s.id !== id) return s;
		changed = true;
		return { ...s, ...patch };
	});
	return changed ? writeSlide(next) : current;
}

/** Take back the most recent stroke. A stroke is the unit the speaker drew, so it is the
    unit they expect back — which is the whole eraser story. */
export function undoStroke(): Stroke[] {
	return writeSlide(get(strokes).slice(0, -1));
}

/** The ERASER's delete: drop whole strokes by id. Ids not on this slide are ignored, and a
    set that matches nothing is a no-op (no write, no timestamp bump). Erasing every stroke
    leaves NO entry behind, exactly like RESET — writeSlide deletes an emptied slide.

    There is deliberately no undo-restore: like `undoStroke`, this rewrites the slide's list
    rather than pushing onto a history, so an erased stroke is gone. A real undo of an erase
    would need a history stack this overlay does not keep. */
export function eraseStrokes(ids: Iterable<string>): Stroke[] {
	const drop = new Set(ids);
	if (drop.size === 0) return get(strokes);
	const current = get(strokes);
	const remaining = current.filter((s) => !drop.has(s.id));
	if (remaining.length === current.length) return current; // nothing matched — leave it be
	return writeSlide(remaining);
}

/** Clear THIS slide's ink. */
export function resetSlideInk(): void {
	writeSlide([]);
}

/** Clear the ink on EVERY slide of every deck in this origin — "start over", the twin of
    the presenter console's existing "Start over (whole deck)" for note ticks. */
export function resetAllInk(): void {
	inkBook.set({});
	staleDismissed.set(false);
}

/** Dismiss the stale-ink prompt for this visit ("keep it"). */
export function dismissStale(): void {
	staleDismissed.set(true);
}

export type { SlideInk };

/** Declare whether the DECK offers the ANNOTATE control. Unlike setAdjustOffered this is
    NOT re-called per slide — the flag is deck-wide, so paging cannot take the pen out of
    the speaker's hand mid-answer. */
export function setAnnotateOffered(on: boolean): void {
	deckWide = on === true;
	recompute();
}

/** Opt in/out from a slide URL's `?annotate` flag, then remember it across navigations
    (the nav links drop the flag, so we persist it). `?annotate=off` also disarms a pen
    left on. A URL with no flag changes nothing — it just re-resolves. */
export function applyAnnotateParam(url: URL): void {
	if (!browser) return;
	const choice = readAnnotateParam(url.searchParams);
	if (choice !== null) {
		localStorage.setItem(CAN_KEY, String(choice));
		if (!choice) annotationMode.set(false);
	}
	recompute();
}
