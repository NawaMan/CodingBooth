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
}

/** Navigate to `href`, animating when this deck uses view transitions and the
    browser supports them. Falls back, in order, to a plain client-side goto (no
    reload/blink), then to a full-page load. */
export function navigate(href: string, opts: NavigateOptions = {}): void {
	if (!href) return;
	const { viewTransitions = false, kind = 'slide', direction = 'forward' } = opts;

	if (!viewTransitions) {
		if (browser) window.location.href = href;
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
