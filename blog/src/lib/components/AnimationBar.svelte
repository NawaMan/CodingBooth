<!--
  AnimationBar — in-slide playback controls for a slide's keyframe animation.

  PLACING this component IN A SLIDE is the signal that "this slide has a finite,
  timeline-based keyframe (@keyframes) animation I want the viewer to control".
  It does NOT touch the slide-to-slide page transitions (those live on the
  ::view-transition tree and are left exactly as they are) — it only governs the
  CSS @keyframes animations playing on elements WITHIN this slide.

  It drives them through the Web Animations API (getAnimations): every CSS
  @keyframes animation is also a live Animation object whose clock we can read and
  write. From that one handle the bar offers:
    - a PROGRESS bar    — the playhead across the slide's whole animation envelope
    - PAUSE / PLAY      — detach the animation from wall-clock time, and reattach
    - click / drag      — scrub the progress bar to seek to any point
    - RESTART           — jump back to 0 and play from the top

  Scope: it controls the finite CSS animations found inside the nearest slide
  `.content` (its own controls are excluded; CSS *transitions* like Box/WideDiv and
  infinite-loop animations are ignored — neither has a meaningful "progress").

  By default it shows a low-profile "ANIMATE" chrome button (like MODE / the nav
  controls); clicking it reveals the full control bar. The reveal is one-way — the
  bar stays once shown (there is no control to fold it back to the button).

  PLACEMENT: a PLAIN deck-level bar (default scope `.content`, no `driven` clock, no
  explicit `host`) is the slide's ONE central control, so it is HOSTED in the deck's
  bottom ControlBar — portaled out of the scaled canvas into the bar, beside the TOC and
  pager (see the `barHosted` prop, utils/portal, stores/localChrome). A SCOPED bar
  (`scope=".set-*"` / <AnimationScene>), a `driven` rail or a `host`-set bar governs a
  region and stays in the slide, anchored just past the nav. `barHosted={false}` forces a
  plain bar back into the slide.

  Usage — drop it anywhere inside a slide that animates:
      <AnimationBar />
  It renders NOTHING — not even the ANIMATE button — on a slide with no finite,
  seekable @keyframes animation, so it is safe to leave in a shared template and
  cannot interfere with a static slide.
-->
<script lang="ts">
	import CtrlBtn                 from './CtrlBtn.svelte';
	import { browser }            from '$app/environment';
	import { afterNavigate }      from '$app/navigation';
	import { onMount, onDestroy, tick } from 'svelte';
	import { pauseGroup, playGroup } from '$lib/utils/slideAnim';
	import { portal }             from '$lib/utils/portal';
	import { animBarSlot, registerHostedAnim, unregisterHostedAnim } from '$lib/stores/localChrome';

	/* Selector for the element whose subtree is searched for animations. Defaults
	   to the slide canvas `.content`; an author can narrow it (e.g. ".page") to a
	   sub-region when one slide hosts several independent animated areas. Resolved
	   relative to the bar's own position (nearest enclosing match), so several bars
	   on one page — e.g. one <AnimationScene> each — each govern their own region.
	   <AnimationScene> uses this to point the embedded bar at the scene wrapper. */
	export let scope = '.content';
	/* Explicit scope element, highest precedence over `scope`. For the rare case an
	   author already holds the container element (their own bind:this) and wants a
	   standalone bar to govern exactly its subtree. Usually unnecessary — the scope
	   selector resolved from the bar's position covers the <AnimationScene> case. */
	export let host: HTMLElement | null = null;
	/* Emphasise the collapsed ANIMATION button with the prominent (accent) look
	   instead of the muted chrome, when controlling the animation is meant to read
	   as part of the slide rather than incidental chrome. */
	export let highlight = false;
	/* Skip the ANIMATION button and show the controls straight away. With the
	   reveal being one-way anyway, this just means "always open". */
	export let startExpanded = false;
	/* "Driven" mode: an EXTERNAL source owns the playhead (e.g. a ScrollDiv wired
	   `onScroll={(t, p) => bar.seekFraction(p.progY)}`). We detach the animations
	   from the wall-clock on load and seek to 0, then let seekFraction() move them.
	   The bar shows the rail as a live read-out; the play/restart buttons are
	   hidden because re-attaching to the clock would fight the external driver. */
	export let driven = false;
	/* Start the animation HELD at its first frame with the bar already open,
	   instead of letting it auto-play on load. The viewer presses Play to begin.
	   Implies "shown" (like startExpanded) but also pauses + seeks to 0, so the
	   slide opens on the animation's initial state rather than running it. */
	export let startPaused = false;
	/* HOST this bar's scrubber in the deck's bottom ControlBar instead of floating it
	   just past the nav inside the scaled slide. `undefined` (the default) AUTO-DETECTS:
	   a plain deck-level bar — default scope `.content`, no external `driven` clock and no
	   explicit `host` element — is the slide's ONE central control, so it hosts; a scoped
	   bar (`.set-*` / `.anim-scene`), a `driven` rail or a `host`-set bar governs a region
	   and stays in the slide. Pass `barHosted={false}` to keep a plain bar in the slide, or
	   `barHosted` to force hosting. When hosted, the bar portals its `.anim-bar` node into
	   the ControlBar (see utils/portal + stores/localChrome); the zero-footprint
	   `anim-anchor` stays behind, so scope resolution still finds `.content`. */
	export let barHosted: boolean | undefined = undefined;

	/* Seek the whole group to a 0..1 fraction of its envelope. The public hook for
	   scroll-/pointer-driven scrubbing from a parent — pair it with `driven`. */
	export function seekFraction(f: number) {
		if (!hasAnim || duration <= 0) return;
		seek(Math.max(0, Math.min(1, f)) * duration);
	}

	/* Re-read the slide's animations and recompute the envelope WITHOUT resetting
	   the bar's UI (unlike refresh(), which collapses it). Call after an external
	   change to the animation — e.g. an authoring tool that retimes it — so the
	   rail's time-scale tracks the new duration. */
	export function rescan() { collect(); }

	let root:   HTMLElement;         // this component's wrapper (used to self-exclude)
	let anchor: HTMLElement;         // always-present DOM marker for scope resolution
	let track:  HTMLElement;         // the progress rail (its geometry maps x -> time)

	let anims: Animation[] = [];     // the finite CSS animations we govern
	let duration = 0;                // envelope length in ms (max end time of all)
	let playhead = 0;                // current position in ms
	let playing  = false;            // true while attached to the clock and advancing
	let hasAnim  = false;            // gate: render nothing until a real animation exists
	let expanded = startExpanded;    // false = just the ANIMATION button; true = full bar
	let dragging = false;            // a scrub is in progress (pointer held on the rail)
	let raf = 0;                     // the progress-sampling rAF handle (0 = idle)

	// Horizontal placement. By default the collapsed ANIMATION button parks just to
	// the RIGHT of the slide nav bar (…NEXT LAST — it takes the slot PRESENT used to
	// hold, before PRESENT moved up to the slide's top-right chrome), and the expanded bar keeps that
	// LEFT edge fixed and grows RIGHTWARD into the open space. We measure the nav's
	// right edge at runtime rather than hard-code a pixel — the nav and this bar share
	// the transformed canvas as their offsetParent, so offsetLeft/Width are clean
	// canvas px. `leftPos` is the bar's left edge in canvas px (applied as inline
	// `left`); null means "no nav here" → keep the old centred position (e.g.
	// embedded/startExpanded bars). `positioned` gates visibility so the bar doesn't
	// flash at its pre-measure spot on first paint.
	let leftPos: number | null = null;
	let topInset: number | null = null;   // canvas-px top that centres the collapsed button on the nav row
	let positioned = false;

	// Does this bar belong in the bottom ControlBar? Auto: a plain deck-level bar hosts;
	// a scoped / driven / host-set bar stays in the slide. `barHosted` overrides either way.
	$: hosted = barHosted ?? (!driven && !host && scope === '.content');
	// The live portal target — the ControlBar's slot element once it has mounted, else null
	// (which parks the bar at its authored position). Only hosted bars chase it.
	$: hostTarget = hosted ? $animBarSlot : null;

	// Register this bar as a live hosted animation while it is hosted AND has something to
	// play, so the ControlBar reveals its animation segment (divider + slot) only then.
	const animOwner = Symbol('hostedAnim');
	$: if (browser) {
		if (hosted && hasAnim) registerHostedAnim(animOwner);
		else                   unregisterHostedAnim(animOwner);
	}

	// When hosted, the ControlBar owns placement — no canvas-px left/top anchoring. Hold the
	// bar hidden until the slot exists (it flashing in-slide for a frame before the portal
	// lands would be worse than a beat of nothing). Otherwise: the nav-anchored inline style.
	$: barStyle = hosted
		? (hostTarget ? '' : 'visibility:hidden;')
		: (leftPos !== null ? `left:${leftPos}px;` : '') +
			(topInset !== null && !expanded ? `top:${topInset}px;bottom:auto;` : '') +
			(positioned ? '' : 'visibility:hidden;');

	// Measure the nav and anchor the bar's LEFT edge just past it, so the collapsed
	// button sits after LAST and the expanded bar grows rightward. A bar that
	// starts expanded (embedded/driven) has no nav to anchor to and stays centred.
	function positionBar() {
		// Hosted bars are placed by the ControlBar, not anchored to the in-canvas nav.
		if (!browser || !root || expanded || hosted) { positioned = true; return; }
		const parent = root.offsetParent as HTMLElement | null;
		const nav = (parent?.querySelector('.nav') ?? null) as HTMLElement | null;
		if (parent && nav) {
			const GAP = 14; // canvas px between the nav's right edge and the button
			leftPos = nav.offsetLeft + nav.offsetWidth + GAP;
			// Vertically centre the collapsed button on the nav row (their boxes differ
			// in height, so match centres, not edges).
			const navCentre = nav.offsetTop + nav.offsetHeight / 2;
			topInset = navCentre - root.offsetHeight / 2;
		} else {
			leftPos = null; // no nav on this layout — fall back to the centred spot
			topInset = null;
		}
		positioned = true;
	}

	$: fraction = duration > 0 ? Math.max(0, Math.min(1, playhead / duration)) : 0;

	// The wall-clock end of an animation: delay + active duration (+ end delay).
	// 0 for anything without a finite, numeric end (we filter those out anyway).
	function endTimeOf(a: Animation): number {
		const e = a.effect?.getComputedTiming().endTime;
		return typeof e === 'number' && Number.isFinite(e) ? e : 0;
	}

	// Find every finite CSS @keyframes animation in `scope`, excluding our own
	// controls and CSS *transitions* (Box/WideDiv) and infinite loops.
	function collect() {
		if (!browser) return;
		// Resolve the scope from the bar's own position. `anchor` is always in the DOM
		// (unlike `root`, which only exists once hasAnim renders the bar), so closest()
		// finds THIS bar's enclosing scope even on first paint — letting several scenes
		// on one page each resolve to their own region. `host` (explicit element) wins.
		const scopeRoot = (host ?? anchor?.closest(scope) ?? root?.closest(scope)
			?? document.querySelector(scope) ?? document) as Document | Element;
		const all = scopeRoot.getAnimations({ subtree: true });
		anims = all.filter((a) => {
			// Skip the controls' own animations, if any.
			const target = (a.effect as KeyframeEffect | null)?.target as Element | null;
			if (target && root && root.contains(target)) return false;
			// CSS transitions (Box/WideDiv) are state-driven, not a playable timeline.
			if (typeof CSSTransition !== 'undefined' && a instanceof CSSTransition) return false;
			// Only animations with a finite, non-zero envelope are seekable.
			return endTimeOf(a) > 0;
		});
		duration = anims.reduce((m, a) => Math.max(m, endTimeOf(a)), 0);
		hasAnim  = anims.length > 0 && duration > 0;
		// They begin attached to the clock on first paint — reflect that.
		if (hasAnim) playing = anims.some((a) => a.playState === 'running');
	}

	// Read the live playhead as the furthest-advanced animation, each capped at its
	// own end so a short early animation can't peg the bar before the long one ends.
	function sample(): number {
		let t = 0;
		for (const a of anims) {
			const ct = typeof a.currentTime === 'number' ? a.currentTime : 0;
			t = Math.max(t, Math.min(ct, endTimeOf(a)));
		}
		return t;
	}

	function allFinished(): boolean {
		return anims.length > 0 && anims.every((a) => a.playState === 'finished');
	}

	function loop() {
		playhead = sample();
		if (playing && !allFinished()) {
			raf = requestAnimationFrame(loop);
		} else {
			if (allFinished()) { playing = false; playhead = duration; }
			raf = 0;
		}
	}
	function startLoop() { if (!raf && browser) raf = requestAnimationFrame(loop); }
	function stopLoop()  { if (raf) { cancelAnimationFrame(raf); raf = 0; } }

	// Seek the whole group to time `t` (ms). Each animation is clamped to its own
	// end, so the group settles coherently even with staggered delays/durations.
	function seek(t: number) {
		const clamped = Math.max(0, Math.min(t, duration));
		for (const a of anims) a.currentTime = Math.min(clamped, endTimeOf(a));
		playhead = clamped;
	}

	function pause() { pauseGroup(anims); playing = false; stopLoop(); }

	function play() {
		// A spent animation replays from the top. Judge that on the PLAYHEAD, not on
		// playState: scrubbing to the end leaves every animation *paused* at its end, never
		// 'finished', and playGroup (rightly) will not restart a finished animation — so a
		// playState test would make Play a no-op there.
		if (sample() >= duration) seek(0);
		// `playGroup`, not a bare a.play() loop: play() on an animation that has reached its
		// end auto-rewinds it. The animations here do NOT share an end — `drawDelay` staggers
		// a Draw/Connector reveal — so resuming a half-played slide would redraw the shapes
		// that had already finished.
		playGroup(anims);
		playing = true;
		startLoop();
	}

	function toggle() { playing ? pause() : play(); }

	function restart() { seek(0); play(); }

	// Reveal the bar (one-way). While collapsed the animation just plays as authored
	// (we never pause it) and the sampling loop is idle; expanding re-reads the live
	// playhead, so the rail snaps to wherever the animation currently is.
	function expand() {
		expanded = true;
		if (playing) startLoop();
	}

	// --- Scrubbing: pointer x on the rail -> a time, dragging detaches from clock.
	function timeAt(clientX: number): number {
		const r = track.getBoundingClientRect();
		return ((clientX - r.left) / r.width) * duration;
	}
	function onPointerDown(e: PointerEvent) {
		dragging = true;
		pause();                       // a scrub pauses: progress now follows the pointer
		seek(timeAt(e.clientX));
		track.setPointerCapture(e.pointerId);
	}
	function onPointerMove(e: PointerEvent) { if (dragging) seek(timeAt(e.clientX)); }
	function onPointerUp(e: PointerEvent) {
		dragging = false;
		track.releasePointerCapture?.(e.pointerId);
	}

	// Keyboard scrubbing for the focused rail: arrows nudge, Home/End jump.
	function onKeydown(e: KeyboardEvent) {
		const step = duration / 20;    // ~5% per arrow press
		if (e.key === 'ArrowLeft')      { pause(); seek(playhead - step); e.preventDefault(); }
		else if (e.key === 'ArrowRight') { pause(); seek(playhead + step); e.preventDefault(); }
		else if (e.key === 'Home')       { pause(); seek(0);               e.preventDefault(); }
		else if (e.key === 'End')        { pause(); seek(duration);        e.preventDefault(); }
		else if (e.key === ' ')          { toggle();                       e.preventDefault(); }
	}

	// (Re)detect this slide's animations and reset to the collapsed button. Runs on
	// mount AND after every client-side navigation, so a single AnimationBar mounted
	// in a persistent deck layout tracks whatever slide is now on screen — appearing
	// on slides that animate, vanishing on those that don't. CSS animations can
	// attach a frame after first paint, so look once more next frame if empty. (No
	// sampling loop here — it starts only when the bar is expanded.)
	function refresh() {
		if (!browser) return;
		// Driven bars are always open (rail-as-read-out); a startPaused bar opens too
		// (so its Play button is visible); otherwise honour startExpanded.
		expanded = driven || startPaused || startExpanded;
		stopLoop();
		const begin = () => {
			if (!hasAnim) return;
			if (driven) { pause(); seek(0); }            // external source owns the playhead
			else if (startPaused) { pause(); seek(0); }  // hold on frame 0 until the viewer plays
			else if (expanded && playing) startLoop();   // already-open: sample the live clock
		};
		// Measure once the bar is actually in the DOM (tick() waits for Svelte's flush
		// of the {#if hasAnim} block), so root/offsetParent exist.
		const place = () => { if (hasAnim) tick().then(positionBar); };
		collect();
		if (hasAnim) { begin(); place(); }
		else requestAnimationFrame(() => { collect(); begin(); place(); });
	}

	onMount(() => {
		refresh();
		// Web fonts can land after first paint and widen the nav — re-anchor then.
		if (browser && (document as unknown as { fonts?: FontFaceSet }).fonts)
			(document as unknown as { fonts: FontFaceSet }).fonts.ready.then(() => positionBar());
	});
	afterNavigate(refresh);
	onDestroy(() => { stopLoop(); unregisterHostedAnim(animOwner); });
</script>

<!-- Zero-footprint marker that is ALWAYS in the DOM at the bar's position, so the
     scope can be resolved (anchor.closest) before any controls render. -->
<span class="anim-anchor" bind:this={anchor} aria-hidden="true"></span>

{#if hasAnim}
<div
	class="anim-bar no-print"
	class:expanded
	class:centered={!hosted && leftPos === null}
	class:hosted
	style={barStyle}
	bind:this={root}
	use:portal={hostTarget}
>
	{#if !expanded}
	<!-- Low-profile reveal button (chrome, like MODE / the nav controls). One-way:
	     pressing it shows the bar for good. -->
	<span class="toggle">
		<CtrlBtn chrome={!highlight} text="ANIMATE" on:click={expand} />
	</span>
	{:else}
	{#if !driven}
	<button class="icon-btn" aria-label={playing ? 'Pause' : 'Play'} on:click={toggle}>
		{#if playing}
			<!-- pause -->
			<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z" /></svg>
		{:else}
			<!-- play -->
			<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8 5v14l11-7z" /></svg>
		{/if}
	</button>
	{/if}

	<div
		class="track"
		bind:this={track}
		role="slider"
		tabindex="0"
		aria-label="Animation progress"
		aria-valuemin={0}
		aria-valuemax={100}
		aria-valuenow={Math.round(fraction * 100)}
		on:pointerdown={onPointerDown}
		on:pointermove={onPointerMove}
		on:pointerup={onPointerUp}
		on:keydown={onKeydown}
	>
		<div class="fill" style="width:{fraction * 100}%"></div>
		<div class="knob" style="left:{fraction * 100}%"></div>
	</div>

	{#if !driven}
	<button class="icon-btn" aria-label="Restart" on:click={restart}>
		<!-- replay -->
		<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5V1L7 6l5 5V7c3.31 0 6 2.69 6 6s-2.69 6-6 6-6-2.69-6-6H4c0 4.42 3.58 8 8 8s8-3.58 8-8-3.58-8-8-8z" /></svg>
	</button>
	{/if}
	{/if}
</div>
{/if}

<style>
	.anim-anchor { display: none; }   /* DOM-present, layout-absent (used for closest) */
	.anim-bar {
		position: absolute;
		/* Anchored to the LEFT (inline `left` from positionBar), so the collapsed button
		   sits just past the nav bar and the expanded bar grows RIGHT from that fixed
		   left edge. `right:auto` lets the inline `left` own the horizontal. */
		right: auto;
		display: flex;
		align-items: center;
		gap: 0.6em;
		font-size: 1.5em;          /* match the nav-bar chrome scale */
		/* Collapsed state: just the small ANIMATION button, only as wide as itself,
		   dropped onto the nav text row. (The reveal is one-way, so this never has to
		   share a vertical centre with the tall expanded row below.) */
		width: auto;
		bottom: 0.4em;
	}
	/* Fallback when no nav bar is found (embedded / start-expanded bars): keep the
	   old centred position. */
	.anim-bar.centered {
		left: 50%;
		right: auto;
		transform: translateX(-50%);
	}
	.anim-bar.expanded {
		/* Tuned so the tall icon row's vertical CENTRE lines up with the nav text.
		   With the left edge fixed (just past LAST), this width grows the bar
		   RIGHTWARD into the open space. */
		bottom: 0.35em;
		min-height: 0.8em;
		width: 54%;
		max-width: 810px;
	}

	/* ── HOSTED: portaled into the bottom ControlBar ──────────────────────────────────
	   When the bar rides the ControlBar (see the `barHosted` prop), it is no longer the
	   canvas-absolute pill anchored past the nav — it flows INLINE in the bar's row. So
	   drop the absolute positioning and the enlarged 1.5em scale, and shrink back to the
	   bar's own (smaller) scale so the collapsed ANIMATE button reads like the TOC / pager
	   buttons beside it. The portaled node keeps this scoped styling (Svelte's scope hash
	   rides with the element wherever the DOM moves it). */
	.anim-bar.hosted {
		position: static;
		left: auto;
		right: auto;
		top: auto;
		bottom: auto;
		transform: none;
		font-size: 1em;            /* inherit the ControlBar's row scale, not the 1.5em canvas one */
		width: auto;
		gap: 0.4em;
	}
	.anim-bar.hosted.expanded {
		width: auto;               /* the bar sizes to its content — the rail carries a fixed width */
		min-height: 0;
	}
	/* Collapsed ANIMATE button: no longer in a 1.5em context, so it needs no scale-down. */
	.anim-bar.hosted .toggle {
		font-size: 1em;
	}
	/* Compact transport for the slimmer bar: smaller icon buttons and a fixed-width rail
	   (a bar that sizes to its content gives `flex:1` nothing to fill). */
	.anim-bar.hosted .icon-btn {
		width: 2em;
		height: 2em;
	}
	.anim-bar.hosted .icon-btn svg {
		width: 1.4em;
		height: 1.4em;
	}
	.anim-bar.hosted .track {
		flex: none;
		width: 15.6em;   /* the hosted rail, lengthened 30% from the original 12em */
	}

	/* The ANIMATE button is rendered in this bar's enlarged (1.5em) context, so
	   scale it back down to read like the MODE / nav chrome buttons. */
	.toggle {
		flex: none;
		font-size: 0.62em;
	}
	.icon-btn {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		flex: none;
		width: 2.8em;
		height: 2.8em;
		padding: 0;
		cursor: pointer;
		/* Recede like the nav-bar chrome, but stay legible on the dark canvas; the
		   accent fill on hover matches CtrlBtn's chrome hover. */
		color: var(--ctrl-icon-fg, #9aa7b0);
		background: var(--ctrl-bg, #181818);
		border: 0;
		border-radius: 6px;
	}
	.icon-btn:hover {
		color: var(--on-accent, #FFFFFF);
		background: var(--ctrl-hover-bg, #2980B9);
	}
	.icon-btn:active {
		box-shadow: 0 3px var(--ctrl-active-shadow, #0056B3);
		transform: translateY(2px);
	}
	.icon-btn svg {
		display: block;
		width: 2em;
		height: 2em;
		fill: currentColor;
	}
	.track {
		position: relative;
		flex: 1;
		height: 0.28em;
		border-radius: 999px;
		background: var(--ctrl-track-bg, #333333);
		cursor: pointer;
		touch-action: none;        /* let us own horizontal drag for scrubbing */
	}
	/* Invisible grab strip: the visible rail is only 0.28em tall but the knob is
	   ~0.62em, so a press on the knob's top/bottom edge would miss the thin rail and
	   land on the bar behind it (dead zone). This pseudo-element extends the track's
	   pointer target vertically past the whole knob — without thickening the rail —
	   so the white knob is grabbable from its first frame, not only along its waist. */
	.track::before {
		content: '';
		position: absolute;
		left: 0;
		right: 0;
		top: 50%;
		height: 1.2em;             /* taller than the knob (0.62em) for a comfortable grab */
		transform: translateY(-50%);
		/* transparent — purely a hit area (a no-background element is still hit-tested) */
	}
	.track:focus-visible {
		outline: 2px solid var(--ctrl-hover-bg, #2980B9);
		outline-offset: 3px;
	}
	.fill {
		position: absolute;
		left: 0;
		top: 0;
		height: 100%;
		border-radius: 999px;
		background: var(--ctrl-strong-bg, #2980B9);
	}
	.knob {
		position: absolute;
		top: 50%;
		width: 0.62em;
		height: 0.62em;
		border-radius: 50%;
		background: var(--on-accent, #FFFFFF);
		border: 2px solid var(--ctrl-strong-bg, #2980B9);
		transform: translate(-50%, -50%);
		pointer-events: none;      /* the rail handles all pointer interaction */
	}
</style>
