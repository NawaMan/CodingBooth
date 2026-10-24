<!--
  Block — an absolutely-positioned, editable wrapper in CANVAS pixels.

  Drop it around any slide content to pin that content at exact (x, y) with a
  fixed (width, height) in the deck's fixed coordinate space (1920x1080 landscape
  by default). Because SlideDeck scales the whole canvas with one CSS transform,
  these coordinates are authored once and scale with the slide in every display
  mode — no per-element math.

      <Block x={120} y={240} width={400} height={160} name="hero">
          <h2>Pinned content</h2>
      </Block>

  The wrapped content fills the box in both axes by default (a resize rubber-bands
  it) — pass `fill={false}` for pure positioning, where the content keeps its
  natural size. When ADJUST mode is ON, the wrapper grows a drag body + a bottom-right
  resize handle + an id/location bar carrying the send-to-back / bring-to-front
  / copy / delete buttons (Delete or Backspace deletes the selected Block too;
  Ctrl+C / Ctrl+V copies and pastes it, the copy a live second instance — both
  pending until SAVE, undoable with Ctrl+Z). Dragging updates x/y/width/height live, and the box publishes its updated
  OPENING tag — just
  `<Block … x={…} y={…} …>`, or `<Tag … />` for a self-closing wrapper (ImageBlock) —
  to the ADJUST change registry, so SAVE writes that one line back over the element's
  existing open tag (its children and closing tag stay put). (Snippet-emit, not live
  source rewrite: what SAVE writes is the element's own current props — robust and
  decoupled from the page text.)

  The drag math divides screen-pixel pointer deltas by the element's LIVE rendered
  scale (getBoundingClientRect().width / offsetWidth), so a drag tracks the cursor
  1:1 whether the deck is FITTED (fit-to-window) or SCALED to any zoom factor.

  Inside a <Group>, x/y/width/height are the group's local units: the Block draws
  at the group's mapping of them (and scales its content to match), drags in local
  units, and SAVEs them unchanged. See Group.svelte.
-->
<script lang="ts">
	import { adjustMode, canAdjust } from '$lib/stores/adjustMode';
	import { record } from '$lib/stores/adjustHistory';
	import { nextChangeId, reportChange, withdrawChange, type Geometry } from '$lib/stores/adjustChanges';
	import { copyBlock, pasteRequests, type PasteRequest } from '$lib/stores/blockClipboard';
	import { pasteBox, nextCopyName } from '$lib/adjust/pasteCore';
	import { selectedBlock, nextBlockId } from '$lib/stores/selectedBlock';
	import { reportAnchor, withdrawAnchor, blockAnchors } from '$lib/stores/blockAnchors';
	import { reportBlockZ, withdrawBlockZ, otherZValues } from '$lib/stores/blockOrder';
	import { frontZ, backZ } from '$lib/utils/stackingCore';
	import { trackPointer } from '$lib/utils/drag';
	import { guardStyle } from '$lib/adjust/styleGuardCore';
	import { getGroup } from '$lib/utils/groupContext';
	import {
		IDENTITY,
		NOTHING_HIDDEN,
		NOTHING_MOVED,
		compose,
		isHidden,
		isIdentity,
		moveFor,
		moveFrame,
		mapBox,
		morphName,
		visibleBox,
		type Frame,
		type HideState,
		type MoveMap
	} from '$lib/utils/groupCore';
	import { browser } from '$app/environment';
	import { onDestroy, onMount } from 'svelte';
	import { get, readable } from 'svelte/store';

	// Editing affordances only when the ADJUST control is BOTH available (dev or an
	// opted-in `?adjust` session) and switched on. canAdjust keeps the published
	// deck inert even if a stale adjustMode=true lingers in localStorage.
	$: editing = $canAdjust && $adjustMode;

	// Selection: grabbing a Block selects it, which floats it to the top so it (and
	// its grip) stays reachable when Blocks overlap. Transient — never written to
	// source (that's the persisted `z` prop below; the selection lift rides on top
	// of the authored z while editing, see `displayZ`). One selection at a time,
	// since every Block reads the same store.
	const blockId = nextBlockId();
	$: selected = editing && $selectedBlock === blockId;

	// Keys for the selection (only the selected Block listens, so exactly one handler
	// is live): Escape clears it, Delete / Backspace deletes the Block. A drag's own
	// Escape is handled by trackPointer's onCancel. Capture phase, so a delete is
	// swallowed before a page-level Backspace (AppendixPage's RETURN) can also act.
	function handleSelectionKey(event: KeyboardEvent) {
		if (event.key === 'Escape') {
			selectedBlock.set(null);
			return;
		}
		// Ctrl/Cmd+C copies the Block — unless the author has text selected, which
		// is an ordinary text copy and must stay one.
		if ((event.ctrlKey || event.metaKey) && !event.shiftKey && !event.altKey && event.key.toLowerCase() === 'c') {
			if (!deletable || isTyping(event.target) || window.getSelection()?.toString()) return;
			event.preventDefault();
			copyThis();
			return;
		}
		if (event.key !== 'Delete' && event.key !== 'Backspace') return;
		if (!deletable || isTyping(event.target)) return;
		event.preventDefault();
		event.stopImmediatePropagation();
		deleteBlock();
	}
	$: if (browser) {
		if (selected) window.addEventListener('keydown', handleSelectionKey, true);
		else window.removeEventListener('keydown', handleSelectionKey, true);
	}
	onDestroy(() => {
		if (browser) window.removeEventListener('keydown', handleSelectionKey, true);
		// Don't leave a destroyed Block as the selection target.
		if (selected) selectedBlock.set(null);
	});

	/** Top-left position and size, in canvas pixels. */
	export let x = 0;
	export let y = 0;
	export let width = 200;
	export let height = 120;
	/** Optional label, shown in edit mode and used in the copied snippet's comment. */
	export let name = '';
	/** Persistent stacking order for OVERLAPPING Blocks (CSS z-index in canvas
	    space). Author it by hand or with the ADJUST-mode Front / Back buttons, then
	    Copy / Save writes it back to source alongside x/y/width/height. Default 0
	    emits no z-index at all (Blocks keep painting in DOM order, `z-index: auto`,
	    so a grip can still float across a neighbour in ADJUST mode). The order shows
	    live in ADJUST too — the Block you're grabbing lifts to the top, every other
	    sits at its authored z — so a reorder is visible as you make it (see
	    `displayZ`). The Front/Back buttons keep z at or above 0 (a Block stays above
	    the slide's in-flow content); a negative z is honoured when hand-authored, for
	    a deliberate backdrop behind the text. */
	export let z = 0;
	/** Stretch the wrapped content to fill the box in both axes (the default), so a
	    resize rubber-bands it. A Block is a sizing frame and virtually every use
	    wants this — content that sets its own width/height still wins. Pass
	    `fill={false}` for pure positioning, where the content keeps its natural
	    size and the box is just a hit/anchor region. */
	export let fill = true;
	/** Snap step (canvas px) while dragging/resizing. 1 = freeform. */
	export let grid = 1;
	/** Lock the width:height ratio while resizing. A number sets an explicit ratio
	    (e.g. 16/9); `true` locks to the element's current shape at the drag's start;
	    `false`/null resizes freeform. Hold Alt while resizing to break the lock and
	    change the ratio freely. */
	export let aspect: number | boolean | null = null;
	/** Canvas bounds used to clamp dragging. Match the deck's width/height. */
	export let canvasWidth = 1920;
	export let canvasHeight = 1080;
	/** Where the element may go. 'canvas' (default) keeps it fully inside the
	    canvas; 'none' lets you drag/resize it past the edges — off-stage or bleeding
	    over an edge. (Undo/Ctrl+Z gets it back if it goes fully out of reach.) */
	export let bounds: 'canvas' | 'none' = 'canvas';
	/** Smallest size you can resize down to. */
	export let minSize = 24;
	/** Snippet shape for the emitted save-patch tag. A wrapper (e.g. ImageBlock)
	    overrides `tag` + `attrs` so the patch carries ITS tag, not the inner Block.
	    `attrs` is a pre-rendered attribute string (with a leading space); `selfClose`
	    emits `<Tag ... />` instead of an open/close pair with a slot placeholder. */
	export let tag = 'Block';
	export let attrs = '';
	export let selfClose = false;
	/** Report this wrapper's opening tag to the page-wide changed-tags
	    registry, so a Draw's "Copy changed" patch includes moved Blocks too.
	    Scaffolding wrappers opt out with false: KeyframeStudio's ghost stops
	    (their tags are meaningless as source) and Draw's own hosted
	    Rect/Ellipse blocks (Draw already reports those itself). */
	export let track = true;
	/** Optional draw-on reveal editor (a Draw Rect/Ellipse passes this via
	    <Draw>): when set, the toolbar grows time/delay fields for the wrapped
	    shape's self-draw. Plain Blocks leave it null. */
	export let drawEdit: import('$lib/draw/types').DrawOnEditor | null = null;
	/** Set only on a PASTED copy (rendered by its source Block, never authored):
	    the source Block's name and mount-time geometry, which SAVE uses to find
	    the element to duplicate. */
	export let pasteOf: { name: string; before: Geometry } | null = null;
	/** On a pasted copy: the blockId of the source Block that renders it, so a
	    copy of the copy is rendered by — and saved from — that same source. */
	export let pasteHost: number | null = null;
	/** The route file this tag was written in. Never authored: in `pnpm dev` the
	    source-stamp plugin adds it to every Block-family tag (adjust/sourceTag.ts),
	    so SAVE can patch a Block that lives in a component — a shared scene —
	    instead of looking for it in the slide. Empty in a build. */
	export let __file = '';

	/** Inline style for the root element, applied last so it wins — EXCEPT for the
	    properties this Block writes itself (left/top/width/height/inset/position),
	    which are reserved: the x/y/width/height props own the box. A geometry
	    declaration here is stripped before the style is applied, so what you see
	    always matches the props and a ADJUST drag actually moves the box. Your
	    source is left alone; the dead declaration is just called out in the ADJUST
	    chrome. See adjust/styleGuardCore.ts. */
	export let style: string = '';
	/** The `style` of the shape a HOSTED Block is editing (a Draw Rect/Ellipse).
	    That style is applied — and guarded — by the shape itself, on its own SVG
	    element; this Block never renders or emits it. It is passed here for ONE
	    reason: the badge belongs on the box you actually drag. Plain Blocks leave
	    it empty and guard their own `style` instead. */
	export let hostStyle: string = '';
	/** DOM id for the root element. */
	export let id: string = '';
	/** Extra class(es) for the root element. NOTE: a slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS (global.css / roles.css / a
	    :global(...) block) or a utility class. See AGENTS.md. */
	let klass: string = '';
	export { klass as class };

	let el: HTMLElement;

	// Inside a <Group>, x/y/width/height are the group's LOCAL units and `frame`
	// maps them onto the canvas; `box` is where this Block is actually drawn.
	// Outside any group the frame is the identity and box === the props, so a
	// plain Block renders exactly as before. Drags, SAVE and the readout stay in
	// local units (the numbers in source); the anchor and the DOM are in canvas.
	const group = getGroup();
	const groupFrame = group?.frame ?? readable<Frame>(IDENTITY);
	// Moved on this slide by the group's `move` (by name): one more map, about the
	// Block's own centre, between its source numbers and the group's frame. The
	// source numbers — what a drag changes and SAVE writes — stay where it is drawn.
	const groupMoves = group?.moves ?? readable<MoveMap>(NOTHING_MOVED);
	$: ownMove = moveFrame(moveFor($groupMoves, name), { x, y, width, height });
	$: moved = !isIdentity(ownMove);
	$: frame = moved ? compose($groupFrame, ownMove) : $groupFrame;
	$: scaled = frame.s !== 1;
	$: box = mapBox(frame, { x, y, width, height });
	// The canvas, in local units: what bounds="canvas" clamps to.
	$: stage = visibleBox(frame, canvasWidth, canvasHeight);
	// The group's per-slide cast and morph names (see Group's `hide` / `morph`).
	const groupHidden = group?.hidden ?? readable<HideState>(NOTHING_HIDDEN);
	const groupMorph = group?.morph ?? readable<string | null>(null);
	$: concealed = !!group && isHidden($groupHidden, name);
	$: vtName = morphName($groupMorph, name);
	// Glide (Group `glide`): a camera change within the slide animates instead of
	// jumping. Not while editing — a drag must track the pointer, not chase it.
	// Nor before the first frame is painted: a slide that opens part-way through
	// a build (paged back into, see Steps) sets its camera during mount, and that
	// is where it starts, not something to glide to.
	const groupGlide = group?.glide ?? readable(0);
	let settled = false;
	onMount(() => {
		if (!group) return;
		let raf = requestAnimationFrame(() => {
			raf = requestAnimationFrame(() => (settled = true));
		});
		return () => cancelAnimationFrame(raf);
	});
	$: gliding = settled && $groupGlide > 0 && !editing;
	// The content layer keeps its transform even at 1× while gliding, so a zoom
	// back to 1:1 animates down to it rather than snapping when `scaled` flips.
	$: zoomLayer = scaled || gliding;

	const snap =(n: number) => (grid > 1 ? Math.round(n / grid) * grid : Math.round(n));
	const clamp = (n: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, n));

	// One pointer gesture, parameterised by which corner(s) it moves. `move` shifts
	// x/y; `size` grows width/height. Both at once = a drag; size-only = resize.
	type Mode = 'move' | 'size';
	let dragging: Mode | null = null;

	function startDrag(mode: Mode, event: PointerEvent) {
		if (!editing) return;
		event.preventDefault();
		event.stopPropagation();
		// Grabbing the body or the grip selects this Block (brings it to the top so
		// the gesture — and future clicks — land on it, not a Block overlapping it).
		selectedBlock.set(blockId);
		dragging = mode;

		const startX = x;
		const startY = y;
		const startW = width;
		const startH = height;
		// Ratio to hold while resizing: explicit number, or the current shape when
		// `aspect` is `true`. null = freeform.
		const ratio = typeof aspect === 'number' ? aspect : aspect === true ? startW / startH : null;

		const free = bounds === 'none';
		// Local bounds and units, fixed for the gesture (a camera doesn't move mid-drag).
		const s = $groupFrame.s;
		// A move's scale is about the centre: a resize then shows on the dragged
		// edge at (1 + scale) / 2 of its size change, so the pointer is divided by that.
		const grow = (1 + ownMove.s) / 2;
		const right = stage.x + stage.width;
		const bottom = stage.y + stage.height;
		// The shared helper measures the live rendered scale from `el`, captures
		// the pointer, and streams canvas-px deltas until pointerup / Esc — which
		// the group's zoom turns into local units.
		trackPointer(event, {
			scaleFrom: el,
			onMove: (cdx, cdy, e) => {
				const dx = cdx / s / (mode === 'move' ? 1 : grow);
				const dy = cdy / s / (mode === 'move' ? 1 : grow);
				if (mode === 'move') {
					// Hold Shift to lock the move to a single axis — whichever the pointer
					// has travelled furthest along, from the drag's START. Re-evaluated on
					// every move (like the aspect-lock below), so swinging the drag past the
					// diagonal — or pressing/releasing Shift mid-gesture — switches the
					// locked axis live. A tie keeps the horizontal, matching line ~192.
					let mx = dx;
					let my = dy;
					if (e.shiftKey) {
						if (Math.abs(dx) >= Math.abs(dy)) my = 0;
						else mx = 0;
					}
					x = snap(free ? startX + mx : clamp(startX + mx, stage.x, right - width));
					y = snap(free ? startY + my : clamp(startY + my, stage.y, bottom - height));
				} else if (ratio && !e.altKey) {
					// Aspect-locked: drive from the axis the pointer moved most, derive the
					// other from `ratio`, then clamp to canvas + minSize without skewing —
					// whichever bound binds first wins and the partner follows the ratio.
					// Hold Alt to break the lock and resize freeform (see the else below).
					let w, h;
					if (Math.abs(dx) >= Math.abs(dy)) {
						w = startW + dx;
						h = w / ratio;
					} else {
						h = startH + dy;
						w = h * ratio;
					}
					if (w < minSize) { w = minSize; h = w / ratio; }
					if (h < minSize) { h = minSize; w = h * ratio; }
					if (!free && x + w > right)  { w = right  - x; h = w / ratio; }
					if (!free && y + h > bottom) { h = bottom - y; w = h * ratio; }
					width  = snap(w);
					height = snap(h);
				} else {
					width = clamp(snap(startW + dx), minSize, free ? Infinity : right - x);
					height = clamp(snap(startH + dy), minSize, free ? Infinity : bottom - y);
				}
			},
			// On commit, record the net change (before → after) for global undo/redo —
			// but only if the gesture actually moved something, so a stray click that
			// doesn't drag never clutters the history.
			onEnd: () => {
				dragging = null;
				const before = { x: startX, y: startY, w: startW, h: startH };
				const after = { x, y, w: width, h: height };
				if (before.x === after.x && before.y === after.y && before.w === after.w && before.h === after.h) return;
				record({
					undo: () => { x = before.x; y = before.y; width = before.w; height = before.h; },
					redo: () => { x = after.x;  y = after.y;  width = after.w;  height = after.h; },
				});
			},
			// Esc cancels the in-progress gesture: snap every value back to where it
			// was when the drag began.
			onCancel: () => {
				dragging = null;
				x = startX; y = startY; width = startW; height = startH;
			}
		});
	}

	// Bring-to-front / send-to-back: set `z` above/below every other Block on the
	// slide (frontZ/backZ read the sibling z's from the blockOrder registry). The
	// pure core is a no-op when this Block is already the extreme, so `setZ` only
	// records an undo step when the value actually moves.
	function setZ(next: number) {
		if (next === z) return;
		const before = z;
		const after = next;
		z = next;
		record({
			undo: () => { z = before; },
			redo: () => { z = after; },
		});
	}
	const bringToFront = () => setZ(frontZ(z, otherZValues(blockId)));
	// Send-to-back is FLOORED at 0: a Block shares one stacking context with the
	// slide's in-flow content (text, a code box), and a NEGATIVE z-index paints
	// behind that flow — so "send to back" against default (z=0) Blocks would drop
	// this one behind the slide's body, not just behind its sibling Blocks. Flooring
	// keeps every Block at or above the content layer (a z=0 positioned Block already
	// sits above in-flow content). A deliberate backdrop-behind-text is still one
	// hand-authored `z={-1}` away — the button just won't produce that by surprise.
	const sendToBack = () => setZ(Math.max(0, backZ(z, otherZValues(blockId))));

	// Delete: a PENDING removal, like every other ADJUST edit. The Block hides (and
	// drops its anchor, so arrows to it vanish), goes into the undo history, and
	// reports itself `removed` so SAVE cuts the whole element out of the source —
	// see patchSource's REMOVE mode. Only a tracked Block: a hosted Draw Rect/Ellipse
	// or a KeyframeStudio ghost is not an element of the slide's own source.
	let removed = false;
	$: deletable = track;
	function deleteBlock() {
		if (!deletable || removed) return;
		removed = true;
		selectedBlock.set(null);
		record({
			undo: () => { removed = false; },
			redo: () => { removed = true; },
		});
	}
	// Copy / paste. Copy hands the clipboard this Block's box and the id of the
	// SOURCE Block (itself, or the one that rendered this copy). Paste asks that
	// source Block to render one more live instance of itself — see `copies` and
	// the {#each} at the end of the markup. Pending until SAVE, like a delete.
	let copied = false;
	let copiedTimer: ReturnType<typeof setTimeout> | undefined;
	function copyThis() {
		if (!deletable || removed) return;
		copyBlock({ host: pasteHost ?? blockId, x, y, width, height, z, baseName: pasteOf ? pasteOf.name : name });
		copied = true;
		clearTimeout(copiedTimer);
		copiedTimer = setTimeout(() => (copied = false), 900);
	}
	onDestroy(() => clearTimeout(copiedTimer));

	interface PastedCopy { key: number; name: string; x: number; y: number; width: number; height: number; z: number }
	let copies: PastedCopy[] = [];
	let lastPaste = 0;
	function takePaste(req: PasteRequest | null) {
		if (!req || req.host !== blockId || req.id <= lastPaste) return;
		lastPaste = req.id;
		// The canvas clamp assumes a stage at the origin, so inside a mapped group
		// the copy just cascades unclamped (the drag that follows clamps it).
		const plain = isIdentity($groupFrame);
		const landed = pasteBox(req, req.n, bounds === 'canvas' && plain ? { width: canvasWidth, height: canvasHeight } : null);
		const copy = { key: req.id, name: nextCopyName(req.baseName, get(blockAnchors).keys()), ...landed, z: req.z };
		copies = [...copies, copy];
		record({
			undo: () => { copies = copies.filter((c) => c !== copy); },
			redo: () => { copies = [...copies, copy]; },
		});
	}
	// Only a source-backed Block hosts copies; a copy forwards to its host instead.
	$: if (browser && deletable && !pasteOf) takePaste($pasteRequests);
	// A fresh copy arrives selected, ready to drag.
	onMount(() => { if (pasteOf) selectedBlock.set(blockId); });

	function isTyping(target: EventTarget | null): boolean {
		const node = target as HTMLElement | null;
		return !!node && (node.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(node.tagName));
	}

	// Publish this Block's live z so its siblings' Front/Back can order against it.
	// Browser-only: purely a ADJUST-mode aid, and SSR must not touch module state
	// that outlives one render (unlike blockAnchors, which a Connector needs on the
	// server).
	$: if (browser) {
		if (removed) withdrawBlockZ(blockId);
		else reportBlockZ(blockId, z);
	}
	onDestroy(() => { if (browser) withdrawBlockZ(blockId); });

	// When NOT editing, a bounds="none" element that bleeds past the canvas should
	// look clipped to the canvas edge (the "stage"), not spill into the letterbox.
	// Clip just THIS element to the canvas rectangle, computed in its own local
	// coords (local L maps to canvas x+L, so the visible band is -x … canvasWidth-x).
	// While editing, no clip — the off-stage part (and its handles) stays grabbable.
	// Canvas units throughout (`box`): the clip is about the stage, not the group.
	$: clipPath =
		!editing && bounds === 'none'
			? `inset(${Math.max(0, -box.y)}px ${Math.max(0, box.x + box.width - canvasWidth)}px` +
			  ` ${Math.max(0, box.y + box.height - canvasHeight)}px ${Math.max(0, -box.x)}px)`
			: 'none';

	// The applied z-index folds the AUTHOR z and the transient editing lift into
	// ONE inline value, so the author's stacking shows in real time while ADJUST is
	// on (dragging a Block over/under others reflects the order you're authoring)
	// without an inline value fighting a stylesheet class on specificity.
	//
	//   * Presentation (not editing): the author z, or `auto` at z=0 — so untouched
	//     Blocks keep painting in DOM order and create no stacking context.
	//   * Editing: the Block you're touching floats to the top for grabbability —
	//     dragging > selected > hovered, in a band just under the in-canvas chrome
	//     (KeyframeStudio panel / ghosts sit at z 50). Every OTHER editing Block
	//     shows its author z live, clamped below that lift band so the one you grab
	//     always wins; z=0 stays `auto` (no stacking context), so a grip can still
	//     float across a neighbour — the common all-default slide is unchanged.
	let hovered = false;
	// Lift band (all < 50, the KeyframeStudio panel/ghost layer). The author z shown
	// for a non-grabbed Block is capped one below the lowest lift so a grabbed Block
	// is always on top. Real Front/Back values are single digits, so the cap only
	// ever bites a deliberately huge hand-authored z — and even then, only in ADJUST.
	const Z_HOVER = 44;
	const Z_SELECTED = 46;
	const Z_ACTIVE = 48;
	const Z_AUTHOR_CAP = 42;
	$: displayZ = editing
		? dragging
			? Z_ACTIVE
			: selected
				? Z_SELECTED
				: hovered
					? Z_HOVER
					: z
						? Math.min(Math.round(z), Z_AUTHOR_CAP)
						: null
		: z
			? Math.round(z)
			: null;
	$: zStyle = displayZ == null ? '' : `z-index:${displayZ};`;

	$: aspectAttr = typeof aspect === 'number' ? ` aspect={${aspect}}` : aspect === true ? ' aspect' : '';
	// z is emitted only when non-zero: the default layer leaves no z-index in
	// source, so unrelated Blocks stay `z-index: auto` and a copied tag stays clean.
	$: zAttr = z ? ` z={${Math.round(z)}}` : '';

	// The author's own pass-through props. ADJUST neither reads nor edits them — but
	// SAVE replaces the WHOLE opening tag, so anything not emitted here is DELETED
	// from the author's source the moment they drag the Block. They are echoed back
	// verbatim, and a value carrying a double quote is single-quoted so the line still
	// parses when it is pasted in.
	// (A HOSTED Block — the editing wrapper a Draw shape mounts, `tag="Rect"` — receives
	// none of these: the shape emits its own via draw/editing.ts's sharedAttrs, into
	// `attrs`. So the two paths never double-emit.)
	const quoted = (n: string, v: string) => (v.includes('"') ? ` ${n}='${v}'` : ` ${n}="${v}"`);
	// NOTE: the ORIGINAL `style` is echoed, not the guarded one. Reserving a
	// property changes what RENDERS, never what the author wrote — SAVE hands
	// the source string back byte-for-byte, and a stray `left: 40px` survives in
	// source as an inert declaration for the author to delete. ADJUST never edits
	// inside an author's attribute value.
	$: passAttrs =
		(id ? quoted('id', id) : '') + (klass ? quoted('class', klass) : '') + (style ? quoted('style', style) : '');

	// The props own the geometry: strip any left/top/width/height/inset/position the
	// author's `style` declares, so it cannot cancel the box this Block is drawing.
	// Without this, the two land in ONE inline declaration block and the author's
	// wins — ADJUST then drags a box that cannot move (see adjust/styleGuardCore.ts).
	// Cosmetics (stroke, dash, colour, a decorative rotate) pass through untouched
	// and still win, exactly as before.
	$: guard = guardStyle(style);
	// A hosted Block (Draw's Rect/Ellipse) doesn't render the shape's style — the
	// shape does — but the badge belongs here, on the box you grab.
	$: hostGuard = guardStyle(hostStyle);
	$: ignoredGeometry = [...guard.reserved, ...hostGuard.reserved];
	$: displacedBy = [...guard.offsets, ...hostGuard.offsets];
	$: openTag =
		`<${tag}${name ? ` name="${name}"` : ''}${attrs}${passAttrs} x={${Math.round(x)}} y={${Math.round(y)}}` +
		` width={${Math.round(width)}} height={${Math.round(height)}}${aspectAttr}${zAttr}`;
	// The save-patch tag is only the OPENING tag with the live geometry — that's the
	// single line SAVE writes over your element's existing open tag to update its position.
	// (A self-closing wrapper like ImageBlock has no children, so it stays `<Tag … />`.)
	$: snippet = selfClose ? `${openTag} />` : `${openTag}>`;

	// The mount-time tag is the SOURCE form; live-vs-initial drives this
	// wrapper's entry in the page-wide changed-tags registry (Draw's
	// "Copy changed" OLD/NEW patch). Browser-only: SSR must not touch the
	// module-level registry.
	const changeId = nextChangeId();
	const initial = { x, y, width, height, z };
	// What a copy of THIS Block needs to find it in source at SAVE.
	const sourceOf = {
		name,
		before: {
			x: Math.round(initial.x),
			y: Math.round(initial.y),
			width: Math.round(initial.width),
			height: Math.round(initial.height),
			z: Math.round(initial.z),
		},
	};
	$: initialZAttr = initial.z ? ` z={${Math.round(initial.z)}}` : '';
	$: initialOpenTag =
		`<${tag}${name ? ` name="${name}"` : ''}${attrs}${passAttrs} x={${Math.round(initial.x)}} y={${Math.round(initial.y)}}` +
		` width={${Math.round(initial.width)}} height={${Math.round(initial.height)}}${aspectAttr}${initialZAttr}`;
	$: initialSnippet = selfClose ? `${initialOpenTag} />` : `${initialOpenTag}>`;
	$: if (browser && track)
		reportChange({
			id: changeId,
			kind: tag,
			name,
			file: __file || undefined,
			// A pasted copy is dirty for as long as it exists — it is not in source
			// yet. Deleting it (or undoing the paste) leaves nothing to save.
			dirty: pasteOf ? !removed : removed || snippet !== initialSnippet,
			removed: pasteOf ? false : removed,
			pasteOf: pasteOf ?? undefined,
			oldTag: pasteOf
				? `(new: a copy of ${pasteOf.name ? `"${pasteOf.name}"` : `the ${tag} at ${pasteOf.before.x},${pasteOf.before.y}`} — insert it after that element)`
				: initialSnippet,
			newTag: removed ? '(deleted: remove this element, its children and closing tag)' : snippet,
			// Structured geometry for the dev "Save" endpoint: `before` matches the
			// source, `after` is what gets written.
			before: {
				x: Math.round(initial.x),
				y: Math.round(initial.y),
				width: Math.round(initial.width),
				height: Math.round(initial.height),
				z: Math.round(initial.z),
			},
			after: {
				x: Math.round(x),
				y: Math.round(y),
				width: Math.round(width),
				height: Math.round(height),
				z: Math.round(z),
			},
		});
	onDestroy(() => withdrawChange(changeId));

	// Publish a NAMED block's live box to the page-wide anchor registry, so a
	// <Connector from="…" to="…"> can route an arrow between boxes by name and
	// keep following them as they're dragged. Unlike reportChange above this is
	// NOT browser-gated: a prerendered slide must ship its connectors drawn.
	// `track={false}` wrappers (Draw's hosted Rect/Ellipse blocks, KeyframeStudio
	// ghosts) opt out — they only exist in ADJUST mode, so an anchor on them
	// would appear and vanish with the toggle.
	// Plain object, not a `let`: mutating a field must not itself invalidate the
	// reactive statement that writes it (that would be a self-triggering cycle).
	const anchor = { name: '' };
	$: if (track && name && !removed) {
		// A renamed Block must not leave its old name behind in the registry.
		if (anchor.name && anchor.name !== name) withdrawAnchor(anchor.name);
		anchor.name = name;
		// Canvas coordinates — where the box is drawn — so a Connector or Spotlight
		// outside the group still finds it.
		reportAnchor(name, box);
	}
	// A deleted Block takes its anchor with it; undo re-reports through the block above.
	$: if (removed && anchor.name) {
		withdrawAnchor(anchor.name);
		anchor.name = '';
	}
	onDestroy(() => withdrawAnchor(anchor.name));

	// Inside a group, a named Block reports its LOCAL box there too, so the group's
	// camera can `fit` / `focus` on it by name.
	const memberKey = {};
	// Where it is on THIS slide (moved), so a camera aims at the part, not its old spot.
	$: if (group) {
		if (track && name && !removed) group.register(memberKey, name, mapBox(ownMove, { x, y, width, height }));
		else group.withdraw(memberKey);
	}
	onDestroy(() => group?.withdraw(memberKey));
</script>

<!-- svelte-ignore a11y-no-static-element-interactions a11y-no-noninteractive-element-interactions -->
<div
	class="movable {klass}"
	class:editing={editing}
	class:selected={selected}
	class:active={dragging}
	class:removed={removed}
	class:pasted={!!pasteOf}
	class:concealed
	class:gliding
	id={id || undefined}
	data-gp-morph={vtName ?? undefined}
	bind:this={el}
	style="left:{box.x}px; top:{box.y}px; width:{box.width}px; height:{box.height}px; clip-path:{clipPath}; {gliding ? `--gp-glide:${$groupGlide}s;` : ''} {zStyle} {guard.safe}"
	on:pointerdown={(e) => startDrag('move', e)}
	on:pointerenter={() => (hovered = true)}
	on:pointerleave={() => (hovered = false)}
>
	<!-- Zoomed by a group: the content lays out at its LOCAL size and is scaled up
	     as a whole (text, borders, picture), inside the real-size box. The
	     transform sits on this inner layer, never on the Block itself, so a
	     View-Transition snapshot of the Block is the true box, painted crisp. -->
	<div
		class="fill-layer"
		class:loose={!fill}
		class:scaled={zoomLayer}
		style={zoomLayer ? `width:${width}px; height:${height}px; transform:scale(${frame.s});` : undefined}
	><slot /></div>

	{#if editing}
		<div class="readout">
			{name ? name + ' · ' : ''}{Math.round(x)},{Math.round(y)} · {Math.round(width)}×{Math.round(height)}{z ? ' · z' + Math.round(z) : ''}{scaled ? ' · ×' + +frame.s.toFixed(3) : ''}{moved ? ' · moved' : ''}
			<button
				class="zbtn" type="button" title="Send to back" aria-label="Send to back"
				on:pointerdown|stopPropagation on:click|stopPropagation={sendToBack}
			>⤓</button>
			<button
				class="zbtn" type="button" title="Bring to front" aria-label="Bring to front"
				on:pointerdown|stopPropagation on:click|stopPropagation={bringToFront}
			>⤒</button>
			{#if deletable}
				<button
					class="zbtn" type="button" title="Copy (Ctrl+C) — paste with Ctrl+V; SAVE writes the copy"
					aria-label="Copy block"
					on:pointerdown|stopPropagation on:click|stopPropagation={copyThis}
				>{copied ? '✓' : '⧉'}</button>
				<button
					class="zbtn delete" type="button" title="Delete (Del) — undo with Ctrl+Z; SAVE writes it"
					aria-label="Delete block"
					on:pointerdown|stopPropagation on:click|stopPropagation={deleteBlock}
				>✕</button>
			{/if}
		</div>
		{#if ignoredGeometry.length || displacedBy.length}
			<!-- The style/geometry collision, said out loud — ADJUST-mode only, so it
			     can never reach a published deck. Not a blocker: the drag works fine
			     (that is the point of reserving the properties). This exists so an
			     author who wrote `style="left: 40px"` learns why it does nothing,
			     instead of concluding ADJUST is broken. -->
			<div class="style-warn" role="status">
				{#if ignoredGeometry.length}
					<span>⚠ <code>style</code> sets {ignoredGeometry.join(', ')} — ignored, the {ignoredGeometry.length > 1 ? 'props win' : 'prop wins'}</span>
				{/if}
				{#if displacedBy.length}
					<span>⚠ <code>{displacedBy.join(', ')}</code> shifts this away from its x/y — anchors point at the box, not the pixels</span>
				{/if}
			</div>
		{/if}
		{#if drawEdit}
			<!-- Draw-on reveal editor for a wrapped Draw shape (Rect/Ellipse):
			     retime the self-draw + its delay. stopPropagation so editing the
			     fields doesn't start a Block drag. -->
			<!-- svelte-ignore a11y-no-static-element-interactions -->
			<div class="drawon" on:pointerdown|stopPropagation>
				<span>draw</span>
				<input
					type="number" min="0" step="0.1"
					value={drawEdit.seconds}
					aria-label="draw-on seconds"
					on:change={(e) => drawEdit.setSeconds(+e.currentTarget.value)}
				/><span>s +</span>
				<input
					type="number" min="0" step="0.1"
					value={drawEdit.delay}
					aria-label="draw-on delay seconds"
					on:change={(e) => drawEdit.setDelay(+e.currentTarget.value)}
				/><span>s</span>
			</div>
		{/if}
		<!-- svelte-ignore a11y-no-static-element-interactions -->
		<div class="handle" on:pointerdown={(e) => startDrag('size', e)}></div>
	{/if}
</div>

<!-- Pasted copies: further live instances of this same Block, slot and all, as
     siblings (so they position against the same canvas). Never authored — they
     exist until SAVE writes them into source, or undo takes them away. -->
{#each copies as c (c.key)}
	<svelte:self
		name={c.name} x={c.x} y={c.y} width={c.width} height={c.height} z={c.z}
		{fill} {grid} {aspect} {canvasWidth} {canvasHeight} {bounds} {minSize}
		{tag} {attrs} {selfClose} {track} {style} class={klass}
		pasteOf={sourceOf} pasteHost={blockId} {__file}
	><slot /></svelte:self>
{/each}

<style>
	.movable {
		position: absolute;
		box-sizing: border-box;
	}
	/* Deleted in ADJUST, pending SAVE. Hidden rather than unmounted, so undo brings
	   the content back exactly as it was (a Monaco editor, a video's position…). */
	.movable.removed {
		display: none;
	}
	/* Hidden by its group on this slide (Group `hide`). Visibility, not display:
	   the box stays, so a morph still pairs it and fades it as it glides. In
	   ADJUST it is faint instead — there to grab, plainly not on the slide. */
	.movable.concealed {
		visibility: hidden;
	}
	.movable.concealed.editing {
		visibility: visible;
		opacity: 0.3;
	}
	/* Gliding (Group `glide`): the box and the content's zoom animate together, on
	   the same curve as the deck's morphs. A part leaving the shot fades out as it
	   moves; visibility flips at the END of the fade (and at the start of a fade
	   in), so a hidden part never takes a click mid-way. */
	.movable.gliding {
		--gp-glide-ease: cubic-bezier(0.65, 0, 0.35, 1);
		transition:
			left var(--gp-glide) var(--gp-glide-ease),
			top var(--gp-glide) var(--gp-glide-ease),
			width var(--gp-glide) var(--gp-glide-ease),
			height var(--gp-glide) var(--gp-glide-ease),
			opacity var(--gp-glide) var(--gp-glide-ease),
			visibility var(--gp-glide) step-end;
	}
	.movable.gliding .fill-layer {
		transition: transform var(--gp-glide) var(--gp-glide-ease);
	}
	.movable.gliding.concealed {
		opacity: 0;
	}
	.movable.gliding:not(.concealed) {
		transition-timing-function: var(--gp-glide-ease), var(--gp-glide-ease), var(--gp-glide-ease),
			var(--gp-glide-ease), var(--gp-glide-ease), step-start;
	}
	@media (prefers-reduced-motion: reduce) {
		.movable.gliding,
		.movable.gliding .fill-layer {
			transition: none;
		}
	}

	/* The wrapped content fills the box by default: a Block is a sizing frame, and
	   every real usage wants its content to take the whole box so a resize
	   rubber-bands it. A single grid cell spanning the box stretches the child in
	   both axes (grid's default stretch alignment); content that sets its own
	   width/height overrides the stretch. `fill={false}` → `display:contents`, so
	   the slot content behaves as a plain flow child (its natural size), exactly
	   as before this layer existed. */
	.fill-layer {
		position: absolute;
		inset: 0;
		display: grid;
		grid-template: 1fr / 1fr;
	}
	.fill-layer.loose {
		position: static;
		display: contents;
	}
	/* Scaled by a group: laid out at the local size (inline width/height), then
	   zoomed from the top-left corner to fill the real box. A loose layer can't
	   stay `display: contents` here — a transform needs a box to apply to. */
	.fill-layer.scaled {
		inset: auto;
		left: 0;
		top: 0;
		transform-origin: 0 0;
	}
	.fill-layer.loose.scaled {
		position: absolute;
		display: block;
	}
	/* In edit mode the wrapper becomes a manipulable object: a dashed outline marks
	   its bounds, the body is a move target, and text selection is suppressed so a
	   drag never turns into a text highlight. */
	.movable.editing {
		outline: 1.5px dashed var(--ctrl-strong-bg, #2980b9);
		outline-offset: 2px;
		cursor: move;
		user-select: none;
		touch-action: none;
	}
	.movable.active {
		outline-style: solid;
	}
	/* A pasted copy is not in source until SAVE: warm outline, so it reads as new. */
	.movable.editing.pasted {
		outline-color: var(--adjust-warn-bg, #f0a33e);
	}
	/* A selected Block reads as the active object: a solid (not dashed) outline. */
	.movable.selected {
		outline-style: solid;
	}

	/* Grip + id/location bar float above other Blocks' bodies (z 35), so you can click
	   to select — or hit Front/Back — even when overlapped. This is the ONE stacking
	   value still in CSS; the wrapper's own z-index (the author z plus the
	   drag/select/hover lift) is computed inline (see `displayZ`), because it now
	   carries the author's real-time stacking order and a class rule could not.
	   All lift values sit below the in-canvas KeyframeStudio panel (z 50) and the
	   Box modal (z 1000). An idle or z=0 Block keeps z-index:auto (no stacking
	   context), so a grip can still float across a neighbour. */
	.movable.editing .handle,
	.movable.editing .readout {
		z-index: 35;
	}

	/* The id/location bar: name · x,y · w×h · z, with the stacking buttons folded in
	   on its right (⤓ send-to-back / ⤒ bring-to-front). One flex pill: the bar itself
	   is pointer-events:none (a drag can start on the text), and the buttons re-enable
	   pointer events (see `.readout .zbtn`). */
	.movable .readout {
		position: absolute;
		left: 0;
		top: -1.7em;
		display: inline-flex;
		align-items: center;
		gap: 0.2em;
		font-size: 0.55em;
		font-family: 'Fira Code', monospace;
		white-space: nowrap;
		padding: 0 0.2em 0 0.4em;
		background: var(--ctrl-strong-bg, #2980b9);
		color: var(--on-accent, #ffffff);
		border-radius: 3px;
		pointer-events: none;
	}

	/* The style/geometry collision badge — the TOP row of the chrome above the box:
	   badge, then the id/location bar, then the box itself.
	   Two things this has to get right, both learned the hard way:
	   1. UNIT BASIS. The offset is in the BLOCK's font-size, not the badge's (this row
	      sets no font-size — the pills below carry the 0.55em), so `bottom: 100% + 1.9em`
	      clears the id/location bar (which sits at `top: -1.7em` in its OWN 0.55em) with
	      room to spare, instead of landing on top of it.
	   2. STACKING. Above the bar/handle band (35), so a caution is never buried by the
	      buttons it sits beside — still well under the KeyframeStudio panel (50).
	   Bottom-anchored, so a second line grows upward rather than down into the bar.
	   Warm, not blue: a caution, not a status. pointer-events:none so it can never eat
	   a drag that starts near the top edge of the box. */
	.movable .style-warn {
		position: absolute;
		left: 0;
		bottom: calc(100% + 1.9em);
		z-index: 36;
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: 2px;
		pointer-events: none;
	}
	.movable .style-warn span {
		font-size: 0.55em;
		font-family: 'Fira Code', monospace;
		white-space: nowrap;
		padding: 0 0.4em;
		background: var(--adjust-warn-bg, #f0a33e);
		color: var(--adjust-warn-fg, #1a1a1a);
		border-radius: 3px;
	}
	.movable .style-warn code {
		font-family: inherit;
		font-weight: 700;
	}

	/* Draw-on reveal editor (only present for wrapped Draw Rect/Ellipse):
	   a compact row hanging under the box. */
	.movable .drawon {
		position: absolute;
		left: 0;
		top: 100%;
		margin-top: 4px;
		display: inline-flex;
		align-items: center;
		gap: 0.25em;
		font-size: 0.55em;
		font-family: 'Fira Code', monospace;
		white-space: nowrap;
		padding: 0.15em 0.4em;
		background: rgba(18, 18, 18, 0.92);
		border: 1px solid var(--ctrl-strong-bg, #2980b9);
		border-radius: 4px;
		color: #9aa7b0;
		touch-action: none;
	}
	.movable .drawon input {
		width: 3.4em;
		font-family: 'Fira Code', monospace;
		font-size: 1em;
		color: #cfe3f2;
		background: var(--ctrl-bg, #181818);
		border: 1px solid var(--ctrl-strong-bg, #2980b9);
		border-radius: 4px;
		padding: 0.1em 0.3em;
	}

	/* Bring-to-front / send-to-back, folded into the id/location bar. Glyph buttons
	   in the deck's control palette (no new role tokens: dev-only ADJUST chrome).
	   They re-enable the pointer events the bar switches off, and read as chips on
	   the bar via a translucent fill that brightens on hover. */
	.movable .readout .zbtn {
		pointer-events: auto;
		display: inline-flex;
		align-items: center;
		font-size: 1.15em;
		line-height: 1;
		cursor: pointer;
		padding: 0.1em 0.25em;
		border: 0;
		border-radius: 2px;
		background: rgba(255, 255, 255, 0.14);
		color: inherit;
	}
	.movable .readout .zbtn:hover {
		background: rgba(255, 255, 255, 0.3);
	}
	.movable .readout .zbtn.delete:hover {
		background: var(--adjust-warn-bg, #f0a33e);
		color: var(--adjust-warn-fg, #1a1a1a);
	}

	/* Bottom-right resize grip. */
	.movable .handle {
		position: absolute;
		right: -6px;
		bottom: -6px;
		width: 14px;
		height: 14px;
		border-radius: 3px;
		background: var(--ctrl-strong-bg, #2980b9);
		border: 1.5px solid var(--on-accent, #ffffff);
		cursor: nwse-resize;
		touch-action: none;
	}
</style>
