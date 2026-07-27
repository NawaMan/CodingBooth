// Internal helpers for ADJUST-mode shape editing (DRAW-3). Not public API.
//
// The snippet a shape's Copy emits is its current OPENING tag with live
// geometry — snippet-emit, never live source rewrite (Block's contract).
// These helpers keep the attribute formatting identical across shapes so the
// copied tag always round-trips: paste it over the source line and the
// render is reproduced exactly.

import type { Point } from './types';

let nextId = 1;
/** Stable per-instance id for ShapeEditor registrations. */
export function newEditorId(): number {
	return nextId++;
}

/** Trim float noise for copied attributes: ≤2 decimals, never NaN. */
export function fmtNum(n: number): string {
	return String(Math.round((Number.isFinite(n) ? n : 0) * 100) / 100 + 0);
}

/** `[510, 770]` — the point literal an author writes on a slide. */
export function fmtPoint(p: Point): string {
	return `[${fmtNum(p[0])}, ${fmtNum(p[1])}]`;
}

const num = (n: number) => (Number.isFinite(n) ? n : 0);

/** A per-stop easing value safe to emit into a generated <style>. Keeps only
 *  the characters a CSS timing function needs (keywords, cubic-bezier/steps
 *  numbers), so a stop's `ease` can never break out of the keyframe block.
 *  Returns '' for anything suspicious. */
export function sanitizeEase(ease: string | undefined | null): string {
	if (!ease) return '';
	const e = String(ease).trim();
	return /^[a-z0-9.,()%\- ]+$/i.test(e) ? e : '';
}

/** The two keyframe stops bracketing a target percent, plus the local 0..1
 *  fraction between them. `sorted` must be ascending by pct. */
export function neighborsAt<T extends { pct: number }>(
	sorted: T[],
	target: number
): { a: T; b: T; frac: number } {
	let a = sorted[0];
	let b = sorted[sorted.length - 1];
	for (let k = 0; k < sorted.length - 1; k++) {
		if (target >= num(sorted[k].pct) && target <= num(sorted[k + 1].pct)) {
			a = sorted[k];
			b = sorted[k + 1];
			break;
		}
	}
	const span = num(b.pct) - num(a.pct);
	return { a, b, frac: span ? (target - num(a.pct)) / span : 0 };
}

/** The midpoint percent of the widest gap in a pct-sorted stop list — where
 *  "+ keyframe" inserts when no playhead is available. */
export function widestGapMid<T extends { pct: number }>(sorted: T[]): number {
	let gi = 0;
	let gap = -1;
	for (let k = 0; k < sorted.length - 1; k++) {
		const g = num(sorted[k + 1].pct) - num(sorted[k].pct);
		if (g > gap) {
			gap = g;
			gi = k;
		}
	}
	return Math.round((num(sorted[gi].pct) + num((sorted[gi + 1] ?? sorted[gi]).pct)) / 2);
}

/** Linear interpolation between two optional points at fraction `frac`
 *  (rounded); a lone point passes through. */
export function lerpPointAt(a: Point | undefined, b: Point | undefined, frac: number): Point | undefined {
	if (a && b) return [Math.round(a[0] + (b[0] - a[0]) * frac), Math.round(a[1] + (b[1] - a[1]) * frac)];
	return a ?? b;
}

/** The AnimationBar playhead as a 0–100 percent, read from a shape's own
 *  live CSS animation on `el` (whose keyframes are named `animName`).
 *  Returns null when there's no running animation to read (SSR, tests, or
 *  a browser without getAnimations) — callers fall back to the widest gap. */
export function playheadPercent(
	el: Element | undefined,
	animName: string,
	durationSec: number | null,
	delaySec = 0
): number | null {
	if (!el || !durationSec || typeof el.getAnimations !== 'function') return null;
	const anims = el.getAnimations();
	const a =
		anims.find((x) => (x as CSSAnimation).animationName === animName) ?? anims[0];
	const t = a?.currentTime;
	if (typeof t !== 'number') return null;
	// currentTime spans delay + duration; the keyframe pct only spans the
	// duration, so a delayed animation's playhead starts after the hold.
	return Math.max(0, Math.min(100, ((t - delaySec * 1000) / (durationSec * 1000)) * 100));
}

/** A box shape's opening tag in EXACTLY the format the hosted Block's Copy
 *  emits (name, extra attrs, rounded geometry, aspect) — one source of truth
 *  so the per-shape Copy and the "Copy changed" patch never drift. */
export function boxTag(
	tag: string,
	name: string,
	attrs: string,
	x: number,
	y: number,
	w: number,
	h: number,
	aspect: number | boolean | null = null
): string {
	const aspectAttr = typeof aspect === 'number' ? ` aspect={${aspect}}` : aspect === true ? ' aspect' : '';
	return (
		`<${tag}${name ? ` name="${name}"` : ''}${attrs}` +
		` x={${Math.round(x)}} y={${Math.round(y)}}` +
		` width={${Math.round(w)}} height={${Math.round(h)}}${aspectAttr} />`
	);
}

export interface SharedShapeAttrs {
	arrow?: string;
	arrowSize?: number;
	color?: string;
	thickness?: number;
	dash?: boolean | string;
	label?: string;
	labelText?: string;
	labelAt?: number;
	labelOffset?: number;
	draw?: number;
	drawDelay?: number;
	grid?: number;
	/** The author's own pass-through props. They carry NO meaning for ADJUST — it
	    neither reads nor edits them — but they must survive the round-trip, because
	    ADJUST replaces the whole opening tag. Anything this function forgets to emit
	    is DELETED from the author's source the moment they drag the shape. */
	id?: string;
	class?: string;
	style?: string;
}

/** Quote an attribute value without ever producing a broken tag: a value carrying a
 *  double quote (`style='content: "x"'`) is emitted in single quotes instead. Total,
 *  like the rest of this module — the emitted line is pasted straight into source, so
 *  it has to parse whatever the author wrote. */
function attr(name: string, value: string): string {
	return value.includes('"') ? ` ${name}='${value}'` : ` ${name}="${value}"`;
}

/** The non-geometry attributes of a copied opening tag, in a stable order,
 *  emitted only when they differ from the shape defaults. */
export function sharedAttrs(a: SharedShapeAttrs): string {
	let out = '';
	if (a.arrow && a.arrow !== 'none') out += ` arrow="${a.arrow}"`;
	if (a.arrowSize != null) out += ` arrowSize={${fmtNum(a.arrowSize)}}`;
	if (a.color) out += ` color="${a.color}"`;
	if (a.thickness != null) out += ` thickness={${fmtNum(a.thickness)}}`;
	if (a.dash === true) out += ' dash';
	else if (typeof a.dash === 'string' && a.dash) out += ` dash="${a.dash}"`;
	if (a.label) out += ` label="${a.label}"`;
	if (a.labelText) out += ` labelText="${a.labelText}"`;
	if (a.labelText && a.labelAt != null && a.labelAt !== 0.5) out += ` labelAt={${fmtNum(a.labelAt)}}`;
	if (a.labelText && a.labelOffset != null && a.labelOffset !== 20)
		out += ` labelOffset={${fmtNum(a.labelOffset)}}`;
	if (a.draw) out += ` draw={${fmtNum(a.draw)}}`;
	if (a.draw && a.drawDelay) out += ` drawDelay={${fmtNum(a.drawDelay)}}`;
	if (a.grid && a.grid > 1) out += ` grid={${fmtNum(a.grid)}}`;
	// Last, and only when the author set them — so an untouched shape's tag is byte
	// for byte what it always was, and a decorated one keeps its decoration.
	if (a.id) out += attr('id', a.id);
	if (a.class) out += attr('class', a.class);
	if (a.style) out += attr('style', a.style);
	return out;
}
