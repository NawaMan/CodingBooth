<!--
  Annotate — the speaker's ink overlay.

  Mounted ONCE per deck by SlideDeck (a canvas-level singleton, like <Spotlight>), so no
  slide has to place it. Inert until the speaker arms ANNOTATE: then the surface takes the
  pointer and freehand strokes land on the live slide — circle the term, underline the line
  of code, cross out the wrong branch. <Spotlight> can already ring a Block, but only one
  the AUTHOR named in advance; this is for what the speaker decides to point at while
  answering a question.

  Geometry is not ours: sampled pointer positions go through annotateCore.simplifyPoints
  and then drawCore's `smoothPath` — the SAME Catmull-Rom smoothing <Polyline> and <Curve>
  render through, so ink inherits the NaN-safe, total discipline the Draw family is already
  tested against, and a stroke is nothing more exotic than a `d` string.

  INK PERSISTS, per slide, across reloads (stores/annotation.inkBook). Two windows share it
  for free — they are the same origin, so the audience's copy of the store hears the
  speaker's strokes through the `storage` event, with no relay to keep in step. The price of
  keeping ink is that it can go STALE, so a slide whose marks are older than a day says so
  on arrival and offers to clear them; RESET (this slide) and RESET ALL live on the bar, and
  again in the presenter console.

  The overlay is still SSR-inert: `persisted` degrades to an empty in-memory book on the
  server, so a prerendered page ships no surface, no listener and no ink — whatever happens
  to be in the author's browser.

  Three z-layers, and the order matters: the ink surface (40) sits over the slide's own
  Blocks; the bar and the ANNOTATE toggle (41/42) sit over the surface, because while the
  pen is armed the surface owns EVERY pointer on the canvas — anything the speaker must
  still be able to click has to out-rank it, or they can arm the pen and never put it down.
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
		arrowD,
		clampBarPos,
		hitStroke,
		hitText,
		inkAgeText,
		levelPoints,
		rectD,
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
	import { barPos } from '$lib/stores/annotation';
	import { trackPointer } from '$lib/utils/drag';
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
	}

	let {
		canvasWidth = 1920,
		canvasHeight = 1080,
		penWidth = 6,
		highlighterWidth = 34,
		arrowHead = 36,
		eraserRadius = 14,
		textSize = 44,
		inkColors = [null, '#E5484D', '#3FA9F5', '#4BD07A', '#FFFFFF'],
		levelHighlight = true,
		snapPen = true
	}: Props = $props();


	// Armed = the control is offered here AND the speaker turned it on. Both halves matter:
	// a stale persisted `true` must stay inert on a deck that never offers the pen.
	const armed = $derived($canAnnotate && $annotationMode);

	// The surface renders whenever there is ink to show OR the pen is armed — the AUDIENCE
	// window mirrors strokes with the mode OFF, so "armed" alone would leave it blank, and
	// "has ink" alone would give the speaker nothing to draw on.
	const showSurface = $derived(armed || $strokes.length > 0);

	// The modes that lay down NO ink: the eraser removes, freeze promotes to source, text
	// types its own label. None of them has a colour to set or a stroke to build.
	const picking = $derived($annotateTool === 'eraser' || $annotateTool === 'freeze');

	// The tool actually drawn with as a stroke. The picking modes and text do not lay down a
	// live path, so while any of them is selected we stand in the pen (the draw path never
	// runs: `live` stays empty). This keeps every draw-side call (shapeOf/dFor/strokeWidth)
	// type-safe without an `as` in sight.
	const drawTool = $derived<AnnotateTool>(
		picking || $annotateTool === 'text' ? 'pen' : ($annotateTool as AnnotateTool)
	);
	// The colour the next mark uses — the selected tool's own, or null while picking (neither
	// the eraser nor freeze paints anything). Text is colourable, so it keeps its swatch.
	const color = $derived(picking ? null : $annotateColor[$annotateTool as AnnotateTool]);

	let surface: SVGSVGElement | undefined = $state();
	let live: Point[] = $state([]);
	let seq = 0;

	// ── The eraser ────────────────────────────────────────────────────────────────────────
	// Whole-stroke rubber: hover a mark and it lights up in the erase colour to say "this is
	// what goes"; press (or drag across) and it is removed. There is no partial erase — a
	// stroke is stored as points, and rubbing out a *piece* would mean splitting the polyline;
	// the unit you drew is the unit you take back, same as UNDO.
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
				if (hitText(p, s.points[0] ?? [0, 0], s.text ?? '', s.size ?? textSize, eraserRadius)) return s.id;
			} else {
				const halfWidth = strokeWidth(s.tool, penWidth, highlighterWidth) / 2;
				if (hitStroke(p, s.points, eraserRadius + halfWidth)) return s.id;
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
	const freezeOpts = $derived({ penWidth, highlighterWidth });
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
		return m ? m[1].split(',').map((s) => s.trim()).filter(Boolean) : [];
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
			if (hitText(p, s.points[0] ?? [0, 0], s.text ?? '', s.size ?? textSize, TEXT_GRAB_SLOP)) return s.id;
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
			const stroke: Stroke = { id: `ink-${Date.now()}-${++seq}`, tool: 'text', points: [[x, y]], text, size };
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

	/** `null` colour → no inline style → the role token paints it. */
	function paint(c: string | null | undefined): string {
		return c ? `stroke:${c};` : '';
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
		if (tool === 'line' || tool === 'arrow') return snapPen && snapping ? snapAxis(points) : straightLine(points);
		if (tool === 'rectangle') return straightLine(points); // two opposite corners; rectD normalises them
		return points;
	}

	/** The `d` for a mark. An ARROW gets a shaft-plus-chevron path (arrowD), a RECTANGLE a
	    closed box (rectD), every other stroke the smoothed ink line (strokeD). The points are
	    already shaped by shapeOf, so this only chooses how they become a path — the geometry is
	    the core's. (TEXT is never a path; it renders as an SVG <text>, not through here.) */
	function dFor(points: Point[], tool: AnnotateTool): string {
		if (tool === 'arrow') return arrowD(points, arrowHead);
		if (tool === 'rectangle') return rectD(points);
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
		if (!armed || ev.button !== 0) return;
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
	}

	function onPointerMove(ev: PointerEvent): void {
		if (!armed) return;

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
		const points = shapeOf(simplifyPoints(live, 4), drawTool);
		live = [];
		if (points.length === 0) return;

		const stroke: Stroke = { id: `ink-${Date.now()}-${++seq}`, tool: drawTool, points };
		if (color) stroke.color = color;
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
	const BAR_SCALE = 0.525;

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
	const barStyle = $derived(
		$barPos
			? `left:${$barPos.x}px; top:${$barPos.y}px; bottom:auto; transform:scale(${BAR_SCALE}); transform-origin:top left;`
			: ''
	);

	function pick(tool: AnnotateMode): void {
		annotateTool.set(tool);
	}

	function setColor(c: string | null): void {
		if (picking) return; // neither the eraser nor freeze has a colour to set
		annotateColor.update((m) => ({ ...m, [$annotateTool]: c }));
	}

	// The bar's mode buttons, as icons. Each carries its word as the aria-label AND the tooltip,
	// so nothing is lost by dropping the text — a screen reader and a hover both still say "Pen".
	// The `d` is a 24×24 line glyph, stroked in currentColor (see .annot-btn.icon svg).
	const TOOLS: { tool: AnnotateMode; label: string; d: string }[] = [
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

	/** Escape puts the pen down; Ctrl/Cmd+Z takes back a stroke.

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
		if (ev.key === 'Shift') snapping = true;
		if (ev.key === 'Escape') {
			ev.preventDefault();
			annotationMode.set(false);
		} else if ((ev.ctrlKey || ev.metaKey) && ev.key.toLowerCase() === 'z') {
			ev.preventDefault();
			undoStroke();
		}
	}

	function onKeyup(ev: KeyboardEvent): void {
		// Releasing Shift returns the pen to freehand — the live stroke bows back to the samples
		// the moment the key comes up, even if the pointer is holding still.
		if (ev.key === 'Shift') snapping = false;
	}
</script>

<svelte:window on:keydown={onKeydown} on:keyup={onKeyup} />

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
		style="width:{canvasWidth}px; height:{canvasHeight}px; pointer-events:{armed ? 'auto' : 'none'};"
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
					class:erasing={eraseHoverId === stroke.id}
					class:freezing={freezeHoverId === stroke.id}
					class:frozen={frozenPick.includes(stroke.id)}
					d={dFor(stroke.points, stroke.tool)}
					stroke-width={strokeWidth(stroke.tool, penWidth, highlighterWidth)}
					style={paint(stroke.color)}
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
				d={dFor(shapeOf(live, drawTool), drawTool)}
				stroke-width={strokeWidth(drawTool, penWidth, highlighterWidth)}
				style={paint(color)}
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
			style="left:{editing.x}px; top:{editing.y}px; font-size:{editing.size}px; {color ? `color:${color};` : ''}"
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
	<div class="annot-bar no-print" role="toolbar" aria-label="Annotation tools" bind:this={bar} style={barStyle}>
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
			ondblclick={homeBar}
		>⠿</span>
		<!-- The mode buttons, as icons — PEN LINE ARROW RECTANGLE HIGHLIGHT TEXT ERASE. The word
		     lives on as the aria-label and the tooltip, so nothing is lost by dropping the text.
		     ERASE is a MODE, not a colour of ink (it removes marks); it wears the erase tint when
		     armed, the same token a mark about to be deleted lights up in. -->
		{#each TOOLS as t (t.tool)}
			<button
				type="button"
				class="annot-btn icon"
				class:on={$annotateTool === t.tool}
				class:erase={t.tool === 'eraser'}
				class:freeze={t.tool === 'freeze'}
				aria-label={t.label}
				aria-pressed={$annotateTool === t.tool}
				title={t.label}
				onclick={() => pick(t.tool)}
			>
				<svg viewBox="0 0 24 24" aria-hidden="true"><path d={t.d} /></svg>
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

		<!-- Colour is meaningless while picking, so the swatches step aside for the eraser
		     and for freeze. -->
		{#if !picking}
			<span class="annot-sep" aria-hidden="true"></span>

			<!-- Swatches for speed (you are on stage), plus a picker for anything else. The first
			     swatch is the THEME's colour, and picking it stores `null` rather than a hex. -->
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
					onclick={() => setColor(c)}
				></button>
			{/each}
			<label class="annot-custom" title="Custom colour">
				<input
					type="color"
					aria-label="Custom ink colour"
					value={color ?? '#F0A33E'}
					oninput={(e) => setColor((e.currentTarget as HTMLInputElement).value)}
				/>
			</label>
		{/if}

		<span class="annot-sep" aria-hidden="true"></span>
		<button type="button" class="annot-btn" disabled={$strokes.length === 0} onclick={undoStroke}
			>UNDO</button
		>
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
		stroke: var(--annot-pen, #F0A33E);
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
		stroke: var(--annot-highlighter, #F5E663);
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
		stroke: var(--annot-erase, #FF5C5C);
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
		stroke: var(--annot-freeze, #6FD3F5);
		opacity: 1;
		mix-blend-mode: normal;
		filter: none;
	}
	.annot-stroke.freezing {
		filter: drop-shadow(0 0 7px var(--annot-freeze-glow, rgba(111, 211, 245, 0.75)));
	}

	/* A TEXT label — FILLED (not stroked) with its own role token, which defaults to the pen's
	   colour so untinted text follows the theme with the ink. The same glow the pen carries, so
	   a label reads over whatever the slide put behind it. */
	.annot-text {
		fill: var(--annot-text, var(--annot-pen, #F0A33E));
		font-family: inherit;
		font-weight: 600;
		white-space: pre;
		filter: drop-shadow(0 0 6px var(--annot-pen-glow, rgba(0, 0, 0, 0.55)));
	}
	/* A label the eraser is about to remove, lit in the erase colour like a stroke is. */
	.annot-text.erasing {
		fill: var(--annot-erase, #FF5C5C);
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
		color: var(--annot-text, var(--annot-pen, #F0A33E));
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
		border: 1px solid var(--annot-stale-edge, #F0A33E);
		box-shadow: 0 6px 24px rgba(0, 0, 0, 0.45);
	}
	.annot-stale-text {
		color: var(--annot-bar-fg, #D7DDE5);
		margin-right: 0.3em;
	}

	/* ── The palette ────────────────────────────────────────────────────────────────── */
	.annot-bar {
		position: absolute;
		left: 50%;
		bottom: 28px;
		/* 75% of prior size, then another 70% on top — the pen palette was reading large
		   next to the window-edge chrome. Net 0.75 * 0.7 = 0.525 of the original size.
		   Keep this literal in sync with BAR_SCALE above — the dragged (inline) transform
		   reuses that constant so a drag never loses the shrink.

		   translateY(-100%) is listed AFTER scale on purpose: percentages in `translate()`
		   resolve against the element's own (unscaled) box, but composed in THIS order the
		   shift gets scaled down right along with everything else — so it moves the bar up
		   by exactly its own RENDERED height (0.525 × unscaled), clearing the 28px gap it
		   sits in rather than overshooting by the unscaled height. Listed before translateX
		   so translateX's own -50% (centering) still resolves against the unscaled width,
		   unaffected — matches how it already behaved. */
		transform: translateX(-50%) scale(0.525) translateY(-100%);
		transform-origin: center bottom;
		z-index: 41;
		display: flex;
		align-items: center;
		/* Tighter than before (gap 0.4→0.28, padding 0.45/0.7→0.3/0.5) so the icons can grow
		   (font-size 0.8→0.92) without the bar getting wider — the buttons carry glyphs now, not
		   words, so they read better big and packed close. */
		gap: 0.28em;
		padding: 0.3em 0.5em;
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
		padding: 0.2em 0.55em;
		border-radius: 999px;
		border: 1px solid transparent;
		background: transparent;
		color: var(--annot-bar-fg, #D7DDE5);
		white-space: nowrap;
	}
	/* A mode button carries a glyph, not a word: a square-ish target with a larger icon inside.
	   The <svg> strokes in currentColor, so the icon flips to the on-fg colour when the button
	   is active (.on sets both background and colour). */
	.annot-btn.icon {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		padding: 0.22em;
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
	.annot-btn:hover:not(:disabled) {
		background: var(--annot-bar-hover, rgba(255, 255, 255, 0.1));
	}
	.annot-btn.on {
		background: var(--annot-pen, #F0A33E);
		color: var(--annot-bar-on-fg, #1A1206);
	}
	/* The eraser armed: tint its button with the erase colour, not the pen's, so the bar
	   itself says the next gesture DELETES. Same token the about-to-go strokes light up in. */
	.annot-btn.erase.on {
		background: var(--annot-erase, #FF5C5C);
		color: var(--annot-bar-on-fg, #1A1206);
	}
	/* FREEZE armed: the same trick the eraser plays, in freeze's own cold token — the bar says
	   which of the two "point at a mark" modes you are in without reading the icon. */
	.annot-btn.freeze.on,
	.annot-btn.freeze-go {
		background: var(--annot-freeze, #6FD3F5);
		color: var(--annot-bar-on-fg, #1A1206);
	}
	/* The commit. Disabled until something freezable is picked, so an empty press is not a
	   thing that can happen — the count on the face and the disabled state come from the same
	   freezeCount, and cannot disagree. */
	.annot-btn.freeze-go:disabled {
		background: transparent;
		color: var(--annot-bar-fg, #D7DDE5);
	}
	/* What just happened (FROZEN 2 / COPIED 2 / PLACE IT YOURSELF), or the standing hint. A
	   write to your source must never be silent — the same rule ADJUST's SAVE flash follows. */
	.annot-said {
		font-size: 0.82em;
		letter-spacing: 0.04em;
		color: var(--annot-bar-done, #7FD1A0);
		white-space: nowrap;
	}
	.annot-said.hint {
		color: var(--annot-bar-fg, #D7DDE5);
		opacity: 0.6;
	}
	.annot-btn:disabled {
		opacity: 0.35;
		cursor: default;
	}
	.annot-btn.keep {
		color: var(--annot-bar-fg, #D7DDE5);
		opacity: 0.75;
	}

	/* Put the pen down — a round (×), the same idea as <Hint>'s dismiss, in place of a DONE
	   word. Quiet at rest, brightens on hover; the glyph is nudged up for optical centring. */
	.annot-close {
		cursor: pointer;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 1.7em;
		height: 1.7em;
		padding: 0;
		border: 1px solid transparent;
		border-radius: 50%;
		background: transparent;
		color: var(--annot-bar-fg, #D7DDE5);
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
		cursor: pointer;
		width: 1.35em;
		height: 1.35em;
		padding: 0;
		border-radius: 50%;
		border: 2px solid transparent;
		background: var(--swatch, var(--annot-pen, #F0A33E));
	}
	/* The theme swatch has no hex of its own — it SHOWS the token, so it keeps meaning the
	   right thing after a re-theme (which is exactly what storing `null` buys). */
	.annot-swatch.theme {
		background: var(--annot-pen, #F0A33E);
	}
	.annot-swatch.theme.hl {
		background: var(--annot-highlighter, #F5E663);
	}
	.annot-swatch.on {
		border-color: var(--annot-bar-fg, #D7DDE5);
		box-shadow: 0 0 0 2px var(--annot-bar-bg, rgba(20, 22, 26, 0.92));
	}

	.annot-custom {
		display: flex;
		align-items: center;
		cursor: pointer;
	}
	.annot-custom input[type='color'] {
		width: 1.35em;
		height: 1.35em;
		padding: 0;
		border: 2px dashed var(--annot-bar-edge, rgba(255, 255, 255, 0.16));
		border-radius: 50%;
		background: transparent;
		cursor: pointer;
	}

	.annot-sep {
		width: 1px;
		align-self: stretch;
		background: var(--annot-bar-edge, rgba(255, 255, 255, 0.16));
	}

	.annot-grip {
		cursor: grab;
		user-select: none;
		/* The gesture is ours: without this, a drag over the bar would also be a scroll or a
		   text-selection on a touch screen. */
		touch-action: none;
		padding: 0 0.35em 0 0.15em;
		line-height: 1;
		font-size: 1.1em;
		color: var(--annot-bar-fg, #D7DDE5);
		opacity: 0.5;
	}
	.annot-grip:hover {
		opacity: 1;
	}
	.annot-grip:active {
		cursor: grabbing;
	}
</style>
