import { writable } from 'svelte/store';

// A page-wide registry of ADJUST-editable opening tags and their edit state,
// so Draw's "Copy changed" patch can include plain <Block>s (and wrappers
// like ImageBlock) that live OUTSIDE any <Draw> — they are siblings of the
// surface, not children, so context can't reach them. Global for the same
// reason adjustHistory is: the author edits one page, not one component
// tree. Nothing here persists — like every ADJUST edit, entries reset on
// reload and Copy → paste is the only way changes reach the source.

export interface Geometry {
	x: number;
	y: number;
	width: number;
	height: number;
	/** Persistent stacking order (Block `z` prop). Optional and 0 by default; the
	    Save patcher only writes it when it is present and non-zero. */
	z?: number;
}

export interface ChangedTagEntry {
	id: number;
	/** Emitted tag name — 'Block', 'ImageBlock', … */
	kind: string;
	name: string;
	/** Current opening tag differs from the mount-time one. */
	dirty: boolean;
	/** The opening tag as mounted (the source form). */
	oldTag: string;
	/** The opening tag with live geometry. */
	newTag: string;
	/** Geometry at mount (matches source) and now — the structured form the dev
	    "Save" endpoint patches with, alongside the human-readable old/new tags. */
	before: Geometry;
	after: Geometry;
}

const entries = writable<Map<number, ChangedTagEntry>>(new Map());

/** Readable view; Map iteration order is registration (mount) order. */
export const adjustChanges = { subscribe: entries.subscribe };

let nextId = 1;
export function nextChangeId(): number {
	return nextId++;
}

/** Upsert an entry (Blocks re-report on every geometry change). */
export function reportChange(entry: ChangedTagEntry): void {
	entries.update((m) => {
		const next = new Map(m);
		next.set(entry.id, entry);
		return next;
	});
}

export function withdrawChange(id: number): void {
	entries.update((m) => {
		if (!m.has(id)) return m;
		const next = new Map(m);
		next.delete(id);
		return next;
	});
}

// --- Draw shapes -----------------------------------------------------------
//
// Draw shapes (Curve/Line/Arc/Polyline/Rect/Ellipse) can't go through the
// geometry registry above: a Curve has no box, only from/to/control points. So
// they publish their WHOLE opening tag (old + new) to this separate registry,
// which the page-level "Save" reads and applies as a literal source replacement
// (see $lib/adjust/patchSource.ts). Kept apart from `adjustChanges` so Draw's own
// "Copy changed" — which already merges its shapes with adjustChanges Blocks —
// doesn't read its own shapes back and double-count them. String keys namespace
// each shape by its Draw instance so multiple <Draw>s on a page don't collide.

export interface ShapeChangeEntry {
	key: string;
	/** Component/tag name — 'Curve', 'Line', 'Rect', … */
	kind: string;
	name: string;
	/** Live tag differs from the mount-time (source) tag. */
	dirty: boolean;
	/** Opening tag as mounted (the literal source string to find). */
	oldTag: string;
	/** Opening tag with live geometry (what to write). */
	newTag: string;
}

const shapes = writable<Map<string, ShapeChangeEntry>>(new Map());

/** Readable view of every registered Draw shape. */
export const shapeChanges = { subscribe: shapes.subscribe };

let nextDrawInstance = 1;
/** A per-<Draw> id so its shape keys never collide with another Draw's. */
export function nextDrawInstanceId(): number {
	return nextDrawInstance++;
}

/** Replace the full set of shapes owned by one Draw instance (upsert-by-prefix):
    every reported shape is keyed `${instance}:...`, so we drop that instance's
    old entries and set the new ones in a single update. */
export function reportShapeChanges(instance: number, list: ShapeChangeEntry[]): void {
	const prefix = `${instance}:`;
	shapes.update((m) => {
		const next = new Map([...m].filter(([k]) => !k.startsWith(prefix)));
		for (const e of list) next.set(e.key, e);
		return next;
	});
}

/** Remove every shape a Draw instance registered (its onDestroy). */
export function withdrawShapeChanges(instance: number): void {
	const prefix = `${instance}:`;
	shapes.update((m) => new Map([...m].filter(([k]) => !k.startsWith(prefix))));
}
