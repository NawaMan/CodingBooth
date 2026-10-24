// Pure maths for <Group> — the coordinate map a group puts between its members
// and the canvas. Browser-free so it unit-tests without a DOM
// (tests/groupCore.test.ts).
//
// A group is a uniform zoom plus a shift: a member authored at local (x, y) is
// drawn at canvas (s·x + dx, s·y + dy), its box s times the size. That one map
// is the whole feature. Members still render REAL canvas geometry (not a CSS
// transform on the box), so a View-Transition morph between two slides glides
// each named part from one true box to the other — the way the EP001 deck
// already morphs its hand-scaled copies, now without the hand-scaling.

/** local → parent: p ↦ s·p + (dx, dy). Uniform scale only — a zoom, never a skew. */
export interface Frame {
	s: number;
	dx: number;
	dy: number;
}

export interface Box {
	x: number;
	y: number;
	width: number;
	height: number;
}

export const IDENTITY: Frame = Object.freeze({ s: 1, dx: 0, dy: 0 });

/** Where a box lands under `f`. */
export function mapBox(f: Frame, b: Box): Box {
	return { x: f.s * b.x + f.dx, y: f.s * b.y + f.dy, width: f.s * b.width, height: f.s * b.height };
}

/** Apply `inner` first, then `outer` — a nested group's map into the canvas. */
export function compose(outer: Frame, inner: Frame): Frame {
	return { s: outer.s * inner.s, dx: outer.s * inner.dx + outer.dx, dy: outer.s * inner.dy + outer.dy };
}

/** The local rectangle that `f` maps onto the canvas [0, cw] × [0, ch] — what a
    member's `bounds="canvas"` clamps to inside a group. */
export function visibleBox(f: Frame, cw: number, ch: number): Box {
	return { x: -f.dx / f.s, y: -f.dy / f.s, width: cw / f.s, height: ch / f.s };
}

/** The smallest box holding every one of `boxes`; null for none. */
export function unionBox(boxes: Iterable<Box>): Box | null {
	let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
	for (const b of boxes) {
		x0 = Math.min(x0, b.x);
		y0 = Math.min(y0, b.y);
		x1 = Math.max(x1, b.x + b.width);
		y1 = Math.max(y1, b.y + b.height);
	}
	return x0 === Infinity ? null : { x: x0, y: y0, width: x1 - x0, height: y1 - y0 };
}

/** `b` grown by `pad` × its own size on every side (0.1 = a 10% margin). */
export function padBox(b: Box, pad: number): Box {
	const p = Number.isFinite(pad) && pad > 0 ? pad : 0;
	return { x: b.x - p * b.width, y: b.y - p * b.height, width: b.width * (1 + 2 * p), height: b.height * (1 + 2 * p) };
}

/** The frame that fits `view` inside the cw × ch canvas, centred and aspect kept
    (CSS `contain`): the longer side touches, the other has a margin. */
export function viewFrame(view: Box, cw: number, ch: number): Frame | null {
	if (!(view.width > 0 && view.height > 0)) return null;
	const s = Math.min(cw / view.width, ch / view.height);
	return { s, dx: cw / 2 - s * (view.x + view.width / 2), dy: ch / 2 - s * (view.y + view.height / 2) };
}

/** The frame that zooms by `zoom` and puts local point `p` at the canvas centre. */
export function focusFrame(p: [number, number], zoom: number, cw: number, ch: number): Frame {
	const s = goodScale(zoom);
	return { s, dx: cw / 2 - s * p[0], dy: ch / 2 - s * p[1] };
}

// --- hide: one scene, a different cast per slide --------------------------------

/** Which members are hidden: by name, or every one (`all`) when an enclosing
    group hid this whole group by ITS name. */
export interface HideState {
	all: boolean;
	names: ReadonlySet<string>;
}

export const NOTHING_HIDDEN: HideState = Object.freeze({ all: false, names: new Set<string>() });

/** A group's hide state: everything its parent hides, plus its own `hide`
    list — and all of it when the parent hides this group by name. */
export function childHide(parent: HideState, groupName: string, hide: Iterable<string>): HideState {
	const names = new Set(parent.names);
	for (const n of hide) if (n) names.add(n);
	return { all: parent.all || (!!groupName && parent.names.has(groupName)), names };
}

export function isHidden(state: HideState, name: string): boolean {
	return state.all || (!!name && state.names.has(name));
}

// --- move: one scene, a part somewhere else on this slide -----------------------

/** Where a part sits on THIS slide, relative to where it is drawn: shifted by
    x/y (the drawing's units) and scaled about its own centre. */
export interface Move {
	x?: number;
	y?: number;
	scale?: number;
}

/** Parts to move, by name — a Block's name, or a nested group's (which moves
    all of it). */
export type MoveMap = Readonly<Record<string, Move>>;

export const NOTHING_MOVED: MoveMap = Object.freeze({});

/** A group's moves: its parent's, then its own on top (its own win). */
export function childMoves(parent: MoveMap, move: MoveMap | null | undefined): MoveMap {
	if (!move || typeof move !== 'object') return parent;
	const own = Object.entries(move).filter(([n, m]) => n && m && typeof m === 'object');
	return own.length ? { ...parent, ...Object.fromEntries(own) } : parent;
}

/** The move for `name`, or null (unnamed, or not in the map). */
export function moveFor(moves: MoveMap, name: string): Move | null {
	return name && Object.prototype.hasOwnProperty.call(moves, name) ? moves[name] : null;
}

/** `m` as a frame for a part whose box is `b`: scale about b's centre, then shift.
    Junk (a NaN, a zero or negative scale) is ignored, never a vanished part. */
export function moveFrame(m: Move | null, b: Box): Frame {
	if (!m) return IDENTITY;
	const s = goodScale(m.scale ?? 1);
	const cx = b.x + b.width / 2;
	const cy = b.y + b.height / 2;
	return { s, dx: cx * (1 - s) + finite(m.x ?? 0), dy: cy * (1 - s) + finite(m.y ?? 0) };
}

/** True when `f` changes nothing. */
export function isIdentity(f: Frame): boolean {
	return f.s === 1 && f.dx === 0 && f.dy === 0;
}

// --- morph: naming the parts for a View-Transition glide ----------------------

/** A string usable as a view-transition-name: a CSS identifier that isn't one of
    the keywords the property already means something by. */
const IDENT = /^[A-Za-z_][A-Za-z0-9_-]*$/;
const RESERVED = new Set(['none', 'auto', 'inherit', 'initial', 'unset', 'revert', 'match-element']);

/** `<prefix>-<name>`, or null when either part can't make a valid name (an
    unnamed member, or a name with a space in it — it just doesn't morph). */
export function morphName(prefix: string | null, name: string): string | null {
	if (!prefix || !name) return null;
	const full = `${prefix}-${name}`;
	return IDENT.test(full) && !RESERVED.has(full) ? full : null;
}

/** The stylesheet that names each part: one rule per member, keyed on the
    member's `data-gp-morph` attribute. With `on`, the names only exist while one
    of those transition kinds runs (`html[data-vt-kind="…"]`, set by the deck's
    pager) — so a plain 'slide' to a neighbouring slide leaves the parts alone. */
export function morphRules(prefix: string | null, names: Iterable<string>, on: string | string[] | null): string {
	const kinds = (on == null ? [] : Array.isArray(on) ? on : [on]).filter((k) => /^[\w-]+$/.test(k));
	const scopes = kinds.length ? kinds.map((k) => `html[data-vt-kind="${k}"] `) : [''];
	const rules: string[] = [];
	for (const n of new Set(names)) {
		const vt = morphName(prefix, n);
		if (!vt) continue;
		const selector = scopes.map((s) => `${s}[data-gp-morph="${vt}"]`).join(', ');
		rules.push(`${selector} { view-transition-name: ${vt}; }`);
	}
	return rules.join('\n');
}

const goodScale = (n: number) => (Number.isFinite(n) && n > 0 ? n : 1);
const finite = (n: number) => (Number.isFinite(n) ? n : 0);

/** A Group's props, as resolveFrame reads them. */
export interface GroupProps {
	/** Placement: the group's local origin sits at (x, y), scaled by `scale`. */
	x?: number;
	y?: number;
	scale?: number;
	/** Camera: this local rectangle fills the canvas. */
	view?: Box | null;
	/** Camera: this member (by name) fills the canvas, with `pad` margin. */
	fit?: string | null;
	pad?: number;
	/** Camera: this member's centre (by name) or this local point sits at the
	    canvas centre, zoomed by `zoom`. */
	focus?: string | [number, number] | null;
	zoom?: number;
}

/** How a group's frame was chosen — reported in ADJUST so an author can see
    which prop is in charge (and that an unknown name fell through). */
export type FrameSource = 'view' | 'fit' | 'focus' | 'place';

/** A group's local → parent frame. Precedence: `view`, then `fit`, then
    `focus`, then the plain `x`/`y`/`scale` placement. A camera prop whose name
    isn't a member (yet — members register as they mount) falls through to the
    next, so a typo shows the scene unzoomed rather than nothing at all. */
export function resolveFrame(
	p: GroupProps,
	lookup: (name: string) => Box | undefined,
	cw: number,
	ch: number
): { frame: Frame; source: FrameSource } {
	if (p.view) {
		const f = viewFrame(p.view, cw, ch);
		if (f) return { frame: f, source: 'view' };
	}
	if (p.fit) {
		const b = lookup(p.fit);
		const f = b && viewFrame(padBox(b, p.pad ?? 0), cw, ch);
		if (f) return { frame: f, source: 'fit' };
	}
	if (p.focus != null) {
		let point: [number, number] | null = null;
		if (typeof p.focus === 'string') {
			const b = lookup(p.focus);
			if (b) point = [b.x + b.width / 2, b.y + b.height / 2];
		} else if (Number.isFinite(p.focus[0]) && Number.isFinite(p.focus[1])) {
			point = p.focus;
		}
		if (point) return { frame: focusFrame(point, p.zoom ?? 1, cw, ch), source: 'focus' };
	}
	return { frame: { s: goodScale(p.scale ?? 1), dx: finite(p.x ?? 0), dy: finite(p.y ?? 0) }, source: 'place' };
}
