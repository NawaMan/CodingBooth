import { writable, get } from 'svelte/store';

// A page-wide registry of every <Block>'s live `z` (stacking order), keyed by
// the Block's transient instance id (the same id `selectedBlock` uses). This is
// the seam bring-to-front / send-to-back read: a Block computes its new z from
// its SIBLINGS' z's (frontZ/backZ in utils/stackingCore), and the only way one
// Block sees another's z is a shared registry — Blocks are siblings in the
// slide markup, so no common provider exists to hang a context on. Same reason
// `selectedBlock` and `blockAnchors` are module-level stores.
//
// This is a pure AUTHORING aid (front/back only run in ADJUST mode), so unlike
// `blockAnchors` it is browser-only — a server render never needs it and must
// not touch module state that outlives one SSR pass.
export const blockOrder = writable<Map<number, number>>(new Map());

/** Publish (or update) one Block's current z. Called by Block on every change. */
export function reportBlockZ(id: number, z: number): void {
	blockOrder.update((map) => {
		if (map.get(id) === z) return map; // no churn on an unrelated re-render
		const next = new Map(map);
		next.set(id, z);
		return next;
	});
}

/** Remove a Block's z (it unmounted). */
export function withdrawBlockZ(id: number): void {
	blockOrder.update((map) => {
		if (!map.has(id)) return map;
		const next = new Map(map);
		next.delete(id);
		return next;
	});
}

/** Every OTHER Block's z — the sibling list frontZ/backZ order `self` against. */
export function otherZValues(selfId: number): number[] {
	const out: number[] = [];
	for (const [id, z] of get(blockOrder)) if (id !== selfId) out.push(z);
	return out;
}
