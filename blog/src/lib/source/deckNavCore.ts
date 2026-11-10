// The EDIT window's FIRST / PREV / NEXT / LAST (pure).
//
// The window pages through a deck's slides the way →/Space do: the visible
// slides of its pages.ts, appendices (`hidden`) skipped. "Where am I" is read
// from the active tab when it is a slide's +page.svelte, so clicking a slide's
// tab moves the counter too; otherwise from the slide EDIT was opened on.

export interface DeckSlide {
	path: string;
	title: string;
}

export interface EditDeck {
	/** Folder under src/routes (may hold `(group)` segments). */
	fsPath: string;
	/** URL path, no leading slash, groups stripped. */
	urlPath: string;
	/** The linear order: visible slides only. */
	slides: DeckSlide[];
}

export interface DeckPosition {
	deck: EditDeck;
	index: number;
}

export interface SlideTarget {
	file: string;
	route: string;
	title: string;
	index: number;
}

export type NavKind = 'first' | 'prev' | 'next' | 'last';

/** The project file of slide `i`, e.g. `src/routes/slides/title.html/+page.svelte`. */
export function slideFile(deck: EditDeck, i: number): string {
	return `src/routes/${deck.fsPath}/${deck.slides[i].path}/+page.svelte`;
}

/** The site path of slide `i`, e.g. `/slides/title.html` (no base). */
export function slideRoute(deck: EditDeck, i: number): string {
	return `/${deck.urlPath}/${deck.slides[i].path}`;
}

/** The deck slide a project file is, or null (a component, an appendix, a $lib file). */
export function positionOfFile(
	decks: readonly EditDeck[],
	file: string | null
): DeckPosition | null {
	if (!file) return null;
	for (const deck of decks) {
		for (let i = 0; i < deck.slides.length; i++) {
			if (slideFile(deck, i) === file) return { deck, index: i };
		}
	}
	return null;
}

/** The deck slide a site path is (base already stripped; a trailing slash or
    query is tolerated), or null. */
export function positionOfRoute(
	decks: readonly EditDeck[],
	route: string | null
): DeckPosition | null {
	if (!route) return null;
	const clean = route.replace(/[?#].*$/, '').replace(/\/+$/, '');
	for (const deck of decks) {
		for (let i = 0; i < deck.slides.length; i++) {
			if (slideRoute(deck, i) === clean) return { deck, index: i };
		}
	}
	return null;
}

/** Where a button goes from `pos`, or null when it has nowhere to go (FIRST on
    the first slide, NEXT on the last…). */
export function navTarget(pos: DeckPosition | null, kind: NavKind): SlideTarget | null {
	if (!pos) return null;
	const n = pos.deck.slides.length;
	const i = pos.index;
	let to: number;
	switch (kind) {
		case 'first':
			to = 0;
			break;
		case 'prev':
			to = i - 1;
			break;
		case 'next':
			to = i + 1;
			break;
		case 'last':
			to = n - 1;
			break;
	}
	if (to < 0 || to >= n || to === i) return null;
	return {
		file: slideFile(pos.deck, to),
		route: slideRoute(pos.deck, to),
		title: pos.deck.slides[to].title,
		index: to
	};
}

/** Strip the site's base path from a pathname. */
export function stripBase(pathname: string, base: string): string {
	if (base && (pathname === base || pathname.startsWith(base + '/'))) {
		return pathname.slice(base.length) || '/';
	}
	return pathname;
}
