// Preloading the neighbouring slides (Chrome's speculation rules).
//
// Every page turn is a full page load, and a cached load still restarts the app: the
// scripts run again, the shell hydrates, the slide mounts — a blank moment each time. A
// `<script type="speculationrules">` naming the next and previous slide lets Chrome load
// them, scripts and all, in a hidden tab; the turn then swaps that page in at once. Other
// browsers ignore the script and load as before.
//
// The URLs must be exactly the ones the deck will navigate to — a prerender is used only on
// an exact match — so they come from the same links the pager uses, with the console's
// `?present` added the same way NavigationBar.decorate adds it.

export interface NeighbourLinks {
	prev?: string;
	next?: string;
}

/** The URLs to preload from this slide: next first (the likelier turn), then previous. */
export function neighbourUrls(nav: NeighbourLinks, present: boolean): string[] {
	const out: string[] = [];
	for (const href of [nav.next, nav.prev]) {
		if (!href) continue;
		const url = present ? href + (href.includes('?') ? '&' : '?') + 'present' : href;
		if (!out.includes(url)) out.push(url);
	}
	return out;
}

/** The speculation-rules JSON for `urls`, or '' when there is nothing to preload. */
export function speculationRules(urls: string[]): string {
	if (urls.length === 0) return '';
	return JSON.stringify({ prerender: [{ source: 'list', urls, eagerness: 'immediate' }] });
}
