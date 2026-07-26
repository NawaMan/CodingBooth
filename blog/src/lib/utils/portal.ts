// A Svelte action that RELOCATES its node into another element — a "portal".
//
// GeekPresent's chrome lives in two disjoint DOM subtrees: the slide content (inside the
// scaled `.content`) and the viewport-fixed `.overlay` (SlideToolbar / ControlBar). A
// control authored in ONE that must physically sit in the OTHER — the deck-level
// AnimationBar, dropped in a slide but belonging in the bottom ControlBar — can't get
// there by CSS. `use:portal` moves the real element there instead, so all its Svelte
// reactivity, WAAPI handles and event handlers keep working — it is the same node, just
// re-parented.
//
// The target is REACTIVE: pass a store value (e.g. `use:portal={hosted ? $slot : null}`)
// and the node moves the moment the slot element appears, and moves back to its original
// spot (or nowhere, held by the caller) when the target goes null. A null target parks
// the node at its authored position — so a bar with no ControlBar to host it simply
// stays where it was written, which is exactly what a bare unit test sees.

export function portal(node: HTMLElement, target: HTMLElement | null | undefined) {
	// Remember where the node was authored, so a null target can put it back rather than
	// orphaning it. A comment placeholder marks the spot even after the node leaves.
	const home = document.createComment('portal-anchor');
	node.parentNode?.insertBefore(home, node);

	let current: HTMLElement | null = null;

	function place(t: HTMLElement | null | undefined) {
		const next = t ?? null;
		if (next === current) return;
		if (next) next.appendChild(node);
		else home.parentNode?.insertBefore(node, home); // back to the authored position
		current = next;
	}

	place(target);

	return {
		update(t: HTMLElement | null | undefined) { place(t); },
		destroy() {
			home.remove();
			// A node parked at home sits inside its component's subtree, and Svelte's
			// own teardown removes it. A node still PORTALED lives OUTSIDE that
			// subtree, where anchor-range teardown (block close, HMR replacement —
			// e.g. the reload a SAVE triggers) can no longer see it: it would strand
			// in the target for the remounted component to double up against. Evict
			// it ourselves — if Svelte also removes it, the second remove is a no-op.
			if (current) node.remove();
		},
	};
}
