import { writable } from 'svelte/store';

// Is the all-slides OVERVIEW grid open? A store, not OverviewPage-local state, because
// several things open it and they must agree: the `o` key (owned by OverviewPage itself),
// the OVERVIEW item in ANNOTATE's tool flyout (audience window, owned by SlideDeck), and
// the OVERVIEW button in the presenter console's bar (owned by PresenterView). One boolean,
// set from any side, read by the grid.
//
// Not persisted: an overview that was open when you left should not reopen itself on the next
// slide load. It is a momentary "where do I want to go" gesture, closed the instant you pick.
export const overviewOpen = writable(false);
