/*
  Put the `@page` rule in the document's head, and keep it there.

  `@page` takes no selector — there is no class, no element, nothing to hang it off — so the
  paper size has to be written as a rule, and the rule has to be replaced whenever the paper
  changes (the notes band adds three inches, and the reader can toggle it).

  It cannot be left to `<svelte:head>`. An `{@html}` block there is rendered on the SERVER, and
  on hydration Svelte adopts the head nodes it finds rather than diffing them — so the rule the
  server computed STAYS, and the one the client computed never lands. The failure is
  particularly nasty because everything else updates: the frame grows its notes band, the paper
  does not grow with it, and the note is pushed onto a second page. Printing a slide with
  `?notes` came out as two sheets, and nothing in the markup looked wrong.

  So: one <style> element, owned by id, written imperatively, idempotent. Browser-only by
  nature — there is no printing on a server.
*/

const ID = 'gp-page-rule';

/** Install or replace the document's `@page` rule. */
export function applyPageRule(css: string): void {
	if (typeof document === 'undefined') return;
	let el = document.getElementById(ID) as HTMLStyleElement | null;
	if (!el) {
		el = document.createElement('style');
		el.id = ID;
		document.head.appendChild(el);
	}
	// Last rule in the head wins, and this one is appended after the SSR'd head — so it does not
	// merely coexist with a stale rule, it overrides it.
	if (el.textContent !== css) el.textContent = css;
}
