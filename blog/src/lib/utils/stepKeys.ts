// What a Space press means on a slide — the one place that decides.
//
// Space is the "advance" key: it steps through a <Steps> build if one is running,
// and otherwise pages the deck. Two separate window listeners act on it (Steps
// reveals/peels; NavigationBar pages), so the decision is factored out here and
// BOTH ask the same question against the same build state. That makes them
// order-independent: whichever listener runs first, each one only acts on the
// intent that belongs to it, and neither can page a slide out from under a build.
//
// The arrow keys are deliberately not handled here — →/← always page, never step.
// Neither do the other paging keys (pageKeyIntent, at the bottom): they never step.

/** The build state a Space press is judged against (null = no build on this slide). */
export interface BuildState {
	/** Another Fragment left to reveal? */
	hasNext: boolean;
	/** A revealed Fragment left to peel back off? */
	hasPrev: boolean;
}

export type SpaceIntent =
	/** Reveal the next Fragment (Steps acts). */
	| 'reveal'
	/** Peel the last Fragment back off (Steps acts). */
	| 'peel'
	/** Build spent (or absent) → page forward (NavigationBar acts). */
	| 'page-next'
	/** Build not started (or absent) → page back (NavigationBar acts). */
	| 'page-prev'
	/** Not ours: not Space, already handled, or a focused control owns it. */
	| 'ignore';

/** True for the space bar, however the browser reports it. */
export function isSpaceKey(e: KeyboardEvent): boolean {
	return e.code === 'Space' || e.key === ' ';
}

/** Focused controls keep Space's native meaning (activate a button, type a space). */
export function isInteractiveTarget(t: EventTarget | null): boolean {
	const el = t as HTMLElement | null;
	if (!el) return false;
	if (el.isContentEditable) return true;
	return /^(INPUT|TEXTAREA|SELECT|BUTTON|A)$/.test(el.tagName);
}

/**
 * Decide what a keydown should do: step the build, or page the deck.
 *
 * Space advances (reveal → else page-next); Shift+Space reverses (peel → else
 * page-prev). So a build simply inserts sub-steps into the deck's forward march.
 */
export function spaceIntent(e: KeyboardEvent, build: BuildState | null): SpaceIntent {
	if (e.defaultPrevented || !isSpaceKey(e) || isInteractiveTarget(e.target)) return 'ignore';
	if (e.shiftKey) return build?.hasPrev ? 'peel' : 'page-prev';
	return build?.hasNext ? 'reveal' : 'page-next';
}

/** What a paging key other than Space and ←/→ means: jump to an end, or step a slide. */
export type PageKeyIntent = 'first' | 'last' | 'next' | 'prev' | 'ignore';

/**
 * The deck's other paging keys — the ones that never touch a build.
 *
 *   Home / End           FIRST / LAST   (on a Mac laptop: Fn+← / Fn+→ send these)
 *   Cmd+↑ / Cmd+↓        FIRST / LAST   (the Mac's own "to the top / bottom")
 *   PageUp / PageDown    PREV / NEXT    (what a presentation clicker sends)
 *
 * Any other modifier is a browser or OS chord and is left alone, as is a key a
 * focused control already claimed (`defaultPrevented` — the AnimationBar rail's
 * own Home/End). Whether the TARGET owns the key is the caller's call, as it is for
 * the arrows: the deck's pager and the presenter console guard it differently.
 */
export function pageKeyIntent(e: KeyboardEvent): PageKeyIntent {
	if (!e || e.defaultPrevented) return 'ignore';
	if (e.altKey || e.ctrlKey || e.shiftKey) return 'ignore';
	if (e.metaKey) {
		if (e.key === 'ArrowUp') return 'first';
		if (e.key === 'ArrowDown') return 'last';
		return 'ignore';
	}
	switch (e.key) {
		case 'Home':     return 'first';
		case 'End':      return 'last';
		case 'PageUp':   return 'prev';
		case 'PageDown': return 'next';
		default:         return 'ignore';
	}
}
