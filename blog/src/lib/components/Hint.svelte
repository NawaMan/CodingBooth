<!--
  Hint — a faint cue pinned to the bottom of the slide.

    <Hint text="Flip ADJUST (top-right) to drag & resize any callout" />

  A Hint floats over whatever the slide happens to put behind it — an image, a
  chart, a live website — so it cannot rely on contrasting with the deck surface.
  Left as bare text it disappears the moment the pixels behind it match its colour.
  It therefore carries its OWN background: a translucent backdrop and a hairline
  rule, both mixed from the --hint-* role tokens, which give the text a legible
  surface of its own on any backdrop while staying quiet enough to read as a cue
  and not as content.

  It rests SEMI-TRANSPARENT and lifts to full opacity on hover/focus — a cue
  should recede while you read the slide and sharpen the moment you look at it —
  and it carries an (X) so a viewer can dismiss it once they've read it. A drag
  grip (like the annotate tool bar's) lets a viewer park it off whatever it lands
  on, and — like the pen's bar — it REMEMBERS that across a page turn, as long as
  the viewer never dismisses it: dismissing (× or double-clicking the grip home)
  resets it, so the next Hint (this slide reloaded, or a later slide's) starts
  fresh rather than inheriting a spot chosen for a cue that's gone. See
  stores/hintPos.ts.

  Props:
    text        — the cue.
    isVisible   — false hides it entirely.
    boxed       — the backdrop + rule (default true). `false` restores the old
                  bare text, for slides that know what sits behind it.
    movable     — offer the drag grip (default true). `false` pins the cue to its
                  resting spot and hides the grip.
    dim         — resting opacity (0–1); lifts to 1 on hover/focus. Unset uses the
                  default 0.4 — faint enough to read as a cue, legible in full on
                  hover. Raise it (dim=0.85) for a slide that wants the cue louder.
    dismissible — show the (X) close button (default true). `false` hides it.
    style       — inline style for the pill, applied last so it wins: e.g.
                  `style="font-size: 0.8em"` for a quieter cue on a busy slide.

  Events:
    close       — fired when the viewer dismisses it via (X). Dismissal is also
                  self-contained: the Hint hides itself, no binding required. It
                  stays dismissed for the life of the slide (each slide is its own
                  page load), so no reset is offered.
-->
<script lang="ts">
	import { createEventDispatcher } from 'svelte';
	import { trackPointer } from '$lib/utils/drag';
	import { hintOffset } from '$lib/stores/hintPos';

	export let text = '-hint-';
	export let isVisible = true;
	/** Draw the translucent backdrop + rule behind the text. */
	export let boxed = true;
	/** Offer the drag grip so a viewer can park the cue off whatever it lands on — the
	    same affordance the annotate tool bar has. On by default; `movable={false}` pins
	    it to its resting spot (bottom-centre) and hides the grip. */
	export let movable = true;
	/** Resting opacity (0–1); lifts to 1 on hover/focus. Unset → the mode default. */
	export let dim: number | null = null;
	/** Show the (X) close button. */
	export let dismissible = true;
	/** Inline style for the pill — the same escape hatch Callout and QuickCode offer.
	    Appended LAST, so it beats both the component's own rules (a plain declaration
	    on the element outranks any class selector) and `dim`'s custom property: a slide
	    that wants a smaller or narrower cue writes `style="font-size: 0.8em"` and gets
	    it. Without this prop the attribute was silently dropped — a Svelte component
	    forwards nothing it has not declared. */
	export let style = '';
	/** DOM id for the root element. */
	export let id: string = '';
	/** Extra class(es) for the root element. NOTE: a slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS (global.css / roles.css / a
	    :global(...) block) or a utility class. See AGENTS.md. */
	let klass: string = '';
	export { klass as class };

	const dispatch = createEventDispatcher<{ close: void }>();
	// Own dismissal, so a bare <Hint/> closes without any binding. ANDed with the
	// isVisible prop below, never written back to it.
	let open = true;

	// `dim` rides an inherited custom property the opacity rules read, with a 0.4
	// fallback — so unset it rests semi-transparent, and setting it moves the rest
	// state. Hover/focus overrides it to 1 regardless. Junk (NaN/±∞) falls back too.
	$: dimVar =
		dim == null || !Number.isFinite(dim)
			? ''
			: `--hint-dim:${Math.min(1, Math.max(0, dim))};`;

	function close() {
		open = false;
		// Dismissal resets the shared position for the NEXT Hint too (see stores/hintPos.ts).
		hintOffset.set(null);
		dispatch('close');
	}

	// ── Dragging the cue ────────────────────────────────────────────────────────────────
	// Like the annotate tool bar, the cue floats over whatever the slide put behind it, so
	// wherever it defaults to it is in someone's way. It moves by a GRIP (a pill you drag by
	// its face is a pill whose close button you can't press), and double-clicking the grip
	// sends it home.
	//
	// The move is a TRANSLATE from the resting spot, not an absolute canvas coordinate: the
	// cue is absolutely positioned inside SlideDeck's transform-scaled `.content`, so a
	// translate in canvas px rides that same scale for free — no need to know the canvas
	// origin or unpick `.content`'s padding.
	let root: HTMLDivElement;
	// canvas-px shift from the resting position — reads through the SHARED hintOffset store
	// (stores/hintPos.ts), so it survives a page turn as long as the viewer never dismisses.
	// Only when `movable`, though: a movable={false} Hint stays pinned at its resting spot
	// regardless of whatever an earlier (different) Hint's drag left behind.
	$: offset = movable ? ($hintOffset ?? { x: 0, y: 0 }) : { x: 0, y: 0 };
	$: moved = offset.x !== 0 || offset.y !== 0;

	function onGripDown(ev: PointerEvent) {
		if (ev.button !== 0) return;
		ev.preventDefault();
		ev.stopPropagation(); // the grip's gesture is a drag, never a text-selection on the pill

		const rootRect = root.getBoundingClientRect();
		const frame = root.closest('.content')?.getBoundingClientRect();
		// Screen px per canvas px, right now, in whatever display mode is in force.
		const scale = root.offsetWidth ? rootRect.width / root.offsetWidth : 1;
		// How far the cue may travel each way (canvas px) before its edge leaves the frame —
		// so a drag can't fling it off-screen and out of reach (double-click still homes it).
		const roomL = frame ? (rootRect.left - frame.left) / scale : Infinity;
		const roomR = frame ? (frame.right - rootRect.right) / scale : Infinity;
		const roomU = frame ? (rootRect.top - frame.top) / scale : Infinity;
		const roomD = frame ? (frame.bottom - rootRect.bottom) / scale : Infinity;
		const start = offset;
		// The exact stored value (may be `null`) — so an Esc-cancel restores precisely what
		// was there, rather than turning an un-dragged `null` into an explicit `{x:0,y:0}`.
		const startStored = $hintOffset;

		trackPointer(ev, {
			scaleFrom: root,
			onMove: (dx, dy) => {
				hintOffset.set({
					x: start.x + Math.max(-roomL, Math.min(roomR, dx)),
					y: start.y + Math.max(-roomU, Math.min(roomD, dy))
				});
			},
			// Esc mid-drag puts it back where it was, like every other gesture in the deck.
			onCancel: () => hintOffset.set(startStored)
		});
	}

	/** Double-click the grip to send the cue back to its resting spot — and clear the
	    shared memory, same as a dismiss, so the next Hint doesn't inherit it either. */
	function homeHint() {
		hintOffset.set(null);
	}
</script>

<div
	class="text {klass}"
	class:hidden={!isVisible || !open}
	class:boxed
	class:movable
	bind:this={root}
	id={id || undefined}
	style="{dimVar}{moved ? `transform: translate(${offset.x}px, ${offset.y}px);` : ''}{style}"
>
	{#if movable}
		<!-- Drag by the GRIP, not by the pill's face; double-click sends it home. Rides the
		     group's rest-opacity like the rest of the cue, so it's a quiet affordance until
		     you point at the hint. -->
		<!-- svelte-ignore a11y_no_static_element_interactions -->
		<span
			class="grip"
			role="button"
			tabindex="-1"
			aria-label="Move the hint"
			title="Drag to move · double-click to reset"
			on:pointerdown={onGripDown}
			on:dblclick={homeHint}
		>⠿</span>
	{/if}
	<span class="label">{text}</span>
	{#if dismissible}
		<!-- Matches the annotate bar's own `.annot-sep` before its close — a divider that
		     separates "the cue" from "dismiss it", not just visual filler. -->
		<span class="sep" aria-hidden="true"></span>
		<button class="close" type="button" aria-label="Dismiss hint" on:click={close}>
			<span aria-hidden="true">×</span>
		</button>
	{/if}
</div>

<style>
	/* Centred by its STATIC POSITION, not by margins. An absolutely positioned box
	   with `left`/`right` both auto is placed where it would have sat in flow — and
	   a Hint's flow parent is SlideDeck's `.content`, a flex container with
	   `justify-content: center`, so the pill lands on the canvas's centre line.
	   (`.content` is also transform-scaled, which makes it the containing block.)
	   `margin: auto` used to sit here and did nothing: per CSS 2.1 §10.3.7, when
	   left, width and right are all auto the auto margins are first set to 0. */
	.text {
		/* cosmetic */
		position: absolute;
		padding-left: 0.5em;
		padding-right: 0.5em;
		/* Lifted to sit JUST ABOVE the window-fixed ControlBar's resting peek (the bottom-centre
		   nav pill auto-hides down to a ~40% strip until hovered; it lives at z-index 50 in
		   SlideDeck's overlay, over the slide's own centre line, and would otherwise bury a
		   centred cue). The cue and the bar are in different coordinate systems — the cue scales
		   with the canvas, the bar stays a constant window size — so there is no scale-exact
		   seam in CSS: this is an em value tuned to land the cue flush over the peek at
		   presentation scale. Was 0px, flush to the canvas floor. */
		bottom: 1.8em;
		/* Paint ABOVE the bottom-right Copyright, which is a later DOM sibling in
		   SlideDeck's `.content` and so would otherwise write over a wide, centred cue.
		   A positive z-index beats the copyright's `auto`, so the cue stays legible and
		   the copyright reads as sitting behind it. */
		z-index: 2;
		/* 1.1em of .content's 24px --base-font → ~26px bold — quiet enough for a
		   cue, still large-text for WCAG's 3:1 bar. Was 1.5em (36px); slides that
		   wanted the quieter size had been overriding with style="font-size:1.1em". */
		font-size: 1.1em;
		font-weight: bold;
		/* Rests semi-transparent (0.4), sharpens to full on hover/focus below.
		   `--hint-dim` (from the `dim` prop) overrides the rest value when set. */
		opacity: var(--hint-dim, 0.4);
		transition: opacity 0.15s ease;
	}

	/* Lift to full opacity when pointed at OR when the close button takes focus
	   (keyboard reveal, the deck's :focus-within chrome convention). Full opacity
	   only raises the verified contrast, never lowers it. */
	.text:hover,
	.text:focus-within {
		opacity: 1;
	}

	@media (prefers-reduced-motion: reduce) {
		.text {
			transition: none;
		}
	}

	/* The backdrop is what makes the cue readable over arbitrary pixels. Both the
	   fill and the rule mix toward `transparent`, so neither needs to know the
	   colour of the surface it lands on — they just pull it toward the theme's own
	   --BACKDROP (deepening it under a dark theme, lightening it under a light one,
	   which is what keeps --hint-fg legible either way).

	   The pill inherits the group's rest opacity (0.4 by default), so `opacity` is a
	   GROUP opacity here: it multiplies the 62% fill and 28% rule down before either
	   lands on the backdrop. At rest the composite text-on-pill is a deliberately
	   faint ~2.3:1 (worst case, over black) — a cue, not content. Hover/focus lifts
	   the group to full, where the composite reaches >= 4.1:1: AA for the ~26px bold
	   this renders at (large text), over every backdrop in the deck (letterbox,
	   terminal, QR plate, chart). Faint until looked at, fully legible the moment
	   it is. */
	.text.boxed {
		bottom: 1em;
		/* Right side is tighter than left: the close button now sits inline (see .close),
		   and Annotate's own bar leaves only ~6.5px after its × — 0.7em read as roughly
		   double that gap here, since Hint isn't itself scaled down the way the bar's
		   `scale(0.525)` shrinks its padding along with everything else. 0.35em is the
		   value that lands the same on-screen gap; left is untouched (the grip side). */
		padding: 0.15em 0.35em 0.15em 0.7em;
		border-radius: 999px;
		color: var(--hint-fg, #C0F1FF);
		background: color-mix(in srgb, var(--hint-bg, #000000) 62%, transparent);
		border: 1px solid color-mix(in srgb, var(--hint-border, #C0F1FF) 28%, transparent);
	}

	/* The (×): now sits INLINE at the end of the row, exactly where the annotate tool
	   bar's own close (.annot-close) sits in its bar — trailing the last button, not a
	   corner badge floating off the pill. Same size, same round shape, same rest/hover
	   treatment (transparent at rest, filling in on hover, glyph nudged up for optical
	   centring) — the two dismiss buttons are now the same control, not just similarly
	   shaped ones. No backdrop of its own: it used to need one (a corner badge floats
	   over arbitrary slide pixels), but inline it sits on the pill's own background —
	   the same reason .annot-close needs none, sitting on the bar's. `vertical-align:
	   middle` keeps its circle centred against the label's text baseline — `.text` is
	   plain inline flow, not a flex row, so nothing else aligns it. */
	.close {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		vertical-align: middle;
		width: 1.7em;
		height: 1.7em;
		padding: 0;
		font-size: 0.85em;
		line-height: 1;
		border-radius: 50%;
		cursor: pointer;
		color: var(--hint-fg, #C0F1FF);
		background: transparent;
		border: 1px solid transparent;
	}
	.close:hover,
	.close:focus-visible {
		background: var(--hint-bg, #000000);
		border-color: var(--hint-border, #C0F1FF);
	}
	/* Optical-centre the × in its circle, exactly as .annot-close does. */
	.close span {
		display: block;
		transform: translateY(-0.06em);
	}

	/* Divider between the cue and its dismiss — the same idea as the annotate bar's own
	   `.annot-sep`, sized for an INLINE row rather than a flex one: there is no `align-
	   self: stretch` to lean on here, so it takes a fixed height instead. Rounded caps
	   (top and bottom) rather than annot-sep's sharp rectangle — a hairline reads fine
	   stretched flex-tall across a whole bar, but a short inline one looks better
	   softened at both ends, like a tiny capsule rather than a cut line. Margin on both
	   sides is the ONLY spacing before the close button now (.close carries none of its
	   own), so the gap either side of the divider stays even. */
	.sep {
		display: inline-block;
		vertical-align: middle;
		width: 2px;
		height: 1.1em;
		margin: 0 0em;
		border-radius: 999px;
		background: color-mix(in srgb, var(--hint-border, #C0F1FF) 28%, transparent);
	}

	/* The drag grip — the dotted handle the cue is moved by, styled like the annotate tool
	   bar's own grip (.annot-grip) so the two read as the same affordance. It rides the
	   group's rest-opacity with the rest of the cue; `touch-action: none` keeps a drag over
	   it from also scrolling or selecting on a touch screen. */
	.grip {
		cursor: grab;
		user-select: none;
		touch-action: none;
		margin-right: 0.35em;
		font-size: 0.9em;
		line-height: 1;
		color: var(--hint-fg, #C0F1FF);
		opacity: 0.65;
	}
	.grip:hover {
		opacity: 1;
	}
	.grip:active {
		cursor: grabbing;
	}

	.text.hidden {
		display: none;
	}
</style>
