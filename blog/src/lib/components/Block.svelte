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
  buttons. Dragging updates x/y/width/height live, and the box publishes its updated
  OPENING tag — just
  `<Block … x={…} y={…} …>`, or `<Tag … />` for a self-closing wrapper (ImageBlock) —
  to the ADJUST change registry, so SAVE writes that one line back over the element's
  existing open tag (its children and closing tag stay put). (Snippet-emit, not live
  source rewrite: what SAVE writes is the element's own current props — robust and
  decoupled from the page text.)

  The drag math divides screen-pixel pointer deltas by the element's LIVE rendered
  scale (getBoundingClientRect().width / offsetWidth), so a drag tracks the cursor
  1:1 whether the deck is FITTED (fit-to-window) or SCALED to any zoom factor.
-->
<script lang="ts">
	import { adjustMode, canAdjust } from '$lib/stores/adjustMode';
	import { record } from '$lib/stores/adjustHistory';
	import { nextChangeId, reportChange, withdrawChange } from '$lib/stores/adjustChanges';
	import { selectedBlock, nextBlockId } from '$lib/stores/selectedBlock';
	import { reportAnchor, withdrawAnchor } from '$lib/stores/blockAnchors';
	import { reportBlockZ, withdrawBlockZ, otherZValues } from '$lib/stores/blockOrder';
	import { frontZ, backZ } from '$lib/utils/stackingCore';
	import { trackPointer } from '$lib/utils/drag';
	import { guardStyle } from '$lib/adjust/styleGuardCore';
	import { browser } from '$app/environment';
	import { onDestroy } from 'svelte';

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

	// Escape clears the selection (only the selected Block listens, so exactly one
	// handler is live). A drag's own Escape is handled by trackPointer's onCancel.
	function handleDeselect(event: KeyboardEvent) {
		if (event.key === 'Escape') selectedBlock.set(null);
	}
	$: if (browser) {
		if (selected) window.addEventListener('keydown', handleDeselect);
		else window.removeEventListener('keydown', handleDeselect);
	}
	onDestroy(() => {
		if (browser) window.removeEventListener('keydown', handleDeselect);
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

	const snap = (n: number) => (grid > 1 ? Math.round(n / grid) * grid : Math.round(n));
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
		// The shared helper measures the live rendered scale from `el`, captures
		// the pointer, and streams canvas-px deltas until pointerup / Esc.
		trackPointer(event, {
			scaleFrom: el,
			onMove: (dx, dy, e) => {
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
					x = snap(free ? startX + mx : clamp(startX + mx, 0, canvasWidth - width));
					y = snap(free ? startY + my : clamp(startY + my, 0, canvasHeight - height));
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
					if (!free && x + w > canvasWidth)  { w = canvasWidth  - x; h = w / ratio; }
					if (!free && y + h > canvasHeight) { h = canvasHeight - y; w = h * ratio; }
					width  = snap(w);
					height = snap(h);
				} else {
					width = clamp(snap(startW + dx), minSize, free ? Infinity : canvasWidth - x);
					height = clamp(snap(startH + dy), minSize, free ? Infinity : canvasHeight - y);
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

	// Publish this Block's live z so its siblings' Front/Back can order against it.
	// Browser-only: purely a ADJUST-mode aid, and SSR must not touch module state
	// that outlives one render (unlike blockAnchors, which a Connector needs on the
	// server).
	$: if (browser) reportBlockZ(blockId, z);
	onDestroy(() => { if (browser) withdrawBlockZ(blockId); });

	// When NOT editing, a bounds="none" element that bleeds past the canvas should
	// look clipped to the canvas edge (the "stage"), not spill into the letterbox.
	// Clip just THIS element to the canvas rectangle, computed in its own local
	// coords (local L maps to canvas x+L, so the visible band is -x … canvasWidth-x).
	// While editing, no clip — the off-stage part (and its handles) stays grabbable.
	$: clipPath =
		!editing && bounds === 'none'
			? `inset(${Math.max(0, -y)}px ${Math.max(0, x + width - canvasWidth)}px` +
			  ` ${Math.max(0, y + height - canvasHeight)}px ${Math.max(0, -x)}px)`
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
			dirty: snippet !== initialSnippet,
			oldTag: initialSnippet,
			newTag: snippet,
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
	$: if (track && name) {
		// A renamed Block must not leave its old name behind in the registry.
		if (anchor.name && anchor.name !== name) withdrawAnchor(anchor.name);
		anchor.name = name;
		reportAnchor(name, { x, y, width, height });
	}
	onDestroy(() => withdrawAnchor(anchor.name));
</script>

<!-- svelte-ignore a11y-no-static-element-interactions a11y-no-noninteractive-element-interactions -->
<div
	class="movable {klass}"
	class:editing={editing}
	class:selected={selected}
	class:active={dragging}
	id={id || undefined}
	bind:this={el}
	style="left:{x}px; top:{y}px; width:{width}px; height:{height}px; clip-path:{clipPath}; {zStyle} {guard.safe}"
	on:pointerdown={(e) => startDrag('move', e)}
	on:pointerenter={() => (hovered = true)}
	on:pointerleave={() => (hovered = false)}
>
	<div class="fill-layer" class:loose={!fill}><slot /></div>

	{#if editing}
		<div class="readout">
			{name ? name + ' · ' : ''}{Math.round(x)},{Math.round(y)} · {Math.round(width)}×{Math.round(height)}{z ? ' · z' + Math.round(z) : ''}
			<button
				class="zbtn" type="button" title="Send to back" aria-label="Send to back"
				on:pointerdown|stopPropagation on:click|stopPropagation={sendToBack}
			>⤓</button>
			<button
				class="zbtn" type="button" title="Bring to front" aria-label="Bring to front"
				on:pointerdown|stopPropagation on:click|stopPropagation={bringToFront}
			>⤒</button>
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

<style>
	.movable {
		position: absolute;
		box-sizing: border-box;
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
