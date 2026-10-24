// Shared slide navigation — the one place that knows HOW a deck pages.
//
// Lifted out of NavigationBar so it can be reused by anything that drives paging:
// the nav bar (clicks / arrow keys), the presenter console's buttons, and the
// cross-window follower in SlideDeck. A *followed* navigation then animates
// exactly like a clicked one, because both go through this function.
//
// Kept OUT of utils/navigate.ts on purpose: that module is pure path math
// (getPageNavigation / documentTitle) and is imported by server/prerender code
// (seo/routes.ts). This file pulls in $app/navigation, so it stays separate.
import { browser } from '$app/environment';
import { goto } from '$app/navigation';
import { ARRIVAL_KEY, arrivalMark, arrivesAtEnd } from './arrivalCore';
import { reportGoto, reportLeaving } from '$lib/record/recordBus';

export type NavDirection = 'forward' | 'back';

export interface NavigateOptions {
	/** This deck's paging strategy (getViewTransitions()). false → a plain
	    full-page load; true → client-side goto wrapped in the View Transitions
	    API (falling back to goto, then a full load). */
	viewTransitions?: boolean;
	/** The leaving slide's transition name for this direction (data-vt-kind).
	    Only used when viewTransitions is on and the browser supports it. */
	kind?: string;
	/** Direction, for the data-vt attribute the view-transition keyframes read. */
	direction?: NavDirection;
	/** Land on the target with its <Steps> build already spent — what PREV wants,
	    so paging back shows a slide as it was left (see arrivalCore.ts). */
	arriveAtEnd?: boolean;
}

/** Leave the arrive-at-end mark for `href`. Storage can throw (private mode, a
    full quota); a lost mark only means the build starts at step 0 as before. */
function markArrivalAtEnd(href: string): void {
	try {
		const mark = arrivalMark(href, window.location.href, Date.now());
		if (mark) sessionStorage.setItem(ARRIVAL_KEY, mark);
	} catch {
		/* no storage → no mark */
	}
}

/** Was this slide reached by PREV? Read by <Steps> as it starts; the mark stays
    until `clearArrival`, so every Steps on the slide sees the same answer. */
export function readArrivalAtEnd(): boolean {
	if (!browser) return false;
	try {
		return arrivesAtEnd(sessionStorage.getItem(ARRIVAL_KEY), window.location.pathname, Date.now());
	} catch {
		return false;
	}
}

/** Drop the mark, once the slide that wanted it has mounted. */
export function clearArrival(): void {
	if (!browser) return;
	try {
		sessionStorage.removeItem(ARRIVAL_KEY);
	} catch {
		/* nothing to clear */
	}
}

/** Navigate to `href`, animating when this deck uses view transitions and the
    browser supports them. Falls back, in order, to a plain client-side goto (no
    reload/blink), then to a full-page load. */
export function navigate(href: string, opts: NavigateOptions = {}): void {
	if (!href) return;
	const { viewTransitions = false, kind = 'slide', direction = 'forward', arriveAtEnd = false } = opts;
	if (browser) {
		if (arriveAtEnd) markArrivalAtEnd(href);
		else clearArrival();
		// A VOD recording hears every page turn here, whatever caused it (no-op otherwise).
		reportGoto(href, direction === 'back', arriveAtEnd);
	}

	if (!viewTransitions) {
		if (browser) {
			reportLeaving(); // a full page load: the Recorder holds the picture until it lands
			window.location.href = href;
		}
		return;
	}
	// @ts-ignore — startViewTransition is not in older lib.dom typings.
	if (!browser || typeof document.startViewTransition !== 'function') {
		goto(href);
		return;
	}

	// These attributes key the keyframes in a deck's view-transitions.css:
	// data-vt-kind picks the effect (the leaving slide's own), data-vt its
	// direction. Both are cleared once the transition settles.
	const root = document.documentElement;
	root.dataset.vtKind = kind;
	root.dataset.vt = direction;
	// @ts-ignore
	const transition = document.startViewTransition(() => goto(href));
	transition.finished.finally(() => {
		delete root.dataset.vt;
		delete root.dataset.vtKind;
	});
}

/** Run `then` once the view transition in progress (if any) has finished — at
    once when there is none. navigate() keeps data-vt-kind on <html> for exactly
    the length of a transition, so its removal is the signal. A slide mounted by
    a transition mounts while the attribute is still set. Returns a cancel, for
    a component that unmounts first. */
export function afterViewTransition(then: () => void): () => void {
	if (!browser) return () => {};
	const root = document.documentElement;
	if (!root.dataset.vtKind) {
		then();
		return () => {};
	}
	const watch = new MutationObserver(() => {
		if (root.dataset.vtKind) return;
		watch.disconnect();
		then();
	});
	watch.observe(root, { attributes: true, attributeFilter: ['data-vt-kind'] });
	return () => watch.disconnect();
}
