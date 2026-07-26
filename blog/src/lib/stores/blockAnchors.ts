import { writable } from 'svelte/store';

/** A named anchor's box, in canvas pixels — exactly a Block's x/y/width/height. */
export interface AnchorRect {
	x: number;
	y: number;
	width: number;
	height: number;
}

// The page-wide registry of NAMED <Block> boxes, keyed by `name`.
//
// This is the seam that turns Block into a diagramming primitive: a <Connector>
// looks its endpoints up here by name, so an arrow follows its boxes as they are
// dragged around in ADJUST mode without the author touching a single coordinate.
//
// Module-level (not context) for the same reason `selectedBlock` is: a Connector
// and the Blocks it links are SIBLINGS in the slide markup, so no common provider
// exists to hang a context on.
//
// NOT browser-gated, unlike `adjustChanges` — a Connector must resolve its
// endpoints during **SSR** too, or the prerendered slide would ship an empty
// diagram. That has one consequence worth knowing:
//
//   * Blocks register as their instance code runs, which during SSR is document
//     order. So a <Connector> only sees a Block that appears BEFORE it in the
//     markup. Put connectors after the boxes they link. (In the browser it
//     self-corrects on the next flush — the store is reactive — but the
//     prerendered HTML would be missing the shaft.)
//   * Names persist between server renders (there is no onDestroy on the
//     server). Harmless: every slide re-registers its own names before its
//     connectors read them, and an unknown name simply renders nothing.
export const blockAnchors = writable<Map<string, AnchorRect>>(new Map());

/** Publish (or update) a named box. Called by Block on every geometry change. */
export function reportAnchor(name: string, rect: AnchorRect): void {
	if (!name) return;
	blockAnchors.update((map) => {
		const prev = map.get(name);
		if (
			prev &&
			prev.x === rect.x &&
			prev.y === rect.y &&
			prev.width === rect.width &&
			prev.height === rect.height
		) {
			// Same box — don't churn subscribers (Block's reactive statement fires
			// on every prop touch, not only on real movement).
			return map;
		}
		const next = new Map(map);
		next.set(name, { ...rect });
		return next;
	});
}

/** Remove a named box (the Block unmounted). */
export function withdrawAnchor(name: string): void {
	if (!name) return;
	blockAnchors.update((map) => {
		if (!map.has(name)) return map;
		const next = new Map(map);
		next.delete(name);
		return next;
	});
}
