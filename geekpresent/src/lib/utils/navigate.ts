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
export const SITE_TITLE = 'GeekPresent';

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

export function getPageNavigation(pages: Array<Page>, currentPath: string, prefix: string = ""): PageNavigation {
    const index = pages.findIndex((page) => page.path === currentPath);
    function addPrefix(path: string | null): string | undefined { return path ? prefix + path : undefined; }

    return {
        first: addPrefix(index > 0                ? pages[0]?.path : null),
        last:  addPrefix(index < pages.length - 1 ? pages[pages.length - 1]?.path : null),
        prev:  addPrefix(index > 0                ? pages[index - 1]?.path : null),
        next:  addPrefix(index < pages.length - 1 ? pages[index + 1]?.path : null),
    };
}
