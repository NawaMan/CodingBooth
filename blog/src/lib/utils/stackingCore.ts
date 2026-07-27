// Pure z-order math for a Block's bring-to-front / send-to-back, in the same
// total, NaN-safe spirit as drawCore/connectorCore/columnsCore: junk in the
// sibling list is ignored, a NaN `self` is treated as 0, and a block that is
// already the unique extreme is left exactly where it is (so tapping "Front"
// twice, or on a block that is already on top, never churns the source or the
// undo history).
//
// Both take `self` (the block's current z) and `others` (every OTHER block's
// live z on the slide — the caller excludes the block itself by id). They return
// the z to assign; the caller compares it to `self` and only records a change if
// it actually moved.

/** Sanitise a z value: a non-finite input orders as 0 (the default layer). */
function clean(z: number): number {
	return Number.isFinite(z) ? z : 0;
}

/**
 * The z that puts `self` strictly above every other block. If `self` is already
 * the top (greater than every other), it is returned unchanged — bring-to-front
 * is idempotent. With no other blocks there is nothing to order against, so
 * `self` is returned as-is.
 */
export function frontZ(self: number, others: number[]): number {
	const s = clean(self);
	const finite = others.filter(Number.isFinite);
	if (finite.length === 0) return s;
	const max = Math.max(...finite);
	return s > max ? s : max + 1;
}

/**
 * The z that puts `self` strictly below every other block. Mirror of
 * {@link frontZ}: already the bottom → unchanged; no other blocks → `self`.
 * The result may go negative — that is what "send to back" means, and blocks
 * share one stacking context, so their order relative to each other is all that
 * matters.
 */
export function backZ(self: number, others: number[]): number {
	const s = clean(self);
	const finite = others.filter(Number.isFinite);
	if (finite.length === 0) return s;
	const min = Math.min(...finite);
	return s < min ? s : min - 1;
}
