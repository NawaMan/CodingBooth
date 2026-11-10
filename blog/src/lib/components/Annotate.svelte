<!--
  Annotate — the speaker's ink overlay.

  Mounted ONCE per deck by SlideDeck (a canvas-level singleton, like <Spotlight>), so no
  slide has to place it. Inert until the speaker arms ANNOTATE: then the surface takes the
  pointer and freehand strokes land on the live slide — circle the term, underline the line
  of code, cross out the wrong branch. <Spotlight> can already ring a Block, but only one
  the AUTHOR named in advance; this is for what the speaker decides to point at while
  answering a question.

  Geometry is not ours: sampled pointer positions go through annotateCore.simplifyPoints,
  and the `d` is derived from them at render. The PEN is a filled freehand outline
  (annotate/freehandCore, vendored perfect-freehand) whose width follows the hand's speed;
  the highlighter — and the pen under `freehand={false}` — go through drawCore's
  `smoothPath`, the SAME Catmull-Rom smoothing <Polyline> and <Curve> render through; line,
  arrow and rectangle are straight (arrowD / rectD). Either way ink inherits the NaN-safe,
  total discipline the Draw family is already tested against, and a stroke is nothing more
  exotic than its points plus a `d` string.

  INK PERSISTS, per slide, across reloads (stores/annotation.inkBook). Two windows share it
  for free — they are the same origin, so the audience's copy of the store hears the
  speaker's strokes through the `storage` event, with no relay to keep in step. The price of
  keeping ink is that it can go STALE, so a slide whose marks are older than a day says so
  on arrival and offers to clear them; RESET (this slide) and RESET ALL live on the bar, and
  again in the presenter console.

  The overlay is still SSR-inert: `persisted` degrades to an empty in-memory book on the
  server, so a prerendered page ships no surface, no listener and no ink — whatever happens
  to be in the author's browser.

  The z-layers, and the order matters: the ink surface (40) sits over the slide's own
  Blocks; the pen's bar (41), the stale-ink notice (42) and the text-label input (43) sit
  over the surface, because while the pen is armed the surface owns EVERY pointer on the
  canvas — anything the speaker must still be able to click has to out-rank it, or they can
  arm the pen and never put it down. The ANNOTATE toggle itself is not here: it lives in
  <SlideToolbar>, in SlideDeck's window-fixed overlay at z-index 50.
-->
<script lang="ts">
	import { browser } from '$app/environment';
	import { tick, untrack } from 'svelte';
	import { canSave } from '$lib/stores/adjustMode';
	import { saveFreeze } from '$lib/stores/adjustSave';
	import {
		freezeCount,
		freezeImport,
		freezeSnippet,
		freezeTags,
		isFreezable
	} from '$lib/annotate/freezeCore';
	import {
		annotationMode,
		canAnnotate,
		annotateTool,
		annotateColor,
		strokes,
		staleInk,
		addStroke,
		undoStroke,
		eraseStrokes,
		updateStroke,
		resetSlideInk,
		resetAllInk,
		dismissStale
	} from '$lib/stores/annotation';
	import {
		annotateKeyIntent,
		arrowD,
		clampBarPos,
		fitBarScale,
		hitStroke,
		hitText,
		inkAgeText,
		levelPoints,
		pickMode,
		rectD,
		rectOutline,
		sanitizeText,
		simplifyPoints,
		snapAxis,
		straightLine,
		strokeD,
		strokeWidth,
		toCanvasPoint,
		TEXT_MAX_LEN,
		type AnnotateMode,
		type AnnotateTool,
		type Stroke
	} from '$lib/annotate/annotateCore';
	import {
		freehandD,
		freehandMaxRadius,
		resolveFreehand,
		type FreehandInput
	} from '$lib/annotate/freehandCore';
	import { barPos } from '$lib/stores/annotation';
	import { trackPointer } from '$lib/utils/drag';
	import { isChromeTypingTarget } from '$lib/chrome/chromeArmCore';
	import type { Point } from '$lib/draw/types';

	interface Props {
		canvasWidth?: number;
		canvasHeight?: number;
		/** Stroke widths in canvas px. The highlighter is a BAND, not a line — to highlight
		 *  is to swipe OVER the words, so it must cover a line of text. */
		penWidth?: number;
		highlighterWidth?: number;
		/** Arrowhead length in canvas px — the chevron on an ARROW mark. Clamped to the
		 *  shaft, so a short arrow keeps a head no longer than itself (see arrowD). */
		arrowHead?: number;
		/** Corner radius of a RECTANGLE mark, in canvas px — a small rounding so a box reads as
		 *  drawn rather than ruled. Clamped to the box (see rectD); 0 gives square corners. A
		 *  frozen box carries it as `<Rect rounded>`, so it keeps its corners in source. */
		rectRadius?: number;
		/** The eraser's reach in canvas px, ON TOP of each stroke's own half-width — how close
		 *  the pointer must come to a mark to catch it. Bigger = a more forgiving rubber. */
		eraserRadius?: number;
		/** Font size of a TEXT mark, in canvas px — stored on the mark when placed, so a label
		 *  keeps its size across reloads and windows even if this default later changes. */
		textSize?: number;
		/** The swatches offered in the bar. The FIRST is always the theme's own colour
		 *  (`null` → painted by the --annot-* role token), so the default follows a re-theme
		 *  instead of freezing today's hex into every mark. */
		inkColors?: (string | null)[];
		/** Keep a highlighter swipe LEVEL — the band sits on the row you swiped, rather than
		 *  sloping along with the hand that drew it. Set false for a freehand highlighter. */
		levelHighlight?: boolean;
		/** Let Shift snap a PEN stroke — or an ARROW — to a dead-straight X/Y axis line, an
		 *  underline or a plumb line the wrist can't hold freehand (the pen's twin of
		 *  levelHighlight). Set false to make Shift inert; the pen stays fully freehand and the
		 *  arrow stays free-angle (still a straight tail→head line, just not axis-locked). */
		snapPen?: boolean;
		/** The PEN's freehand shape (perfect-freehand options, see annotate/freehandCore): a
		 *  filled outline whose width breathes with the hand's speed. Any field left out takes
		 *  the default (size 12, thinning 0.7, streamline 0.6, smoothing 0.5, round caps, no
		 *  taper). `false` brings back the old constant-width line at `penWidth`. Only the pen
		 *  is freehand — the highlighter stays a level band, and line/arrow/rectangle stay crisp. */
		freehand?: FreehandInput | false;
	}

	let {
		canvasWidth = 1920,
		canvasHeight = 1080,
		penWidth = 6,
		highlighterWidth = 34,
		arrowHead = 36,
		rectRadius = 12,
		eraserRadius = 14,
		textSize = 44,
		inkColors = [null, '#E5484D', '#3FA9F5', '#4BD07A', '#FFFFFF'],
		levelHighlight = true,
		snapPen = true,
		freehand = {}
	}: Props = $props();

	// The resolved pen shape, or null when the deck asked for the classic stroked pen.
	const pen = $derived(freehand === false ? null : resolveFreehand(freehand));
	/** Is this mark drawn as a filled freehand outline rather than a stroked line? */
	const isFreehand = (tool: AnnotateTool) => tool === 'pen' && pen !== null;

	// Armed = the control is offered here AND the speaker turned it on. Both halves matter:
	// a stale persisted `true` must stay inert on a deck that never offers the pen.
	const armed = $derived($canAnnotate && $annotationMode);

	// The surface renders whenever there is ink to show OR the pen is armed — the AUDIENCE
	// window mirrors strokes with the mode OFF, so "armed" alone would leave it blank, and
	// "has ink" alone would give the speaker nothing to draw on.
	const showSurface = $derived(armed || $strokes.length > 0);

	// POINTER: the pen stays armed — bar up, ink showing, Esc/Ctrl+Z live — but the surface
	// steps out of the way, so the mouse reaches the slide underneath (a link, a button, a
	// video's controls) without closing ANNOTATE and losing the bar.
	const passThrough = $derived(armed && $annotateTool === 'pointer');

	// The modes that lay down NO ink: the eraser removes, freeze promotes to source, pointer
	// draws nothing at all. None of them has a colour to set or a stroke to build. (Text types
	// its own label; it is colourable, so it is not in this list.)
	const picking = $derived(
		$annotateTool === 'eraser' || $annotateTool === 'freeze' || $annotateTool === 'pointer'
	);

	// The tool actually drawn with as a stroke. The picking modes and text do not lay down a
	// live path, so while any of them is selected we stand in the pen (the draw path never
	// runs: `live` stays empty). This keeps every draw-side call (shapeOf/dFor/strokeWidth)
	// type-safe without an `as` in sight.
	const drawTool = $derived<AnnotateTool>(
		picking || $annotateTool === 'text' ? 'pen' : ($annotateTool as AnnotateTool)
	);
	// The colour the next mark uses — the one shared colour, whichever tool draws it — or null
	// while picking (neither the eraser, freeze nor pointer paints anything).
	const color = $derived(picking ? null : $annotateColor);

	let surface: SVGSVGElement | undefined = $state();
	let live: Point[] = $state([]);
	/** When the pen went down — so a committed stroke can carry how long it took to draw
	    (`Stroke.ms`), which the VOD recorder replays at the same speed. Not reactive. */
	let liveStartedAt = 0;
	let seq = 0;

	// ── The eraser ────────────────────────────────────────────────────────────────────────
	// Whole-stroke rubber: hover a mark and it lights up in the erase colour to say "this is
	// what goes"; press (or drag across) and it is removed. There is no partial erase — a
	// stroke is stored as points, and rubbing out a *piece* would mean splitting the polyline;
	// the unit you drew is the unit you take back, same as Ctrl/Cmd+Z.
	let hoverPoint: Point | null = $state(null); // where the pointer is, in canvas px (null = off-surface)
	let erasing = $state(false); // is a delete-drag in progress (button held)?

	/** The one stroke an erase right here would take — the TOP-MOST under the pointer, or null.
	    Reactive on the pointer position AND the stroke list, so the highlight clears the instant
	    that stroke is removed under the cursor. Null unless the eraser is armed. */
	const eraseHoverId = $derived.by<string | null>(() => {
		if (!armed || $annotateTool !== 'eraser' || !hoverPoint) return null;
		return topStrokeUnder(hoverPoint);
	});

	/** The top-most mark the pointer is on, or null. Marks paint in array order, so a later one
	    sits OVER an earlier one; scanning from the end returns the one you actually see under the
	    cursor. A TEXT label is caught by its box (hitText); a stroke by its ink, within the
	    eraser's reach plus the stroke's own half-width — so a fat highlighter catches as easily
	    as it looks and a hair-thin pen needs a near-direct hit. */
	function topStrokeUnder(p: Point): string | null {
		for (let i = $strokes.length - 1; i >= 0; i--) {
			const s = $strokes[i];
			if (s.tool === 'text') {
				if (hitText(p, s.points[0] ?? [0, 0], s.text ?? '', s.size ?? textSize, eraserRadius))
					return s.id;
			} else {
				const halfWidth =
					isFreehand(s.tool) && pen
						? freehandMaxRadius(pen)
						: strokeWidth(s.tool, penWidth, highlighterWidth) / 2;
				// A rectangle is stored as two corners — its diagonal — so test its OUTLINE.
				const ink = s.tool === 'rectangle' ? rectOutline(s.points) : s.points;
				if (hitStroke(p, ink, eraserRadius + halfWidth)) return s.id;
			}
		}
		return null;
	}

	// ── FREEZE: keeping a mark ────────────────────────────────────────────────────────────
	// Ink is transient by design; a shape is source. FREEZE is the bridge — the speaker picks
	// the marks worth keeping and they come back as <Polyline>/<Line>/<Rect> markup.
	//
	// It is a MODE, and it borrows the eraser's whole interaction, because that interaction
	// already teaches "point at a mark and act on it": hover lights the stroke under the
	// cursor, and the reach test is the same hitStroke/hitText. The one deliberate divergence
	// is that a tap TOGGLES a selection instead of acting at once — freezing is additive and
	// reversible where erasing is neither, and a speaker choosing what to keep wants to see
	// the whole set before committing. Nothing leaves the ink layer and nothing reaches the
	// clipboard or the source until the FREEZE (n) button is pressed.
	//
	// The selection is plain component state, NOT part of the persisted inkBook: it is a
	// question being asked right now, not a property of the slide, and it must not ride the
	// storage event to the audience's window.
	let frozenPick: string[] = $state([]);

	/** The mark a freeze-tap right here would toggle, or null. TEXT is excluded — it has no
	    Draw counterpart (freezeCore's isFreezable), so lighting it up would promise a shape
	    that never arrives. */
	const freezeHoverId = $derived.by<string | null>(() => {
		if (!armed || $annotateTool !== 'freeze' || !hoverPoint) return null;
		const id = topStrokeUnder(hoverPoint);
		return id && isFreezable($strokes.find((s) => s.id === id)) ? id : null;
	});

	/** How many of the picked marks would actually produce a tag — the number on the button,
	    so `FREEZE (2)` means two tags and never one-plus-a-disappointment. */
	const freezeReady = $derived(freezeCount($strokes, frozenPick));

	/** The markup for the current pick, wrapped in a <Draw> for the clipboard (a <Polyline>
	    outside one renders nothing). Recomputed rather than cached — it is cheap, and a
	    stroke erased out from under the selection must drop out of it. */
	const freezeOpts = $derived({ penWidth, highlighterWidth, rectRadius });
	const freezeMarkup = $derived(freezeSnippet($strokes, frozenPick, freezeOpts));

	function toggleFreeze(id: string): void {
		frozenPick = frozenPick.includes(id) ? frozenPick.filter((x) => x !== id) : [...frozenPick, id];
	}

	/** Drop the pick — leaving the mode, paging, or freezing. Ids that no longer exist would
	    be harmless (freezeTags filters by the live list), but a stale pick would still show a
	    count for marks that are gone. */
	function clearFreeze(): void {
		frozenPick = [];
	}

	// Leaving FREEZE mode abandons the pick: a selection you cannot see is a selection you
	// will be surprised by when you come back to it.
	$effect(() => {
		if ($annotateTool !== 'freeze') untrack(clearFreeze);
	});

	/** What the last FREEZE did, shown on the bar for a moment. The same vocabulary ADJUST's
	    SAVE uses, and for the same reason: a keypress that silently may-or-may-not have
	    written to your source is worse than no keypress. */
	let freezeSaid: string | null = $state(null);
	let freezeSayTimer: ReturnType<typeof setTimeout> | undefined;
	function say(msg: string): void {
		freezeSaid = msg;
		clearTimeout(freezeSayTimer);
		freezeSayTimer = setTimeout(() => (freezeSaid = null), 2400);
	}

	/** Commit the pick.

	    TWO destinations, tried in order, and the order is the whole design. In dev with SAVE
	    allowed the markup goes straight into the slide's source — the same write ADJUST's
	    SAVE performs, through the same endpoint and the same partial-write reporting. Anywhere
	    else (a built deck, a static host, SAVE refused) there is no source to write, so it
	    falls back to the clipboard: the snippet-emit bargain every other ADJUST gesture makes.

	    Ink is dropped ONLY when a source write actually lands. A clipboard copy has not landed
	    until the author pastes it, and destroying the mark on the strength of a copy would lose
	    it to a failed paste. */
	async function commitFreeze(): Promise<void> {
		const ids = frozenPick.slice();
		const tags = freezeTags($strokes, ids, freezeOpts);
		if (tags.length === 0) return;

		if ($canSave) {
			const res = await saveFreeze(tags.join('\n'), importsFor(tags));
			if (res.ok && res.patched > 0) {
				// It is in the source now; a second copy on the ink layer would paint twice.
				eraseStrokes(ids);
				clearFreeze();
				say(`FROZEN ${tags.length}`);
				return;
			}
			if (res.ok && res.unmatched.length > 0) {
				// The slide has several <Draw>s and we will not guess which one. Fall through
				// to the clipboard so the author can place it — never a silent no-op.
				say('PLACE IT YOURSELF');
			} else if (!res.ok) {
				say('COPIED (NO SAVE)');
			}
		}

		try {
			await navigator.clipboard.writeText(freezeMarkup);
			if (!freezeSaid) say(`COPIED ${tags.length}`);
		} catch {
			// Clipboard blocked (insecure context / permission) — the prompt is the fallback
			// Draw's own Copy already uses, so the markup is never simply lost.
			window.prompt('Copy this markup into the slide:', freezeMarkup);
		}
		clearFreeze();
	}

	/** The `$lib/draw` names a set of tags needs — parsed from the tags themselves rather
	    than from the strokes, so it can never name a component the markup doesn't use. */
	function importsFor(tags: string[]): string[] {
		const line = freezeImport(tags);
		const m = /\{([^}]*)\}/.exec(line);
		return m
			? m[1]
					.split(',')
					.map((s) => s.trim())
					.filter(Boolean)
			: [];
	}

	// ── Text: place, re-edit, drag ─────────────────────────────────────────────────────────
	// A typed label, not a stroke. Clicking empty canvas opens an editor at that point; clicking
	// an existing label re-opens it; dragging one moves it. The editor is a real <input> laid
	// over the surface in canvas px, so it scales with the slide and the caret behaves.
	const TEXT_GRAB_SLOP = 8; // canvas px of forgiveness when grabbing a label to move/edit
	const TEXT_DRAG_THRESHOLD = 4; // canvas px of travel before a press counts as a move, not a tap

	/** The label being edited: its id (null = a NEW label), anchor and size. Null = editor shut. */
	let editing: { id: string | null; x: number; y: number; size: number } | null = $state(null);
	let editText = $state('');
	let textInput: HTMLInputElement | undefined = $state();

	/** The top-most TEXT label under a point (for the text tool to grab/edit), or null. */
	function topTextUnder(p: Point): string | null {
		for (let i = $strokes.length - 1; i >= 0; i--) {
			const s = $strokes[i];
			if (s.tool !== 'text') continue;
			if (hitText(p, s.points[0] ?? [0, 0], s.text ?? '', s.size ?? textSize, TEXT_GRAB_SLOP))
				return s.id;
		}
		return null;
	}

	/** Open the editor — for an existing label (id set → load its text/size) or a new one at p. */
	function openEditor(id: string | null, at: Point, size = textSize): void {
		const mark = id ? $strokes.find((s) => s.id === id) : undefined;
		editing = { id, x: at[0], y: at[1], size: mark?.size ?? size };
		editText = mark?.text ?? '';
		tick().then(() => {
			textInput?.focus();
			textInput?.select();
		});
	}

	/** Confirm the editor: commit the text as a new mark, patch the one being edited, or (an
	    emptied existing label) delete it. Idempotent — a second call with the editor already
	    shut does nothing, so blur-then-click can both fire safely. */
	function commitText(): void {
		if (!editing) return;
		const text = sanitizeText(editText);
		const { id, x, y, size } = editing;
		editing = null;
		editText = '';
		if (id) {
			if (text) updateStroke(id, { text });
			else eraseStrokes([id]); // emptied → the label is gone, like erasing it
		} else if (text) {
			const stroke: Stroke = {
				id: `ink-${Date.now()}-${++seq}`,
				tool: 'text',
				points: [[x, y]],
				text,
				size
			};
			if (color) stroke.color = color;
			addStroke(stroke);
		}
	}

	/** Abandon the editor without committing — Escape. A half-typed new label vanishes; an
	    existing one keeps whatever it already held. */
	function cancelEditor(): void {
		editing = null;
		editText = '';
	}

	function onEditorKeydown(ev: KeyboardEvent): void {
		// Keep the editor's keys to itself: Enter commits, Escape cancels, and NEITHER may reach
		// the window handler that would otherwise disarm the pen or undo a stroke mid-word.
		ev.stopPropagation();
		if (ev.key === 'Enter') {
			ev.preventDefault();
			commitText();
		} else if (ev.key === 'Escape') {
			ev.preventDefault();
			cancelEditor();
		}
	}

	/** A text-tool press: commit any open editor, then grab the label under the pointer (tap →
	    re-edit, drag → move) or open a fresh editor on empty canvas. */
	function onTextPointerDown(ev: PointerEvent): void {
		const p = pointFrom(ev);
		if (editing) commitText(); // clicking away confirms the current label first

		const id = topTextUnder(p);
		if (!id) {
			openEditor(null, p);
			return;
		}

		// An existing label: decide tap-vs-drag from how far the pointer travels before it lifts.
		const mark = $strokes.find((s) => s.id === id);
		const anchor: Point = mark?.points[0] ?? [p[0], p[1]];
		let moved = false;
		trackPointer(ev, {
			scaleFrom: liveScale,
			onMove: (dx, dy) => {
				if (Math.hypot(dx, dy) > TEXT_DRAG_THRESHOLD) moved = true;
				if (moved) updateStroke(id, { points: [[anchor[0] + dx, anchor[1] + dy]] });
			},
			onEnd: () => {
				if (!moved) openEditor(id, anchor); // a tap re-opens it for editing
			},
			onCancel: () => {
				if (moved) updateStroke(id, { points: [anchor] }); // Esc mid-drag puts it back
			}
		});
	}

	// Is Shift down right now? A live modifier, so it is tracked from every pointer event AND
	// from Shift's own keydown/keyup — pressing or releasing Shift WITHOUT moving must reshape
	// the stroke under the pen immediately, not wait for the next sample.
	let snapping = $state(false);

	// Is Shift held right now — for the BAR, not the pen: while it is, the digit badges move off
	// the mode buttons and onto the swatches, since that is what Shift+digit picks. Kept apart
	// from `snapping`, which the pointer events also rewrite mid-stroke; this one follows only
	// the key itself, and a lost focus (Shift released in another window) lets it go.
	let shiftHeld = $state(false);

	/** `null` colour → no inline style → the role token paints it. */
	function paint(c: string | null | undefined, tool?: AnnotateTool): string {
		if (!c) return '';
		return tool && isFreehand(tool) ? `fill:${c};` : `stroke:${c};`;
	}

	/** The shape a gesture actually takes. A highlighter is LEVELLED — the band sits on the
	    row you swiped instead of sloping with your hand (see levelPoints). A PEN is SNAPPED to
	    a straight X/Y axis while Shift is held (see snapAxis) — an underline or a plumb line.
	    A LINE or an ARROW is always the straight tail→head segment (straightLine), and takes
	    the SAME Shift axis-lock the pen does, so a Shift-held one lies dead horizontal or
	    vertical. All are applied to the LIVE stroke as well as the committed one, so what you
	    watch yourself draw is what you get; shaping only at commit would make the mark jump
	    straight the instant the pen lifted.

	    Committed strokes are stored already-shaped, so re-rendering never re-shapes: a stroke
	    drawn freehand (Shift up, or `snapPen={false}`) keeps its curve for good. */
	function shapeOf(points: Point[], tool: AnnotateTool): Point[] {
		if (tool === 'highlighter' && levelHighlight) return levelPoints(points);
		if (tool === 'pen' && snapPen && snapping) return snapAxis(points);
		if (tool === 'line' || tool === 'arrow')
			return snapPen && snapping ? snapAxis(points) : straightLine(points);
		if (tool === 'rectangle') return straightLine(points); // two opposite corners; rectD normalises them
		return points;
	}

	/** The `d` for a mark. An ARROW gets a shaft-plus-chevron path (arrowD), a RECTANGLE a
	    closed box (rectD), every other stroke the smoothed ink line (strokeD). The points are
	    already shaped by shapeOf, so this only chooses how they become a path — the geometry is
	    the core's. (TEXT is never a path; it renders as an SVG <text>, not through here.) */
	function dFor(points: Point[], tool: AnnotateTool, complete = true): string {
		if (tool === 'arrow') return arrowD(points, arrowHead);
		if (tool === 'rectangle') return rectD(points, rectRadius);
		if (isFreehand(tool)) return freehandD(points, pen, complete);
		return strokeD(points);
	}

	function pointFrom(ev: PointerEvent): Point {
		// Measured, not computed: the surface's own on-screen rect already encodes the display
		// mode's transform (FITTED centres, SCALED pans from the top-left, the presenter
		// console applies none), so we never have to ask which one is in force.
		return toCanvasPoint(
			ev.clientX,
			ev.clientY,
			surface?.getBoundingClientRect(),
			canvasWidth,
			canvasHeight
		);
	}

	/** Pointer capture keeps a stroke coming to us even when the pen leaves the surface
	    mid-drag. It is an optimisation, not the mechanism — the stroke is already ours once
	    `live` is non-empty — so a capture that is unavailable or refuses (an unknown
	    pointerId, a synthetic event) must not take the stroke down with it. */
	function capture(id: number, take: boolean): void {
		try {
			if (take) surface?.setPointerCapture?.(id);
			else surface?.releasePointerCapture?.(id);
		} catch {
			// best-effort
		}
	}

	/** Delete the top-most stroke under a point — one erase step. Called on press and on each
	    move of a delete-drag, so scrubbing the eraser takes the marks one at a time as it passes
	    over them. `eraseHoverId` re-derives from the shortened list, so the highlight drops the
	    stroke the same frame it goes. */
	function eraseUnder(p: Point): void {
		const id = topStrokeUnder(p);
		if (id) eraseStrokes([id]);
	}

	function onPointerDown(ev: PointerEvent): void {
		// POINTER mode's surface takes no pointer (pointer-events: none), but the handler must
		// agree on its own: an event that still lands here must not fall through to the pen.
		if (!armed || passThrough || ev.button !== 0) return;
		ev.preventDefault();

		if ($annotateTool === 'eraser') {
			capture(ev.pointerId, true);
			erasing = true;
			hoverPoint = pointFrom(ev);
			eraseUnder(hoverPoint); // a click erases; a drag keeps erasing (onPointerMove)
			return;
		}

		if ($annotateTool === 'freeze') {
			// A TAP toggles, and that is all — no drag, no capture. Freezing is a decision
			// about a set, so it must be as easy to un-pick a mark as to pick it.
			hoverPoint = pointFrom(ev);
			const id = topStrokeUnder(hoverPoint);
			if (id && isFreezable($strokes.find((s) => s.id === id))) toggleFreeze(id);
			return;
		}

		if ($annotateTool === 'text') {
			onTextPointerDown(ev); // place / re-edit / drag a label — its own gesture, no `live`
			return;
		}

		snapping = ev.shiftKey; // Shift may already be held as the pen goes down
		capture(ev.pointerId, true);
		live = [pointFrom(ev)];
		liveStartedAt = performance.now();
	}

	function onPointerMove(ev: PointerEvent): void {
		if (!armed || passThrough) return;

		if ($annotateTool === 'eraser') {
			// Track the pointer whether or not a button is down: with no button it drives the
			// hover highlight (what WOULD go); with the button held it also erases as it goes.
			hoverPoint = pointFrom(ev);
			if (erasing) eraseUnder(hoverPoint);
			return;
		}

		if ($annotateTool === 'freeze') {
			hoverPoint = pointFrom(ev); // drives the highlight only; the tap does the picking
			return;
		}

		// Text places, re-edits or drags on pointerDOWN (the drag runs on its own trackPointer
		// listeners), so the surface's own move does nothing for it.
		if ($annotateTool === 'text') return;

		if (live.length === 0) return;
		snapping = ev.shiftKey; // the authoritative read each sample — Shift can be let go mid-stroke
		const p = pointFrom(ev);
		// A 2px gate while drawing keeps the live array (and the path we re-render on every
		// move) from filling with near-duplicates at the pointer's sample rate; simplifyPoints
		// does the real decimation once, on commit.
		const last = live[live.length - 1];
		if (Math.hypot(p[0] - last[0], p[1] - last[1]) < 2) return;
		live = [...live, p];
	}

	function onPointerUp(ev: PointerEvent): void {
		if ($annotateTool === 'eraser') {
			if (!erasing) return;
			erasing = false;
			capture(ev.pointerId, false);
			return;
		}

		if ($annotateTool === 'freeze') return; // the pick happened on the press
		if ($annotateTool === 'text') return; // the text gesture ends on its own trackPointer up

		if (live.length === 0) return;
		snapping = ev.shiftKey; // whether the mark COMMITS straight is decided at the lift
		capture(ev.pointerId, false);

		// Decimate first, THEN shape: levelling/snapping reduces a stroke to two points, so
		// simplifying afterwards would have nothing left to do — and the extent a shape reads
		// should come from the samples the hand actually produced, not from a thinned subset.
		// A freehand pen decimates no further than the live 2px gate already did: its width is
		// SIMULATED from the spacing between samples, so thinning to an even 4px would flatten
		// the speed it reads — and the committed outline would visibly jump from the live one.
		const points = shapeOf(simplifyPoints(live, isFreehand(drawTool) ? 2 : 4), drawTool);
		live = [];
		if (points.length === 0) return;

		const stroke: Stroke = { id: `ink-${Date.now()}-${++seq}`, tool: drawTool, points };
		if (color) stroke.color = color;
		const ms = Math.round(performance.now() - liveStartedAt);
		if (ms > 0) stroke.ms = ms;
		addStroke(stroke);
	}

	/** The pointer left the surface: forget where it was, so no stroke stays lit as "about to
	    be erased" while the cursor is elsewhere. A delete-drag already in progress is left to
	    end on its own pointerup (pointer capture still delivers it). */
	function onPointerLeave(): void {
		hoverPoint = null;
	}

	// Single source of truth for the palette's shrink — read by both the default (CSS)
	// transform and the dragged (inline) one below, so a drag can never lose it (see
	// barStyle: `transform:none` used to wipe the scale outright once the bar had ever
	// been moved, so anyone who'd dragged it even once got the full-size bar back forever).
	const BAR_SCALE = 0.7;

	// ── Dragging the bar ────────────────────────────────────────────────────────────────
	// The bar is wide and it sits over the slide, so wherever it defaults to it is in someone's
	// way — over the code they want to circle, or the chart's x-axis. So it moves, by a grip
	// rather than by its body (a bar you drag by its face is a bar whose buttons you cannot
	// press), and it REMEMBERS where it was put.
	let bar: HTMLDivElement | undefined = $state();

	/** Screen px per canvas px, right now, in whatever display mode is in force. The ink
	    surface is laid out at exactly canvas size, so its rect answers this directly. */
	function liveScale(): number {
		const r = surface?.getBoundingClientRect();
		return r && r.width > 0 ? r.width / canvasWidth : 1;
	}

	function onGripDown(ev: PointerEvent): void {
		if (ev.button !== 0) return;
		ev.preventDefault();
		ev.stopPropagation(); // never let the grip's own gesture also draw a stroke

		const barRect = bar?.getBoundingClientRect();
		const surfRect = surface?.getBoundingClientRect();
		if (!barRect || !surfRect) return;

		const scale = liveScale();
		// Where the bar is NOW, in canvas px — measured, because until the first drag it is
		// placed by CSS (bottom-centre) and has no coordinates of its own to read.
		const startX = (barRect.left - surfRect.left) / scale;
		const startY = (barRect.top - surfRect.top) / scale;
		const barW = barRect.width / scale;
		const barH = barRect.height / scale;
		const before = $barPos;

		trackPointer(ev, {
			scaleFrom: liveScale,
			onMove: (dx, dy) =>
				barPos.set(clampBarPos(startX + dx, startY + dy, barW, barH, canvasWidth, canvasHeight)),
			// Esc mid-drag puts it back where it was, like every other gesture in the deck.
			onCancel: () => barPos.set(before)
		});
	}

	/** Double-click the grip to send the bar home. The escape hatch for a bar parked somewhere
	    regrettable — and, since the position is persisted, regrettable *permanently*. */
	function homeBar(): void {
		barPos.set(null);
	}

	// `null` → let the CSS place it (bottom-centre, scaled around its own centre-bottom).
	// Dragged → explicit canvas coords, scaled around its own top-left so the box still
	// renders exactly at the point the drag measured and clamped.
	// ONE line, always: drawn at BAR_SCALE when it fits, shrunk to the canvas width when it
	// would not (fitBarScale). Its natural width is measured live — it changes as FREEZE adds
	// its commit or the swatches step aside — and a transform does not change what a
	// ResizeObserver or offsetWidth reports, so the measurement is the UNSCALED width.
	let barNatural = $state(0);
	$effect(() => {
		const el = bar;
		if (!el || typeof ResizeObserver === 'undefined') return;
		const ro = new ResizeObserver(() => (barNatural = el.offsetWidth));
		ro.observe(el);
		return () => ro.disconnect();
	});
	const barScale = $derived(fitBarScale(barNatural, canvasWidth, BAR_SCALE));
	const barStyle = $derived(
		`--annot-bar-scale:${barScale};` +
			($barPos
				? `left:${$barPos.x}px; top:${$barPos.y}px; bottom:auto; transform:scale(${barScale}); transform-origin:top left;`
				: '')
	);

	// The last mode that was NOT pointer — where picking POINTER a second time hands you back
	// to (see pickMode). Plain component state: it is a convenience for this sitting, not part
	// of anything persisted or mirrored.
	let beforePointer: AnnotateMode | null = null;
	$effect(() => {
		if ($annotateTool !== 'pointer') beforePointer = $annotateTool;
	});

	/** Select a bar mode — from a click or a digit key alike, so both toggle POINTER the same way. */
	function pick(tool: AnnotateMode): void {
		annotateTool.set(pickMode(tool, $annotateTool, beforePointer));
	}

	function setColor(c: string | null): void {
		if (picking) return; // neither the eraser, freeze nor pointer has a colour to set
		annotateColor.set(c);
	}

	// The bar's mode buttons, as icons. Each carries its word as the aria-label AND the tooltip,
	// so nothing is lost by dropping the text — a screen reader and a hover both still say "Pen".
	// The `d` is a 24×24 line glyph, stroked in currentColor (see .annot-btn.icon svg).
	const TOOLS: { tool: AnnotateMode; label: string; d: string }[] = [
		// An arrow cursor: hands off the ink, the mouse is yours. First on the bar, the way a
		// drawing app puts its select tool before the ones that make marks.
		{ tool: 'pointer', label: 'Pointer', d: 'M6 3l12 9-5 1 3 6-2.5 1-3-6L6 17z' },
		{ tool: 'pen', label: 'Pen', d: 'M4 20l1-4L15 5l4 4L9 19l-4 1z M14 6l4 4' },
		{ tool: 'line', label: 'Line', d: 'M5 19L19 5' },
		{ tool: 'arrow', label: 'Arrow', d: 'M5 19L19 5M11 5h8v8' },
		{ tool: 'rectangle', label: 'Rectangle', d: 'M5 6h14v12H5z' },
		{ tool: 'highlighter', label: 'Highlight', d: 'M4 20h5M6 18L15 9l3 3-9 9H6zM14 8l3 3' },
		{ tool: 'text', label: 'Text', d: 'M6 6h12M12 6v13M9 19h6' },
		{ tool: 'eraser', label: 'Erase', d: 'M4 20h9M6 18l7-7 6 6-4 4H10z' },
		// A snowflake: this mark stops melting away. Last on the bar, after the tools that
		// make marks and the one that removes them — freezing is what you do once the
		// drawing is done.
		{ tool: 'freeze', label: 'Freeze', d: 'M12 3v18M4.5 7.5l15 9M19.5 7.5l-15 9' }
	];

	/** Escape puts the pen down; Ctrl/Cmd+Z takes back a stroke; 1–9 pick a mode and Shift+1–9
	    a colour (annotateKeyIntent).

	    The paging keys are deliberately NOT captured: a speaker must never be unable to
	    advance, and a key that both dismisses a tool and navigates away is the trap the
	    appendix Escape note already warns about. So ←/→/Space keep paging — and now that ink
	    persists, paging away no longer destroys it; it is still there when you come back. */
	function onKeydown(ev: KeyboardEvent): void {
		if (!armed) return;
		// Shift is a straight-edge modifier for the pen (snapAxis). Tracked from the key itself,
		// not just from pointer events, so pressing it MID-stroke straightens the live line at
		// once — the speaker does not have to twitch the pen to see the ruler engage. It never
		// preventDefaults or returns early: Shift is also a chord prefix elsewhere.
		if (ev.key === 'Shift') {
			snapping = true;
			shiftHeld = true;
		}
		if (ev.key === 'Escape') {
			ev.preventDefault();
			annotationMode.set(false);
		} else if ((ev.ctrlKey || ev.metaKey) && ev.key.toLowerCase() === 'z') {
			ev.preventDefault();
			undoStroke();
		} else if (!isChromeTypingTarget(ev.target)) {
			// 1–9 pick the bar's modes, Shift+1–9 its swatches, both left to right — so the
			// speaker switches tools without travelling to the bar. Never while typing in a
			// field (the text label's own <input> also keeps its keys to itself).
			const intent = annotateKeyIntent(ev, TOOLS.length, inkColors.length);
			if (!intent) return;
			ev.preventDefault();
			if (intent.kind === 'tool') pick(TOOLS[intent.index].tool);
			else setColor(inkColors[intent.index]);
		}
	}

	function onKeyup(ev: KeyboardEvent): void {
		// Releasing Shift returns the pen to freehand — the live stroke bows back to the samples
		// the moment the key comes up, even if the pointer is holding still.
		if (ev.key === 'Shift') {
			snapping = false;
			shiftHeld = false;
		}
	}
</script>

<svelte:window on:keydown={onKeydown} on:keyup={onKeyup} on:blur={() => (shiftHeld = false)} />

{#if showSurface}
	<!-- svelte-ignore a11y_no_static_element_interactions -->
	<svg
		bind:this={surface}
		class="annot-surface"
		class:armed
		class:erasing={armed && $annotateTool === 'eraser'}
		class:freezing={armed && $annotateTool === 'freeze'}
		class:texting={armed && $annotateTool === 'text'}
		viewBox="0 0 {canvasWidth} {canvasHeight}"
		style="width:{canvasWidth}px; height:{canvasHeight}px; pointer-events:{armed && !passThrough
			? 'auto'
			: 'none'};"
		aria-hidden="true"
		onpointerdown={onPointerDown}
		onpointermove={onPointerMove}
		onpointerup={onPointerUp}
		onpointercancel={onPointerUp}
		onpointerleave={onPointerLeave}
	>
		{#each $strokes as stroke (stroke.id)}
			{#if stroke.tool === 'text'}
				<!-- The label being edited is hidden here — its <input> stands in its place, so the
				     text does not double up while you type. -->
				{#if !(editing && editing.id === stroke.id)}
					<text
						class="annot-text"
						class:erasing={eraseHoverId === stroke.id}
						x={stroke.points[0]?.[0] ?? 0}
						y={stroke.points[0]?.[1] ?? 0}
						font-size={stroke.size ?? textSize}
						dominant-baseline="hanging"
						style={stroke.color ? `fill:${stroke.color};` : ''}>{stroke.text}</text
					>
				{/if}
			{:else}
				<path
					class="annot-stroke"
					class:highlighter={stroke.tool === 'highlighter'}
					class:freehand={isFreehand(stroke.tool)}
					class:erasing={eraseHoverId === stroke.id}
					class:freezing={freezeHoverId === stroke.id}
					class:frozen={frozenPick.includes(stroke.id)}
					d={dFor(stroke.points, stroke.tool)}
					stroke-width={strokeWidth(stroke.tool, penWidth, highlighterWidth)}
					style={paint(stroke.color, stroke.tool)}
				/>
			{/if}
		{/each}

		<!-- The stroke under the pen right now. Same paint as a committed one, so the ink does
		     not shift the instant the pen lifts. (Never rendered in eraser or text mode — those
		     remove/type instead of building a stroke, so `live` stays empty.) -->
		{#if live.length > 0}
			<path
				class="annot-stroke"
				class:highlighter={drawTool === 'highlighter'}
				class:freehand={isFreehand(drawTool)}
				d={dFor(shapeOf(live, drawTool), drawTool, false)}
				stroke-width={strokeWidth(drawTool, penWidth, highlighterWidth)}
				style={paint(color, drawTool)}
			/>
		{/if}
	</svg>

	<!-- The text editor: a real <input> laid over the surface at the label's canvas anchor, so
	     it scales with the slide and the caret behaves. Blur or Enter commits, Escape cancels
	     (see commitText / onEditorKeydown). Only ever shown while a label is being written. -->
	{#if armed && editing}
		<input
			class="annot-text-input no-print"
			bind:this={textInput}
			bind:value={editText}
			maxlength={TEXT_MAX_LEN}
			style="left:{editing.x}px; top:{editing.y}px; font-size:{editing.size}px; {color
				? `color:${color};`
				: ''}"
			aria-label="Annotation text"
			onkeydown={onEditorKeydown}
			onblur={commitText}
		/>
	{/if}
{/if}

<!-- The top-centre PRESENT | ANNOTATE | ADJUST | DISPLAY | ☰ cluster used to live HERE, but it
     was anchored to the slide's own (scaled, letterboxed) content — so it hung off the slide's
     top edge and shrank with the fit transform. It now lives in <SlideToolbar>, which SlideDeck
     mounts in the viewport-fixed overlay so it sticks to the WINDOW's top edge at a constant
     size. The ANNOTATE pen toggle moved with it (it reads the same shared stores); the overlay's
     z-index 50 keeps it above this surface (40), so an armed pen still can't bury the toggle. -->

<!-- Old ink, found on arrival. The reason a persisted pen needs a conscience: without this,
     last week's rehearsal marks appear on stage and the speaker has to notice them before
     the audience does. Only for ink OLDER than the threshold — today's marks never nag. -->
{#if $staleInk}
	<div class="annot-stale no-print" role="status">
		<span class="annot-stale-text">
			This slide has annotations from <b>{inkAgeText($staleInk.ts, browser ? Date.now() : 0)}</b>.
		</span>
		<button type="button" class="annot-btn" onclick={resetSlideInk}>RESET SLIDE</button>
		<button type="button" class="annot-btn" onclick={resetAllInk}>RESET ALL</button>
		<button type="button" class="annot-btn keep" onclick={dismissStale}>KEEP</button>
	</div>
{/if}

{#if armed}
	<!-- The pen's own palette. It has to live ABOVE the ink surface: while the mode is on the
	     surface takes every pointer on the canvas, so anything still clickable must out-rank
	     it. Fully visible at rest, so the tools stay legible; the bar is draggable, so the
	     speaker parks it clear of the slide the audience is reading rather than relying on it
	     to fade. -->
	<div
		class="annot-bar no-print"
		role="toolbar"
		aria-label="Annotation tools"
		bind:this={bar}
		style={barStyle}
	>
		<!-- Drag by the GRIP, not by the bar's face — a bar you drag by its body is a bar whose
		     buttons you can no longer press. Double-click sends it home. -->
		<!-- svelte-ignore a11y_no_static_element_interactions -->
		<span
			class="annot-grip"
			role="button"
			tabindex="-1"
			aria-label="Move the annotation bar"
			title="Drag to move · double-click to reset"
			onpointerdown={onGripDown}
			ondblclick={homeBar}>⠿</span
		>
		<!-- The mode buttons, as icons — POINTER PEN LINE ARROW RECTANGLE HIGHLIGHT TEXT ERASE
		     FREEZE. The word
		     lives on as the aria-label and the tooltip, so nothing is lost by dropping the text.
		     ERASE is a MODE, not a colour of ink (it removes marks); it wears the erase tint when
		     armed, the same token a mark about to be deleted lights up in. -->
		{#each TOOLS as t, i (t.tool)}
			<button
				type="button"
				class="annot-btn icon"
				class:on={$annotateTool === t.tool}
				class:erase={t.tool === 'eraser'}
				class:freeze={t.tool === 'freeze'}
				aria-label={t.label}
				aria-pressed={$annotateTool === t.tool}
				aria-keyshortcuts={String(i + 1)}
				title="{t.label} ({i + 1})"
				onclick={() => pick(t.tool)}
			>
				<svg viewBox="0 0 24 24" aria-hidden="true"><path d={t.d} /></svg>
				<!-- Its key, so nobody has to remember the order — handed to the swatches while
				     Shift is held, since Shift+digit picks a colour instead. -->
				{#if !shiftHeld}<span class="annot-key" aria-hidden="true">{i + 1}</span>{/if}
			</button>
		{/each}

		<!-- FREEZE's own controls, in the swatches' place: while picking, colour is meaningless
		     and what the speaker needs instead is the count and the commit. The button IS the
		     commit — nothing leaves the ink layer until it is pressed. -->
		{#if $annotateTool === 'freeze'}
			<span class="annot-sep" aria-hidden="true"></span>
			<button
				type="button"
				class="annot-btn freeze-go"
				disabled={freezeReady === 0}
				title={$canSave
					? 'Write the picked marks into this slide’s source'
					: 'Copy the picked marks as Draw markup'}
				onclick={commitFreeze}>FREEZE ({freezeReady})</button
			>
			{#if freezeSaid}
				<span class="annot-said" role="status">{freezeSaid}</span>
			{:else}
				<span class="annot-said hint">tap a mark to keep it</span>
			{/if}
		{/if}

		<!-- Colour is meaningless while picking, so the swatches step aside for the eraser,
		     for freeze and for pointer. -->
		{#if !picking}
			<span class="annot-sep" aria-hidden="true"></span>

			<!-- Swatches, and only swatches — you are on stage, and a full colour picker is a dialog
			     to fight with mid-answer; a deck that wants other colours sets `inkColors`. The first
			     swatch is the THEME's colour, and picking it stores `null` rather than a hex. The ring
			     on the picked swatch is the only "current colour" marker the bar needs. -->
			{#each inkColors as c, i (i)}
				<button
					type="button"
					class="annot-swatch"
					class:on={color === c}
					class:theme={c === null}
					class:hl={$annotateTool === 'highlighter'}
					style={c ? `--swatch:${c};` : ''}
					aria-label={c === null ? 'Theme colour' : `Colour ${c}`}
					aria-pressed={color === c}
					aria-keyshortcuts={i < 9 ? `Shift+${i + 1}` : undefined}
					title="{c === null ? 'Theme colour' : c}{i < 9 ? ` (Shift+${i + 1})` : ''}"
					onclick={() => setColor(c)}
				>
					{#if shiftHeld && i < 9}<span class="annot-key" aria-hidden="true">{i + 1}</span>{/if}
				</button>
			{/each}
		{/if}

		<span class="annot-sep" aria-hidden="true"></span>
		<!-- No UNDO button: Ctrl/Cmd+Z takes back a stroke, and the bar is wide enough already. -->
		<button type="button" class="annot-btn" disabled={$strokes.length === 0} onclick={resetSlideInk}
			>RESET</button
		>
		<button type="button" class="annot-btn" onclick={resetAllInk}>RESET ALL</button>
		<span class="annot-sep" aria-hidden="true"></span>
		<!-- Put the pen down. An (×) like the one on <Hint>, rather than a DONE word — it reads
		     as "close this" and costs the bar less width. -->
		<button
			type="button"
			class="annot-close"
			aria-label="Close annotation tools"
			title="Close (Esc)"
			onclick={() => annotationMode.set(false)}
		>
			<span aria-hidden="true">×</span>
		</button>
	</div>
{/if}

<style>
	.annot-surface {
		position: absolute;
		left: 0;
		top: 0;
		display: block;
		/* Over the slide's own Blocks — including one lifted to 35 while being edited — but
		   under the Box modal (1000) and the ADJUST-raised Draw surface (60). Ink is a
		   foreground cue: it is the last thing drawn on the slide. */
		z-index: 40;
	}
	.annot-surface.armed {
		/* The pen is the pointer's job now, so say so — and kill the text-selection drag that
		   would otherwise fight every stroke over a paragraph. */
		cursor: crosshair;
		touch-action: none;
		user-select: none;
	}
	/* Erasing is a different job from drawing, so a different pointer — the stroke that lights
	   up says WHAT goes, the cursor says the mode is delete, not draw. */
	.annot-surface.armed.erasing {
		cursor: cell;
	}
	/* Freezing PICKS rather than draws or deletes, so it wears the pointer every "choose this
	   one" surface in the deck wears, not the eraser's cell. */
	.annot-surface.armed.freezing {
		cursor: pointer;
	}
	/* Text places a caret, so the I-beam — the same cue any text field gives. */
	.annot-surface.armed.texting {
		cursor: text;
	}

	.annot-stroke {
		fill: none;
		stroke: var(--annot-pen, #f0a33e);
		stroke-linecap: round;
		stroke-linejoin: round;
		/* The same crisp-at-scale glow Spotlight's ring uses, drawn in the SVG so it scales
		   with the canvas: ink has to read over whatever the slide put behind it — a photo, a
		   chart, a code box. */
		filter: drop-shadow(0 0 6px var(--annot-pen-glow, rgba(0, 0, 0, 0.55)));
	}

	/* A highlighter is the same stroke, painted as a translucent BAND that lets the words
	   through instead of covering them.

	   The blend mode is the whole trick, and it is a role token because it is the one thing
	   that MUST flip with the theme. `screen` is the dark-deck default (the deck's own):
	   screening a yellow band over a dark background turns the background yellow while light
	   text stays light — a highlighter. A LIGHT theme sets `multiply`, where the band tints
	   the white page and dark text stays dark. Get it backwards and the highlighter smears
	   over the very words it is meant to point at. */
	.annot-stroke.highlighter {
		stroke: var(--annot-highlighter, #f5e663);
		opacity: var(--annot-highlighter-alpha, 0.45);
		mix-blend-mode: var(--annot-highlighter-blend, screen);
		filter: none;
	}

	/* A stroke the eraser is about to remove, lit in the erase colour so the speaker deletes
	   exactly the one they meant. A role token, so it themes; the fallback is a bright red —
	   the universal "this goes" — chosen light-on-dark for the themeless main deck, the same
	   rule the other --annot-* fallbacks follow. It must WIN over .highlighter (identical
	   specificity), so it comes AFTER that rule and restores full opacity, normal blend and
	   its own glow — otherwise a translucent band would light only faintly. */
	.annot-stroke.erasing {
		stroke: var(--annot-erase, #ff5c5c);
		opacity: 1;
		mix-blend-mode: normal;
		filter: drop-shadow(0 0 7px var(--annot-erase-glow, rgba(255, 92, 92, 0.75)));
	}

	/* FREEZE's two states, and they are two rather than one on purpose. `.frozen` is a mark
	   already PICKED — it stays lit for as long as the selection stands, so the speaker sees
	   the whole set they are about to keep, not just the one under the cursor. `.freezing` is
	   the hover, and it adds the glow on top: "this is the one a tap would toggle".

	   Both come after .highlighter for the same reason .erasing does — identical specificity,
	   so order decides — and both restore full opacity and normal blend, or a picked
	   highlighter band would light only faintly. They can never collide with .erasing: the two
	   highlights are keyed to different bar modes, and leaving FREEZE drops the pick. */
	.annot-stroke.frozen,
	.annot-stroke.freezing {
		stroke: var(--annot-freeze, #6fd3f5);
		opacity: 1;
		mix-blend-mode: normal;
		filter: none;
	}
	.annot-stroke.freezing {
		filter: drop-shadow(0 0 7px var(--annot-freeze-glow, rgba(111, 211, 245, 0.75)));
	}

	/* A FREEHAND pen mark is an outline polygon (annotate/freehandCore), so it is FILLED with
	   the colour a stroked mark would draw its line in, and carries no stroke of its own — a
	   stroke would fatten it by its width and undo the thinning. Same tokens, same order as the
	   stroked rules above, so the erase and freeze highlights land on it too. */
	.annot-stroke.freehand {
		fill: var(--annot-pen, #f0a33e);
		stroke: none;
	}
	.annot-stroke.freehand.erasing {
		fill: var(--annot-erase, #ff5c5c);
	}
	.annot-stroke.freehand.frozen,
	.annot-stroke.freehand.freezing {
		fill: var(--annot-freeze, #6fd3f5);
	}

	/* A TEXT label — FILLED (not stroked) with its own role token, which defaults to the pen's
	   colour so untinted text follows the theme with the ink. The same glow the pen carries, so
	   a label reads over whatever the slide put behind it. */
	.annot-text {
		fill: var(--annot-text, var(--annot-pen, #f0a33e));
		font-family: inherit;
		font-weight: 600;
		white-space: pre;
		filter: drop-shadow(0 0 6px var(--annot-pen-glow, rgba(0, 0, 0, 0.55)));
	}
	/* A label the eraser is about to remove, lit in the erase colour like a stroke is. */
	.annot-text.erasing {
		fill: var(--annot-erase, #ff5c5c);
		filter: drop-shadow(0 0 7px var(--annot-erase-glow, rgba(255, 92, 92, 0.75)));
	}

	/* The text editor: a bare, chromeless <input> sitting exactly where the label will draw, at
	   canvas px, so what you type is what lands. No border/background of its own — it borrows the
	   label's colour and the deck's font — with a thin caret-side rule so you can see it is live.
	   z-index 43 keeps it over the surface (40) so it takes focus and the caret. */
	.annot-text-input {
		position: absolute;
		z-index: 43;
		margin: 0;
		padding: 0 0.05em;
		border: none;
		border-left: 2px solid currentColor;
		background: transparent;
		color: var(--annot-text, var(--annot-pen, #f0a33e));
		font-family: inherit;
		font-weight: 600;
		line-height: 1;
		outline: none;
		/* The label draws from its TOP (dominant-baseline: hanging); an input is centred in its
		   own line box, so pull it up by the lead the label leaves above the glyphs — the two
		   then sit at the same place and committing does not make the text jump. */
		transform: translateY(-0.05em);
	}

	/* ── The stale-ink notice ───────────────────────────────────────────────────────── */
	.annot-stale {
		position: absolute;
		top: 2.6em;
		left: 50%;
		transform: translateX(-50%);
		z-index: 42;
		display: flex;
		align-items: center;
		gap: 0.4em;
		padding: 0.5em 0.8em;
		border-radius: 10px;
		font-size: calc(var(--base-font, 16px) * 0.75);
		background: var(--annot-bar-bg, rgba(20, 22, 26, 0.92));
		border: 1px solid var(--annot-stale-edge, #f0a33e);
		box-shadow: 0 6px 24px rgba(0, 0, 0, 0.45);
	}
	.annot-stale-text {
		color: var(--annot-bar-fg, #d7dde5);
		margin-right: 0.3em;
	}

	/* ── The palette ────────────────────────────────────────────────────────────────── */
	.annot-bar {
		position: absolute;
		left: 50%;
		bottom: 28px;
		/* 75% of prior size, then another 70% on top — the pen palette was reading large
		   next to the window-edge chrome. Net 0.75 * 0.7 = 0.525 of the original size — then
		   back up to 0.7 once the bar lost its UNDO and stopped being squeezed, so it fills the
		   room it now has (and a portrait deck's bar is not a strip of specks).
		   The scale itself is --annot-bar-scale, set inline from BAR_SCALE — shrunk further
		   when the bar would not fit the canvas (fitBarScale) — and the dragged (inline)
		   transform uses the same value, so a drag never loses the shrink. Keep the
		   fallback below in sync with BAR_SCALE.

		   translateY(-100%) is listed AFTER scale on purpose: percentages in `translate()`
		   resolve against the element's own (unscaled) box, but composed in THIS order the
		   shift gets scaled down right along with everything else — so it moves the bar up
		   by exactly its own RENDERED height (scale × unscaled), clearing the 28px gap it
		   sits in rather than overshooting by the unscaled height. Listed before translateX
		   so translateX's own -50% (centering) still resolves against the unscaled width,
		   unaffected — matches how it already behaved. */
		transform: translateX(-50%) scale(var(--annot-bar-scale, 0.7)) translateY(-100%);
		transform-origin: center bottom;
		z-index: 41;
		display: flex;
		align-items: center;
		/* Its NATURAL width, on one line. Without this the bar was squeezed: an absolutely
		   positioned box shrinks to fit the room between its `left` and the canvas's right
		   edge — half the canvas, from `left: 50%` — and on a 1080-wide portrait deck (whose
		   bigger base font scales every em here) flex then crushed the swatches to dots and
		   slid the key badges off their icons. Too wide for the canvas, the bar is SCALED
		   down to fit (--annot-bar-scale), never wrapped or squashed. */
		width: max-content;
		flex-wrap: nowrap;
		gap: 0.18em;
		padding: 0.26em 0.45em;
		border-radius: 999px;
		font-size: calc(var(--base-font, 16px) * 0.92);
		background: var(--annot-bar-bg, rgba(20, 22, 26, 0.92));
		border: 1px solid var(--annot-bar-edge, rgba(255, 255, 255, 0.16));
		box-shadow: 0 6px 24px rgba(0, 0, 0, 0.45);

		/* Fully visible at rest. The bar used to ghost until pointed at (the fadeChrome trick),
		   because it hung over the slide at a FIXED spot the speaker couldn't move. Now that the
		   bar is draggable — park it off the content and double-click to send it home — there is
		   nothing to fade for: the speaker chooses where it sits, so it can simply stay legible. */
		opacity: 1;
	}

	.annot-btn {
		cursor: pointer;
		font: inherit;
		font-weight: bold;
		letter-spacing: 0.03em;
		padding: 0.2em 0.45em;
		border-radius: 999px;
		border: 1px solid transparent;
		background: transparent;
		color: var(--annot-bar-fg, #d7dde5);
		white-space: nowrap;
	}
	/* A mode button carries a glyph, not a word: a square-ish target with a larger icon inside.
	   The <svg> strokes in currentColor, so the icon flips to the on-fg colour when the button
	   is active (.on sets both background and colour). */
	.annot-btn.icon {
		position: relative; /* anchors the .annot-key badge */
		display: inline-flex;
		align-items: center;
		justify-content: center;
		padding: 0.2em;
		border-radius: 8px;
	}
	.annot-btn.icon svg {
		display: block;
		width: 1.5em;
		height: 1.5em;
		fill: none;
		stroke: currentColor;
		stroke-width: 2;
		stroke-linecap: round;
		stroke-linejoin: round;
	}
	/* The mode's digit key, tucked into the button's corner — readable when you look for it,
	   quiet when you don't, and costing the bar no width. */
	.annot-key {
		position: absolute;
		right: 0.12em;
		bottom: 0.02em;
		font-size: 0.55em;
		line-height: 1;
		font-weight: bold;
		opacity: 0.6;
		pointer-events: none;
	}
	.annot-btn.on .annot-key {
		opacity: 0.85;
	}
	/* On a swatch the digit sits over a colour of any brightness, so it carries its own dark
	   outline rather than relying on the bar behind it. */
	.annot-swatch .annot-key {
		right: -0.35em;
		bottom: -0.3em;
		opacity: 1;
		color: var(--annot-bar-fg, #d7dde5);
		text-shadow:
			0 0 2px var(--annot-bar-bg, #14161a),
			0 0 2px var(--annot-bar-bg, #14161a);
	}
	.annot-btn:hover:not(:disabled) {
		background: var(--annot-bar-hover, rgba(255, 255, 255, 0.1));
	}
	.annot-btn.on {
		background: var(--annot-pen, #f0a33e);
		color: var(--annot-bar-on-fg, #1a1206);
	}
	/* The eraser armed: tint its button with the erase colour, not the pen's, so the bar
	   itself says the next gesture DELETES. Same token the about-to-go strokes light up in. */
	.annot-btn.erase.on {
		background: var(--annot-erase, #ff5c5c);
		color: var(--annot-bar-on-fg, #1a1206);
	}
	/* FREEZE armed: the same trick the eraser plays, in freeze's own cold token — the bar says
	   which of the two "point at a mark" modes you are in without reading the icon. */
	.annot-btn.freeze.on,
	.annot-btn.freeze-go {
		background: var(--annot-freeze, #6fd3f5);
		color: var(--annot-bar-on-fg, #1a1206);
	}
	/* The commit. Disabled until something freezable is picked, so an empty press is not a
	   thing that can happen — the count on the face and the disabled state come from the same
	   freezeCount, and cannot disagree. */
	.annot-btn.freeze-go:disabled {
		background: transparent;
		color: var(--annot-bar-fg, #d7dde5);
	}
	/* What just happened (FROZEN 2 / COPIED 2 / PLACE IT YOURSELF), or the standing hint. A
	   write to your source must never be silent — the same rule ADJUST's SAVE flash follows. */
	.annot-said {
		font-size: 0.82em;
		letter-spacing: 0.04em;
		color: var(--annot-bar-done, #7fd1a0);
		white-space: nowrap;
	}
	.annot-said.hint {
		color: var(--annot-bar-fg, #d7dde5);
		opacity: 0.6;
	}
	.annot-btn:disabled {
		opacity: 0.35;
		cursor: default;
	}
	.annot-btn.keep {
		color: var(--annot-bar-fg, #d7dde5);
		opacity: 0.75;
	}

	/* Put the pen down — a round (×), the same idea as <Hint>'s dismiss, in place of a DONE
	   word. Quiet at rest, brightens on hover; the glyph is nudged up for optical centring. */
	.annot-close {
		cursor: pointer;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 1.6em;
		height: 1.6em;
		padding: 0;
		border: 1px solid transparent;
		border-radius: 50%;
		background: transparent;
		color: var(--annot-bar-fg, #d7dde5);
		font: inherit;
		font-size: 1.25em;
		line-height: 1;
		opacity: 0.8;
	}
	.annot-close:hover {
		background: var(--annot-bar-hover, rgba(255, 255, 255, 0.1));
		opacity: 1;
	}
	.annot-close span {
		display: block;
		transform: translateY(-0.06em);
	}

	.annot-swatch {
		position: relative; /* anchors the .annot-key badge shown while Shift is held */
		cursor: pointer;
		/* A <button> does NOT inherit font-size — it falls back to the browser's ~13px — so
		   without this the em size below measured against that, not the bar, and the swatches
		   came out a fraction of the icons' size (specks, on a portrait deck's big base font). */
		font-size: inherit;
		width: 1.3em;
		height: 1.3em;
		padding: 0;
		border-radius: 50%;
		border: 2px solid transparent;
		background: var(--swatch, var(--annot-pen, #f0a33e));
	}
	/* The theme swatch has no hex of its own — it SHOWS the token, so it keeps meaning the
	   right thing after a re-theme (which is exactly what storing `null` buys). */
	.annot-swatch.theme {
		background: var(--annot-pen, #f0a33e);
	}
	.annot-swatch.theme.hl {
		background: var(--annot-highlighter, #f5e663);
	}
	.annot-swatch.on {
		border-color: var(--annot-bar-fg, #d7dde5);
		box-shadow: 0 0 0 2px var(--annot-bar-bg, rgba(20, 22, 26, 0.92));
	}

	/* Nothing on the bar shrinks: if it is too wide, the WHOLE bar scales down (fitBarScale). */
	.annot-bar > :global(*) {
		flex-shrink: 0;
	}
	.annot-sep {
		width: 1px;
		margin: 0 0.1em; /* a rule wants a little more air either side than the buttons get */
		align-self: stretch;
		background: var(--annot-bar-edge, rgba(255, 255, 255, 0.16));
	}

	.annot-grip {
		cursor: grab;
		user-select: none;
		/* The gesture is ours: without this, a drag over the bar would also be a scroll or a
		   text-selection on a touch screen. */
		touch-action: none;
		padding: 0 0.3em 0 0.1em;
		line-height: 1;
		font-size: 1.1em;
		color: var(--annot-bar-fg, #d7dde5);
		opacity: 0.5;
	}
	.annot-grip:hover {
		opacity: 1;
	}
	.annot-grip:active {
		cursor: grabbing;
	}
</style>
