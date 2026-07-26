export interface Page {
    path: string;
    /** The slide's name. Drives the Table of Contents and nav labels, AND the
        page segment of the browser-tab <title> (composed with the deck name —
        see documentTitle). So a page sets its tab title the same way it sets its
        favicon: from its pages.ts entry. */
    title: string;
    /** Optional page-level favicon (import a colocated asset so Vite bundles it).
        Overrides the presentation/site favicon for just this slide; emitted by the
        deck shell's <svelte:head>. See SlideDeck.svelte / slides/+layout.svelte. */
    favicon?: string;
    /** Optional page-level SEO description. Falls back to the deck's description
        (the `description` prop on SlideDeck) when omitted. */
    description?: string;
    /** Optional page-level social/OG image — an absolute URL or a site-relative
        path (e.g. 'slides/title-og.png'). Resolved to absolute by the SEO layer;
        falls back to the deck image, then the site-default OG image. */
    image?: string;
    /** Optional alt text for this slide's social image; falls back to the deck's
        imageAlt, then a default describing the site card. */
    imageAlt?: string;
    /** Does this slide OFFER the ADJUST authoring control in a built site?

        A published deck hides ADJUST by default. A slide that *demonstrates* it —
        one whose own prose says "flip ADJUST and drag this box" — sets this, and the
        control appears in the chrome (rendered prominently, since on such a slide the
        button is the point rather than backstage machinery).

        It makes ADJUST **available, not active**: the mode still starts off, so the
        audience sees a normal slide until the speaker flips it. `vite dev` offers the
        control everywhere regardless, and a speaker's sticky `?adjust=off` still
        outranks this. See lib/adjust/adjustAccessCore.ts for the precedence. */
    adjust?: boolean;
    /** Keep this slide OUT of the deck's linear order and its Table of Contents.

        The appendix flag. A hidden slide is still a real, prerendered, linkable
        route — it is simply not part of the forward march: →/Space never wander
        into it, PREV/NEXT step straight over it, and the TOC does not list it. So
        a straight run-through of the deck cannot stumble into the backup demo.

        You reach one by jumping in from a slide that links to it (AppendixLink),
        and you leave by RETURNing to whoever called you (AppendixPage, which reads
        the return address out of `?return=`). See utils/appendixCore.ts. */
    hidden?: boolean;
    /** Optional leave-transition for a View-Transition deck (see setViewTransitions).
        Names the animation used when paging AWAY from this slide — so a slide can be
        animated with the very transition it discusses. NavigationBar exposes it as
        `html[data-vt-kind="…"]`, which view-transitions.css keys its keyframes off.
        Ignored by decks that don't opt into view transitions. Defaults to 'slide'. */
    transition?: string;
    /** Optional leave-transition specifically for paging BACKWARD (← / PREV) away
        from this slide; `transition` is used for forward (→ / NEXT). Lets a slide
        be neutral going forward but replay an effect on the way back (e.g. a "(to)"
        slide that bridges forward with a plain slide yet re-runs its effect on ←).
        Defaults to 'slide' when unset. */
    transitionBack?: string;
}

/** Site-wide default document title — the deck/site name used when neither a
    presentation nor a page sets one. The <title> counterpart to the site favicon
    in app.html (which is the global default in the favicon cascade). */
export const SITE_TITLE = 'The CodingBooth Blog';

/** Compose the browser-tab <title> from the cascade

        page title — presentation title

    each level falling back to the next: page → presentation → site default.
    `pageTitle` is the current slide's own `title` (the same string the Table of
    Contents shows); `presentationTitle` is the deck name a +layout.svelte
    declares (omit it to fall back to SITE_TITLE).

    Unlike the favicon — where the browser uses the LAST <link rel="icon">, so it
    can stack across app.html → layout → page — the browser uses the FIRST
    <title>. So the whole cascade is resolved here and emitted as ONE <title> by
    the shell, rather than layered across files. */
export function documentTitle(pageTitle?: string, presentationTitle?: string): string {
    const deck = presentationTitle ?? SITE_TITLE;
    return pageTitle ? `${pageTitle} — ${deck}` : deck;
}
export interface PageNavigation {
    first: string | undefined;
    last:  string | undefined;
    prev:  string | undefined;
    next:  string | undefined;
}

/** The deck's LINEAR ORDER: the slides →/Space page through and the Table of
    Contents lists. Hidden slides (appendices) are real routes, but they are not
    part of the march — this is the one place that decides that, so paging, the
    TOC and the presenter console's next-slide preview all agree. */
export function visiblePages(pages: Array<Page>): Array<Page> {
    return pages.filter((page) => !page.hidden);
}

export function getPageNavigation(pages: Array<Page>, currentPath: string, prefix: string = ""): PageNavigation {
    const deck  = visiblePages(pages);
    const index = deck.findIndex((page) => page.path === currentPath);
    function addPrefix(path: string | null): string | undefined { return path ? prefix + path : undefined; }

    // Not in the linear order at all — a hidden appendix, or a route missing from
    // pages.ts. Either way it has no neighbours to offer: an appendix is left by
    // RETURNing to the slide that called it, not by paging on to whatever happens
    // to sit at index 0. (Before `hidden` existed, an unlisted path fell out of
    // findIndex as -1 and was handed the FIRST slide as its "next", which read as
    // working navigation on a slide that has none.)
    if (index < 0) return { first: undefined, last: undefined, prev: undefined, next: undefined };

    return {
        first: addPrefix(index > 0               ? deck[0]?.path : null),
        last:  addPrefix(index < deck.length - 1 ? deck[deck.length - 1]?.path : null),
        prev:  addPrefix(index > 0               ? deck[index - 1]?.path : null),
        next:  addPrefix(index < deck.length - 1 ? deck[index + 1]?.path : null),
    };
}
