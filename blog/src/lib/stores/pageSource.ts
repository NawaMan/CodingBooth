import { derived, get, writable } from 'svelte/store';
import { canSave } from '$lib/stores/adjustMode';
import { loadPageSource } from '$lib/stores/sourceSave';
import { openSourceEditor } from '$lib/stores/sourceEditWindow';

// Page-source registry + deck-wide SOURCE / EDIT chrome.
//
// ## Why it used to "disappear" between slides
//
// The first design treated source as a *per-slide component*: a slide that wanted
// ☰ → SOURCE had to mount `<ViewSource source={…?raw} />`. The shell only showed
// the menu rows while something was *registered*. Leave a ViewSource slide for
// one without it (e.g. project-structure.html) and the rows vanished. That was
// never a good fit for chrome that *feels* deck-wide (OVERVIEW, CAPTURE, PRINT).
//
// ## Correct product shape
//
//   - SOURCE — view this slide's `+page.svelte`. Deck-wide whenever we can get
//     the bytes: vite dev (source-load endpoint) on every slide, or a mounted
//     ViewSource's `?raw` import (works in a static build too).
//   - EDIT   — type + SAVE. Deck-wide in vite dev only (needs a source tree).
//     A mounted ViewSource may still offer EDIT in a *built* demo so the control
//     can answer NOT ALLOWED on SAVE (same bargain as ADJUST SAVE).
//
// ViewSource is still useful as the *panel* and as the production SOURCE path;
// it is no longer the gate for "may the menu show the rows at all" in dev.
//
//   - pageSourceCanView  — show SOURCE
//   - pageSourceCanEdit  — show EDIT
//   - pageSourceAvailable — either (legacy name; prefer the two above)
//   - pageSourceOpen / deckSourceFallback / openPageSource(Edit)
//
// Identity registration (a Symbol per instance) is robust under the destroy/mount
// overlap of a client-side (View-Transition) slide change — the same bargain as
// localChrome's localNav / hostedAnim.

const owners = writable<Set<symbol>>(new Set());

/** Optional per-owner opener for the unscaled EDIT window. */
const editOpeners = new Map<symbol, () => void>();

/** True while at least one <ViewSource> / <SourceView> is mounted on this page. */
export const pageSourceHasOwner = derived(owners, (s) => s.size > 0);

/**
 * Show ☰ → SOURCE. True when we can actually open a panel:
 *   - a ViewSource is mounted (`?raw` bytes, works on a static host), or
 *   - vite dev (`canSave`) — load via `/__geekpresent/source-load` for any slide.
 */
export const pageSourceCanView = derived(
	[owners, canSave],
	([$owners, $canSave]) => $owners.size > 0 || $canSave
);

/**
 * Show ☰ → EDIT. True when:
 *   - vite dev (`canSave`) — deck-wide write path, or
 *   - a ViewSource registered an opener (demo slides that teach EDIT → NOT ALLOWED).
 */
export const pageSourceCanEdit = derived(
	[owners, canSave],
	([$owners, $canSave]) => $canSave || $owners.size > 0
);

/** @deprecated Use pageSourceCanView / pageSourceCanEdit. True if either menu row shows. */
export const pageSourceAvailable = derived(
	[pageSourceCanView, pageSourceCanEdit],
	([$v, $e]) => $v || $e
);

/** Whether the source panel (ViewSource CodeBox or deck fallback) is open. */
export const pageSourceOpen = writable(false);

/**
 * When SOURCE is opened without a mounted ViewSource, the deck shell fetches
 * the file and hosts a CodeBox from this buffer.
 */
export const deckSourceFallback = writable<{
	code: string;
	path: string;
	route: string;
} | null>(null);

/**
 * A slide's ViewSource/SourceView joins the registry on mount.
 * Pass `openEdit` so ☰ → EDIT (and the CodeBox EDIT button) can open the popup.
 */
export function registerPageSource(owner: symbol, openEdit?: () => void): void {
	owners.update((s) => {
		const next = new Set(s);
		next.add(owner);
		return next;
	});
	if (openEdit) editOpeners.set(owner, openEdit);
	// Owner will show its own panel — drop any deck fallback.
	deckSourceFallback.set(null);
}

/** Leaves the registry on destroy. Closes the panel when nobody is left offering
    a ViewSource panel (deck fallback is independent). */
export function unregisterPageSource(owner: symbol): void {
	editOpeners.delete(owner);
	owners.update((s) => {
		if (!s.has(owner)) return s;
		const next = new Set(s);
		next.delete(owner);
		return next;
	});
	if (get(owners).size === 0 && !get(deckSourceFallback)) {
		pageSourceOpen.set(false);
	}
}

function currentRoute(): string {
	if (typeof location === 'undefined') return '';
	return location.pathname;
}

/** Open the in-slide SOURCE panel (ViewSource) or the deck-level fallback. */
export async function openPageSource(): Promise<void> {
	if (get(owners).size > 0) {
		deckSourceFallback.set(null);
		pageSourceOpen.set(true);
		return;
	}
	// Dev fallback: load from disk and let SlideDeck host a CodeBox.
	if (!get(canSave)) return;
	const route = currentRoute();
	const loaded = await loadPageSource(route);
	if (!loaded.ok || typeof loaded.content !== 'string') {
		console.warn('[SOURCE]', loaded.error ?? 'could not load page source');
		return;
	}
	deckSourceFallback.set({
		code: loaded.content,
		path: loaded.file ?? route,
		route
	});
	pageSourceOpen.set(true);
}

/**
 * Open the unscaled source-edit popup.
 * Prefers a mounted ViewSource opener; otherwise loads via the dev endpoint.
 */
export async function openPageSourceEdit(): Promise<void> {
	// Prefer the most recently registered opener (SPA: arriving slide mounts after leaving).
	const openers = [...editOpeners.values()];
	const open = openers[openers.length - 1];
	if (open) {
		open();
		return;
	}

	if (!get(canSave)) {
		console.warn('[EDIT] no ViewSource on this slide and SAVE is not available');
		return;
	}

	const route = currentRoute();
	const loaded = await loadPageSource(route);
	if (!loaded.ok || typeof loaded.content !== 'string') {
		console.warn('[EDIT]', loaded.error ?? 'could not load page source');
		return;
	}

	const win = openSourceEditor({
		route,
		path: loaded.file ?? '',
		source: loaded.content,
		language: 'html',
		canSave: true
	});
	if (win) {
		closePageSource();
	} else {
		console.warn(
			'[EDIT] popup blocked — allow popups for this origin to edit source in a separate window'
		);
	}
}

/** Close the SOURCE panel and clear any deck fallback buffer. */
export function closePageSource(): void {
	pageSourceOpen.set(false);
	deckSourceFallback.set(null);
}
