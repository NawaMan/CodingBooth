// Public types for the Draw component family.
// See specs/DRAW-1.md for the full design. Geometry props stay human-readable
// and diffable (from/to/x/y) — raw SVG path syntax never crosses this API;
// drawCore.ts owns the translation to `d` strings.

import type { Snippet } from 'svelte';

/** A point in canvas pixels, [x, y] — same coordinate space as Block x/y. */
export type Point = [number, number];

/** Where arrowheads go on a Line (and, in Phase 2, curved shafts). */
export type ArrowMode = 'none' | 'start' | 'end' | 'both';

/** Props shared by every shape component. */
export interface ShapeStyleProps {
	/** Stroke color; overrides --draw-stroke (default currentColor). */
	color?: string;
	/** Stroke width in canvas px; overrides --draw-thickness (default 4). */
	thickness?: number;
	/** true for the default dash pattern, or an SVG dasharray string like "12 6". */
	dash?: boolean | string;
	/** aria-label for shapes that carry meaning on their own. */
	label?: string;
}

/** Draw-on animation, shared by every stroked shape
 *  (Line/Curve/Arc/Polyline/Rect/Ellipse). */
export interface DrawOnProps {
	/** Seconds for the shape to draw itself in (stroke-dasharray/dashoffset,
	 *  pure CSS — runs in the prerendered page without JS and is scrubbed by
	 *  AnimationBar like any finite animation). Arrowheads and labelText fade
	 *  in over the final fifth. While animating, the animation owns the dash
	 *  pattern, so `dash` is ignored. */
	draw?: number;
	/** Seconds to wait before the draw-on starts. Stagger several shapes'
	 *  drawDelay to build a diagram step by step on ONE timeline —
	 *  AnimationBar's envelope covers delay + duration, so the whole
	 *  sequence scrubs as one. Only meaningful with `draw`. */
	drawDelay?: number;
}

/** One keyframe for an animated Line: a percent (0–100) plus the endpoint
 *  positions (omitted → base from/to) and/or a `drawn` self-draw fraction
 *  (0 = nothing, 1 = full). Geometry and reveal are independent tracks on
 *  the shared `animate` timeline — see CurveStop. */
export interface LineStop {
	pct: number;
	from?: Point;
	to?: Point;
	drawn?: number;
	/** CSS animation-timing-function for the segment STARTING at this stop
	 *  (e.g. 'ease-in', 'ease-out', 'linear'); default inherits the
	 *  animation's ease-in-out. Applies to both tracks this stop is in. */
	ease?: string;
}

/** One keyframe for an animated Curve: a percent plus any of the endpoints /
 *  control points at that moment (omitted ones fall back to the base props),
 *  and/or a `drawn` self-draw fraction (0 = nothing, 1 = full). A stop with
 *  geometry keys is a geometry keyframe; a stop with `drawn` is a reveal
 *  keyframe (keyframed stroke-dashoffset) — the two tracks are independent
 *  and share the `animate` timeline, so a curve can bend AND draw itself in
 *  non-linearly. A cubic keeps c2 defined across stops and a quadratic keeps
 *  it absent, so the generated `d` keeps one command structure. */
export interface CurveStop {
	pct: number;
	from?: Point;
	to?: Point;
	c1?: Point;
	c2?: Point;
	drawn?: number;
	/** CSS timing function for the segment starting here — see LineStop. */
	ease?: string;
}

/** One keyframe for an animated Arc: a percent plus any of the endpoints
 *  and/or the signed `bend` (omitted → base), and/or a `drawn` self-draw
 *  fraction. Geometry and reveal are independent tracks on the shared
 *  `animate` timeline — see CurveStop. Because arc-command flags don't
 *  interpolate, the geometry track samples each stop's arc into a
 *  fixed-count polyline. */
export interface ArcStop {
	pct: number;
	from?: Point;
	to?: Point;
	bend?: number;
	drawn?: number;
	/** CSS timing function for the segment starting here — see LineStop. */
	ease?: string;
}

/** One keyframe for an animated Sprite — a positioned, rotatable HTML box
 *  (the KeyframeStudio "flying element", folded into the Draw family). A
 *  percent (0–100) plus the box geometry at that moment: top-left x/y, size
 *  w/h (canvas px), and an optional rotation `rot` (degrees). Unlike the path
 *  shapes, every Sprite stop carries FULL geometry (there's no base pose to
 *  fall back to) — the geometry is edited by dragging the per-stop ghost, and
 *  the moving element tweens between stops as pure CSS (left/top/width/height/
 *  transform keyframes), so it prerenders and AnimationBar scrubs it. */
export interface SpriteStop {
	pct: number;
	x: number;
	y: number;
	w: number;
	h: number;
	/** Rotation in degrees at this stop (transform: rotate); default 0. */
	rot?: number;
	/** CSS timing function for the segment starting here — see LineStop. */
	ease?: string;
}

/** Visible-label props shared by the path shapes (Line/Curve/Arc). The
 *  aria-only `label` (ShapeStyleProps) is unchanged; `labelText` is its
 *  visible twin — real SVG <text> riding the shape. */
export interface PathLabelProps {
	/** Visible label rendered as SVG <text> on the shape. */
	labelText?: string;
	/** Where along the shape (t ∈ [0, 1]); default 0.5 (midpoint/apex). */
	labelAt?: number;
	/** Perpendicular offset in canvas px — positive is to the LEFT of the
	 *  direction of travel (screen-up on a left-to-right shape); negative
	 *  flips to the other side. Default 20. */
	labelOffset?: number;
}

/** One segment of a multi-segment <Path>: its endpoint `to`, plus optional
 *  control data that selects the segment KIND — `bend` makes it an arc, `c1`
 *  (optionally `c2`) makes it a Bézier curve, and neither makes it a straight
 *  line. Each segment's start point defaults to the previous segment's `to`
 *  (or the Path's `start`, for the first), so a chain is authored as a start
 *  point plus a list of destinations. Give an explicit `from` to lift the pen
 *  and begin a disjoint sub-path. */
export interface PathSegment {
	/** This segment's endpoint (canvas px). Required. */
	to: Point;
	/** Override the chained start point (defaults to the previous `to`). */
	from?: Point;
	/** First control point → a Bézier curve (quadratic unless `c2` is set). */
	c1?: Point;
	/** Second control point → a cubic Bézier (only used when `c1` is set too). */
	c2?: Point;
	/** Signed sagitta fraction → a circular arc (see Arc's `bend`); takes
	 *  precedence over `c1`/`c2` when both are given. */
	bend?: number;
}

/** One keyframe for an animated multi-segment <Path>: a percent (0–100) plus a
 *  whole pose at that moment — the pen `start` and/or the full `segments` list
 *  (each omitted → the base prop), and/or a `drawn` self-draw fraction. Geometry
 *  and reveal are independent tracks on the shared `animate` timeline (see
 *  CurveStop). Because a chain's command structure varies across segments (and
 *  arc flags don't interpolate), the geometry track SAMPLES each pose into a
 *  fixed-count polyline — so keep the segment count/kinds matching the base and
 *  across stops for a smooth morph. */
export interface PathStop {
	pct: number;
	/** Pen start at this keyframe (omitted → the base `start`). */
	start?: Point;
	/** The whole segment list at this keyframe (omitted → the base `segments`). */
	segments?: PathSegment[];
	/** Self-draw progress 0 (nothing) → 1 (full) at this keyframe. */
	drawn?: number;
	/** CSS timing function for the segment starting here — see LineStop. */
	ease?: string;
}

/** The geometry of a path-like shape, as evaluators and path builders see it.
 *  Discriminated by `kind`; every variant is plain data (canvas px + the
 *  human-readable `bend`), so drawCore's pointAt/angleAt/shortenShape stay
 *  pure. Components build these from their props in a $derived. */
export type PathShape =
	| { kind: 'line'; from: Point; to: Point }
	| { kind: 'quadratic'; from: Point; to: Point; c1: Point }
	| { kind: 'cubic'; from: Point; to: Point; c1: Point; c2: Point }
	| { kind: 'arc'; from: Point; to: Point; bend: number }
	// The Polyline's geometry: waypoints instead of from/to. Evaluators expand
	// it to a segment chain (straight lines, or Catmull-Rom cubics when
	// `smooth`) and delegate — see drawCore's polylineSegments. Note a sharp
	// corner has no continuous tangent: an orienting rider SNAPS its heading
	// there (angle-unwrapped, so it turns the short way, but abruptly) —
	// `smooth` is the fix when that looks wrong.
	| { kind: 'polyline'; points: Point[]; close?: boolean; smooth?: boolean };

/** A PathShape that runs from → to — every kind EXCEPT polyline. This is what
 *  endpoint-generic code (chained Path segments, arrowhead trims, endpoint
 *  handles) works over; a polyline reaches it only after expanding to its
 *  segment chain (drawCore's polylineSegments). */
export type SegmentShape = Exclude<PathShape, { kind: 'polyline' }>;

/** What a selected shape exposes to Draw's Copy toolbar (Phase 3). All
 *  getters, created by the shape over its live geometry, so the toolbar's
 *  readout and copied tag follow every handle drag. */
/** One row in the toolbar's keyframe editor for an animated shape. */
export interface AnimStopRow {
	id: number;
	pct: number;
	/** Reveal draw-progress at this stop as a PERCENT (0–100), or null when
	 *  the stop has no reveal keyframe. Present only for shapes with a reveal
	 *  track (Curve). */
	drawn?: number | null;
	/** CSS timing function for the segment starting at this stop, or null for
	 *  the default. */
	ease?: string | null;
	/** Box pose at this stop — left/top/width/height in canvas px and rotate in
	 *  degrees. Present only for box-pose shapes (Sprite); the panel shows
	 *  numeric l/t/w/h/r fields per row when they are. */
	x?: number;
	y?: number;
	w?: number;
	h?: number;
	rot?: number;
}

/** The keyframe editor a shape exposes when it is animating (stops +
 *  animate). Drives the toolbar's per-shape "keyframes" panel: list the
 *  stops, add one (interpolated into the widest gap), remove one (min 2),
 *  and retime one. Structural edits are finder state like every drag —
 *  reset on reload, Copy → paste to persist. */
export interface AnimEditor {
	readonly stops: AnimStopRow[];
	addStop(): void;
	removeStop(id: number): void;
	setPct(id: number, pct: number): void;
	/** Set/clear a stop's reveal draw-progress (percent 0–100, or null to
	 *  remove the reveal keyframe). Present only when the shape supports a
	 *  reveal track; the panel shows a "drawn %" field per row when it is. */
	setDrawn?(id: number, drawnPct: number | null): void;
	/** Set/clear a stop's segment easing (a CSS timing function, or null for
	 *  the default). The panel shows an easing picker per row. */
	setEase?(id: number, ease: string | null): void;
	/** Set one field of a stop's box pose (Sprite): 'x'|'y'|'w'|'h' in canvas
	 *  px, 'rot' in degrees. Present only for box-pose shapes; the panel shows
	 *  numeric l/t/w/h/r fields per row when it is — drag on-canvas OR type. */
	setPose?(id: number, key: 'x' | 'y' | 'w' | 'h' | 'rot', value: number): void;
	/** A LIVE preview at the AnimationBar playhead, for scrubbing: the
	 *  timeline `pct` (0–100) and, when the shape has an active reveal track,
	 *  the interpolated `drawn` percent (read off the animated
	 *  stroke-dashoffset, so it tracks the eased value exactly). Null when
	 *  nothing is animating. The toolbar polls this each frame. */
	preview?(): { pct: number; drawn: number | null } | null;
}

/** The draw-on reveal editor a shape exposes when it is drawing itself on
 *  (`draw` set, no geometry stops). Drives the toolbar's "draw-on" panel:
 *  retime the reveal duration and its start delay, live and copyable. */
export interface DrawOnEditor {
	/** Reveal duration in seconds. */
	readonly seconds: number;
	/** Start delay in seconds (0 = none). */
	readonly delay: number;
	setSeconds(v: number): void;
	setDelay(v: number): void;
}

export interface ShapeEditor {
	readonly id: number;
	/** Tag name, e.g. 'Line' — shown when the shape has no `name`. */
	readonly kind: string;
	readonly name: string;
	/** This shape's ADJUST editing chrome — guide lines + handles, wrapped in a
	 *  `<g class="draw-chrome" data-shape="…">`. The shape renders it inline
	 *  (inside its own `<g>`) while it is NOT the hoisted one; when it IS, <Draw>
	 *  renders this very snippet last inside the surface instead, so the handles
	 *  paint and hit-test above every other shape. SVG has no z-index — paint
	 *  order IS document order — so re-parenting the chrome is the only way to
	 *  raise it, and moving the chrome (rather than the shape's `<g>`) raises
	 *  INTERACTION without disturbing the visible overlap the author drew. */
	readonly chrome?: Snippet;
	/** One-line live geometry summary for the toolbar. */
	readonly readout: string;
	/** The shape's current OPENING tag — what Copy emits. */
	readonly snippet: string;
	/** The tag as the PROPS would emit it — the shape's source form, used as
	 *  the OLD side of the "Copy changed" patch. */
	readonly sourceSnippet: string;
	/** True when live (dragged) geometry differs from the props. */
	readonly dirty: boolean;
	/** Keyframe editor when the shape is animating; null/absent otherwise. */
	readonly anim?: AnimEditor | null;
	/** Draw-on reveal editor when the shape is drawing itself on;
	 *  null/absent otherwise (mutually exclusive with `anim`). */
	readonly drawEdit?: DrawOnEditor | null;
}

/** What a box-geometry shape (Rect/Ellipse) registers with Draw so its
 *  ADJUST-mode editing can ride Block wholesale: Draw renders one
 *  <Block tag={tag} …> per registration as an HTML sibling of the svg
 *  (HTML can't render inside it), two-way bound to the live geometry.
 *  Block then provides move, resize, aspect-lock, grid, bounds, undo, and
 *  a Copy that emits `<Rect …/>` / `<Ellipse …/>`. */
export interface BlockShapeRegistration {
	readonly id: number;
	/** Copied tag name — 'Rect' / 'Ellipse', not 'Block'. */
	readonly tag: string;
	readonly name: string;
	readonly grid: number;
	/** Pre-rendered extra attributes for the copied tag (leading space). */
	readonly attrs: string;
	readonly aspect: number | boolean | null;
	readonly bounds: 'canvas' | 'none';
	/** Live / source opening tags + dirtiness, for the "Copy changed" patch
	 *  (same emission format as the hosted Block's own Copy). */
	readonly snippet: string;
	readonly sourceSnippet: string;
	readonly dirty: boolean;
	/** Draw-on reveal editor when the box is drawing itself on; Block shows
	 *  time/delay fields in its toolbar. Null/absent otherwise. */
	readonly drawEdit?: DrawOnEditor | null;
	/** The shape's author `style`, forwarded so the editing Block can badge a
	 *  geometry collision on the box you actually grab. The shape applies (and
	 *  guards) this style itself, on its own SVG element — the Block never renders
	 *  or emits it. See adjust/styleGuardCore.ts. */
	readonly style?: string;
	/** Live box geometry, get/set — Block binds to these. */
	x: number;
	y: number;
	width: number;
	height: number;
}

/** Canvas size (and, in ADJUST mode, the editing/selection surface) shared
 *  by <Draw> with its shape children via context. */
export interface DrawContext {
	readonly width: number;
	readonly height: number;
	/** True while ADJUST-mode editing is active (canAdjust && adjustMode).
	 *  Shapes render handles/selection chrome only when this is on. */
	readonly editing: boolean;
	/** The shape whose geometry the floating toolbar currently shows. */
	readonly selected: ShapeEditor | null;
	/** Select a shape (click on stroke or handle); null clears. */
	select(editor: ShapeEditor | null): void;
	/** The shape whose `chrome` <Draw> is currently rendering in its top layer
	 *  (select-to-front). Normally the selected shape; a shape renders its own
	 *  chrome inline exactly while it is NOT this one, so the chrome exists in
	 *  precisely one place at a time. */
	readonly hoisted: ShapeEditor | null;
	/** A handle drag has begun / ended. Between the two, <Draw> HOLDS the hoist
	 *  where it is: re-parenting chrome destroys and re-creates its nodes, and a
	 *  node that leaves the document loses the pointer capture trackPointer took
	 *  — after which a pointerup outside the window is never delivered and the
	 *  drag sticks to the cursor. A drag that begins by selecting an unselected
	 *  shape would do exactly that, so the hoist waits for the gesture to finish.
	 *  Nothing is lost by waiting: being in front only matters for GRABBING a
	 *  handle, and the handle is already grabbed. */
	beginGesture(): void;
	endGesture(): void;
	/** Path shapes register on mount so Draw can enumerate them (markup
	 *  order) for the "Copy changed" patch. Returns the unregister. */
	registerShape(editor: ShapeEditor): () => void;
	/** Rect/Ellipse register their Block-shaped box; Draw renders the editing
	 *  Block. Returns the unregister function. */
	registerBlock(shape: BlockShapeRegistration): () => void;
	/** A named path shape (Line/Curve/Arc) publishes its LIVE geometry here so
	 *  a `<Sprite path="name">` can ride it — one curve authored once, flight
	 *  and stroke always in step, in ADJUST and in source. Registration happens
	 *  at component INIT (not an effect) so it exists during prerender, which
	 *  gives it Connector's document-order rule: the sprite must come AFTER the
	 *  shape it references. Returns the unregister. */
	registerPathSource(name: string, get: () => PathShape): () => void;
	/** The named shape's current geometry, or null when nothing (yet) publishes
	 *  under that name — the sprite then renders nothing, like a Connector with
	 *  an unknown endpoint (never a broken flight). */
	pathSource(name: string): PathShape | null;
}

/** setContext/getContext key used by <Draw> and its children. */
export const DRAW_CONTEXT_KEY = Symbol('geekpresent-draw');

/** Provided by <Sprite> to any <Draw> nested inside it (a "group"), so that
 *  nested Draw only shows its editing chrome while the group is ISOLATED
 *  (entered via double-click). A top-level Draw sees no provider and edits
 *  normally in ADJUST. This keeps a flying group's inner handles/toolbar from
 *  lingering (or riding along with the moving box) when you aren't editing it. */
export interface SpriteIsolation {
	readonly entered: boolean;
}

/** setContext/getContext key for the Sprite→nested-Draw isolation gate. */
export const SPRITE_ISOLATION_KEY = Symbol('geekpresent-sprite-isolation');
