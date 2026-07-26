<!--
  Video — a <video> with slide-friendly chrome and TIME BOOKMARKS.

  A bare <video controls> gives you the browser's player: a bar you cannot theme,
  and no way to say "the interesting bit is at 1:14". This is the same element with
  our own chrome (play/pause, restart, click-to-seek track, clock readout, mute) and
  a chapter list — buttons that seek, with the current chapter highlighted as the
  video plays past it.

  Usage:

    <script>
      import Video from '$lib/components/Video.svelte';
      import Block from '$lib/components/Block.svelte';
      import demo  from './demo.mp4';   // Vite resolves the import to a URL
    </script>

    <Block x={120} y={260} width={1000} height={640}>
      <Video src={demo} bookmarks={[
        { at: '0:03', tag: 'HOST',  label: 'No toolchain on the host.' },
        { at: '0:10', tag: 'BOOTH', label: 'Step in — it builds.' },
      ]} />
    </Block>

  It fills the box it is given (like WebSite), so a Block places and sizes it in
  canvas pixels. Import the file as an asset rather than hard-coding `/media/x.mp4`:
  a root-absolute URL breaks under a GitHub Pages base path.

  BOOKMARKS are the point of the component. `at` takes seconds (`74`) or a clock
  string (`'1:14'`); the list is sorted for you, so chapters can be written in any
  order, and a time that cannot be parsed drops out instead of seeking to nowhere.
  The active chapter is the last one the playhead has passed — which is also what
  puts the ticks on the progress track. All of that arithmetic lives in
  `utils/videoCore.ts`, pure and tested.

  THE KEYBOARD BELONGS TO THE DECK. →/← always page a slide (NavigationBar's window
  listener), so this player never binds them — the progress track is a pointer
  affordance, hidden from assistive tech and skipped by Tab. What a keyboard user
  seeks with is the chapter buttons, which are real buttons and say where they go.
  (Space on a focused button keeps its native meaning and never pages the deck; see
  `utils/stepKeys.ts`.)

  SPACE-STEPPING (`keys="global"`, opt-in) makes the bookmarks a <Steps> build: Space
  seeks to the next chapter, and once the last one is behind the playhead it falls
  through and pages to the next slide. Shift+Space walks back, then pages back. That
  is not a coincidence of behaviour — the Video registers itself with the very same
  `activeSteps` store a Steps build uses, so `spaceIntent` arbitrates the handoff for
  both, and NavigationBar's CONTINUE button (and the presenter console's pulse) seek
  the next chapter for free.

  It is OPT-IN because Space is the deck's advance key and only one build per slide
  may own it. A Steps build exists to be stepped; a video exists to be played, and a
  presenter who taps Space to leave the slide should not have to sit through every
  chapter first. Turn it on for a slide whose video IS the content (VideoPage), and
  leave it off where the player is one element among several.

  Props:
    src         — the video URL (required). Import it; don't hard-code a path.
    poster      — still frame shown before playback.
    bookmarks   — chapter markers: { at, label?, tag? }[].
    chapters    — render the chapter list. Default true (when there are bookmarks).
    controls    — render OUR chrome bar. Default true.
    native      — use the browser's own controls instead, and drop our bar.
    keys        — 'global' lets Space/Shift+Space step the bookmarks. Default 'off'.
    continueKey — also seek on the presenter console's CONTINUE pulse. Needs `keys`.
    start       — seek here once metadata lands (seconds or a clock string).
    autoplay    — `true` always starts on mount; `false` never; `'kiosk'` only while
                  a kiosk session is active (lobby loop). Browsers only allow this
                  while muted, so `muted` defaults on for `true` and `'kiosk'`.
    kioskHold   — while kiosk runs, hold the auto-advance clock until this clip's
                  natural end (one cycle even if `loop`). Default true. Decorative
                  clips pass `kioskHold={false}` so pageMs still owns the slide.
    loop, muted, playsinline, preload — the <video> attributes, unchanged.
    width/height — CSS lengths (default '100%' — fills a Block). In normal flow a
                  `100%` height collapses; pass e.g. height="540px".
    style       — extra inline CSS appended to the outer box.

  In `text` mode the player renders in normal flow at `height`, chrome and all: a
  reader scrolling a document wants the chapter list as much as an audience does.
-->
<script lang="ts">
	import { onDestroy, onMount } from 'svelte';
	import { browser } from '$app/environment';
	import { getMode } from '$lib/presentation';
	import { activeSteps } from '$lib/stores/activeSteps';
	import { kioskActive } from '$lib/stores/kiosk';
	import { clearKioskMediaHold, setKioskMediaHold } from '$lib/stores/kioskMediaHold';
	import { spaceIntent } from '$lib/utils/stepKeys';
	import {
		activeBookmarkIndex,
		formatTime,
		normalizeBookmarks,
		parseTime,
		progressPercent,
		seekFraction,
		type Bookmark
	} from '$lib/utils/videoCore';
	import {
		defaultMutedForAutoplay,
		effectiveMediaLoop,
		isLoopWrap,
		mediaHoldFraction,
		mediaHoldRemainingMs,
		shouldDriveChapterSteps,
		shouldHoldForKiosk,
		wantsAutoplay,
		wantsPlay,
		type VideoAutoplay
	} from '$lib/utils/videoKioskCore';

	/** The video URL. Import the file as an asset so it survives a base path. */
	export let src: string = '';
	/** Still frame shown before playback. */
	export let poster: string = '';
	/** Chapter markers: `{ at: '1:14', label: '…', tag: 'BOOTH' }`. */
	export let bookmarks: Bookmark[] = [];
	/** Render the chapter list under the bar. */
	export let chapters: boolean = true;
	/** Render our chrome bar. */
	export let controls: boolean = true;
	/** Use the browser's own controls instead of ours. */
	export let native: boolean = false;
	/** 'global': Space/Shift+Space step the bookmarks, then page the deck. Opt-in —
	    only one build per slide may own Space. */
	export let keys: 'global' | 'off' = 'off';
	/** Also seek on the presenter console's CONTINUE pulse (gp:continue). */
	export let continueKey: boolean = true;
	/** Seek here once metadata arrives — seconds or a clock string. */
	export let start: number | string | null = null;
	/** `true` always; `false` never; `'kiosk'` only while a kiosk session is active. */
	export let autoplay: VideoAutoplay = false;
	/** Hold the kiosk clock until this clip's natural end (one cycle if `loop`). */
	export let kioskHold: boolean = true;
	/** Restart on end. */
	export let loop: boolean = false;
	/** Start muted. `undefined` → muted when autoplay is `true` or `'kiosk'`. */
	export let muted: boolean | undefined = undefined;
	/** Play inline on iOS rather than taking over the screen. */
	export let playsinline: boolean = true;
	/** How much to fetch up front: 'none' | 'metadata' | 'auto'. */
	export let preload: 'none' | 'metadata' | 'auto' = 'metadata';
	/** Outer box size, any CSS length. Defaults fill a Block. */
	export let width: string = '100%';
	export let height: string = '100%';
	/** Extra inline CSS appended to the outer box. */
	export let style: string = '';
	/** DOM id for the root element. */
	export let id: string = '';
	/** Extra class(es) for the root element. NOTE: a slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS (global.css / roles.css / a
	    :global(...) block) or a utility class. See AGENTS.md. */
	let klass: string = '';
	export { klass as class };

	const isText = getMode() === 'text';
	/** Identity for activeSteps + kiosk media hold. */
	const token = {};

	let video: HTMLVideoElement;
	let track: HTMLElement;

	// Media bindings, not hand-wired events: Svelte keeps these in step with the
	// element's own play/pause/timeupdate/durationchange. `duration` is NaN until
	// metadata lands, which every consumer below is written to survive.
	// Autoplay may be kiosk-only — seed paused assuming session off; the reactive
	// block below starts play when kiosk becomes active.
	let paused = !wantsAutoplay(autoplay, false);
	let currentTime = 0;
	let duration = NaN;
	// Seeded once from the prop, then owned by the mute button. Autoplay modes
	// that can fire without a gesture default muted; hold-driven kiosk Start mutes
	// in the play-kick block below so ordinary Video chrome stays unmuted.
	let isMuted = muted ?? defaultMutedForAutoplay(autoplay);
	/** First natural end of this hold cycle — loop must not re-trap kiosk. */
	let cycleDone = false;
	/** Previous playhead — detects a loop wrap if `ended` never fires. */
	let prevHoldTime = 0;

	// Authored autoplay, or kiosk running a content hold — play the tape, don't
	// leave a paused playhead for chapter-step seeks.
	$: wantPlay =
		!isText &&
		wantsPlay({
			autoplay,
			kioskActive: $kioskActive,
			kioskHold,
			cycleDone
		});
	// HTML autoplay attr only when we actually want play now (not a latent 'kiosk').
	$: mediaAutoplay = wantPlay;
	// Strip `loop` for one kiosk playthrough so the `ended` event fires (HTML loop
	// suppresses it and would pin the booth forever). Author's loop returns after.
	$: mediaLoop = effectiveMediaLoop({
		loop,
		kioskActive: $kioskActive,
		kioskHold,
		cycleDone
	});
	// When kiosk/autoplay wants play, flip paused so Svelte's binding calls play().
	// Force mute first if the author did not insist on sound — unmuted autoplay is
	// rejected by the browser and the clip would sit paused on the first frame.
	// Stopping kiosk does not force-pause — the speaker may keep watching.
	$: if (browser && video && wantPlay && paused && !cycleDone) {
		if (muted !== false) isMuted = true;
		paused = false;
	}

	$: holding = shouldHoldForKiosk({
		kioskHold,
		kioskActive: $kioskActive,
		cycleDone,
		wantPlay,
		paused,
		currentTime,
		duration
	});
	// Belt-and-braces: if loop still wrapped the playhead (ended suppressed),
	// treat that as cycle complete so kiosk can page.
	$: if (browser && holding && !cycleDone && isLoopWrap(prevHoldTime, currentTime, duration)) {
		finishHoldCycle();
	}
	$: if (holding) prevHoldTime = currentTime;
	$: if (!holding) prevHoldTime = 0;

	$: if (browser && !isText) {
		if (holding) {
			setKioskMediaHold(token, {
				fraction: mediaHoldFraction(currentTime, duration),
				remainingMs: mediaHoldRemainingMs(currentTime, duration)
			});
		} else {
			clearKioskMediaHold(token);
		}
	}

	$: marks = normalizeBookmarks(bookmarks);
	$: active = activeBookmarkIndex(marks, currentTime);
	$: percent = progressPercent(currentTime, duration);
	$: showChapters = chapters && marks.length > 0;
	// `native` hands the whole job to the browser's bar; ours would just duplicate it.
	$: showBar = controls && !native;

	/** Seek, clamped into the video. Called by the track and every chapter button. */
	function seekTo(seconds: number) {
		if (!video || !Number.isFinite(seconds)) return;
		// `duration` is NaN before metadata: clamp to the low end only, and let the
		// element reject anything past its (still unknown) end.
		const end = Number.isFinite(duration) ? duration : Infinity;
		currentTime = Math.min(end, Math.max(0, seconds));
	}

	function togglePlay() {
		paused = !paused;
	}

	function restart() {
		cycleDone = false;
		prevHoldTime = 0;
		seekTo(0);
		paused = false;
	}

	/** One playthrough finished — release the kiosk hold (loop must not re-trap). */
	function finishHoldCycle() {
		if (cycleDone) return;
		cycleDone = true;
		clearKioskMediaHold(token);
	}

	/** Natural end — only fires when `loop` is off (we strip it during a hold). */
	function onEnded() {
		finishHoldCycle();
	}

	function seekFromClick(event: MouseEvent) {
		// `detail === 0` is a keyboard activation, which carries no coordinates —
		// it would seek to the track's left edge, i.e. silently restart the video.
		// The track is not focusable anyway; this is the belt to that braces.
		if (!track || !event.detail || !Number.isFinite(duration)) return;
		seekTo(seekFraction(event.clientX, track.getBoundingClientRect()) * duration);
	}

	/** `start` can only be honoured once the element knows how long the video is. */
	function onMetadata() {
		const at = parseTime(start);
		if (Number.isFinite(at) && at > 0) seekTo(at);
	}

	// ---- Space-stepping: the bookmarks, as a <Steps> build -------------------
	//
	// A build has a next step and a previous one, and hands Space back to the deck
	// at either end. For a Video the steps are the chapters: forward is the first
	// mark ahead of the playhead, back is the one before the active mark. Note
	// `hasPrev` is `active > 0`, not `>= 0`: from the FIRST chapter there is no
	// earlier one to step to, so Shift+Space pages back to the previous slide —
	// which also keeps a mark at 0:00 from trapping the presenter on it.
	$: nextMark = marks.find((m) => m.time > currentTime);
	$: build = { hasNext: !!nextMark, hasPrev: active > 0 };

	/** Seek to the next chapter. Also what CONTINUE and the presenter pulse do. */
	function stepNext() {
		if (nextMark) seekTo(nextMark.time);
	}
	/** Seek to the chapter before the active one. */
	function stepPrev() {
		if (active > 0) seekTo(marks[active - 1].time);
	}

	// Publish to the slide chrome exactly as a Steps build does — same store, same
	// contract — so CONTINUE steps the chapters and greys out on the last one. Only
	// the keyboard-owning instance registers, matching who Space would drive.
	// While kiosk is active we *un*register: otherwise the runner's `reveal` branch
	// seeks bookmark-to-bookmark every stepMs on a still-paused (or mid-play) tape.
	$: drivesChrome =
		browser &&
		!isText &&
		shouldDriveChapterSteps({
			keysGlobal: keys === 'global',
			hasMarks: marks.length > 0,
			kioskActive: $kioskActive
		});
	$: if (drivesChrome) {
		activeSteps.set({ owner: token, ...build, next: stepNext });
	} else {
		activeSteps.update((v) => (v && v.owner === token ? null : v));
	}

	onDestroy(() => {
		// Only clear it if we are still the registered build (a later one may own it).
		activeSteps.update((v) => (v && v.owner === token ? null : v));
		clearKioskMediaHold(token);
	});

	// Space seeks forward, Shift+Space back. We claim the key only while a chapter
	// remains in that direction; at either end the event is left untouched, and
	// NavigationBar's listener pages the deck. Both listeners judge the SAME build
	// state through `spaceIntent`, so their firing order cannot matter.
	function onKeydown(e: KeyboardEvent) {
		const intent = spaceIntent(e, build);
		if (intent === 'reveal') {
			e.preventDefault(); // also stops the browser's scroll-on-space
			stepNext();
		} else if (intent === 'peel') {
			e.preventDefault();
			stepPrev();
		}
		// 'page-next' / 'page-prev' / 'ignore' → not ours; NavigationBar decides.
	}

	/** The presenter console's CONTINUE, relayed by SlideDeck as a DOM event. */
	function onContinue() {
		stepNext();
	}

	onMount(() => {
		if (browser && !isText && keys === 'global') {
			window.addEventListener('keydown', onKeydown);
			if (continueKey) window.addEventListener('gp:continue', onContinue);
		}
	});
	onDestroy(() => {
		if (browser) {
			window.removeEventListener('keydown', onKeydown);
			window.removeEventListener('gp:continue', onContinue);
		}
	});
</script>

<div class="video {klass}" class:text-mode={isText} id={id || undefined} style="width: {width}; height: {height}; {style}">
	<div class="stage">
		<!-- svelte-ignore a11y-media-has-caption (captions belong to the video the
		     author supplies; a <track> can be slotted in by wrapping this component) -->
		<video
			bind:this={video}
			bind:paused
			bind:currentTime
			bind:duration
			bind:muted={isMuted}
			on:loadedmetadata={onMetadata}
			on:ended={onEnded}
			{src}
			poster={poster || undefined}
			controls={native}
			autoplay={mediaAutoplay}
			loop={mediaLoop}
			{playsinline}
			{preload}
		></video>
	</div>

	{#if showBar}
		<div class="bar">
			<button
				type="button"
				class="ctrl"
				title={paused ? 'Play' : 'Pause'}
				aria-label={paused ? 'Play' : 'Pause'}
				on:click={togglePlay}
			>
				{#if paused}
					<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
						<path d="M8 5.5v13l11-6.5z" />
					</svg>
				{:else}
					<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
						<rect x="6" y="5" width="4" height="14" rx="1" />
						<rect x="14" y="5" width="4" height="14" rx="1" />
					</svg>
				{/if}
			</button>

			<button
				type="button"
				class="ctrl"
				title="Restart"
				aria-label="Restart from the beginning"
				on:click={restart}
			>
				<svg
					viewBox="0 0 24 24"
					fill="none"
					stroke="currentColor"
					stroke-width="2.4"
					stroke-linecap="round"
					stroke-linejoin="round"
					aria-hidden="true"
				>
					<path d="M3 12a9 9 0 1 0 3-6.7" />
					<polyline points="3 4 3 9 8 9" />
				</svg>
			</button>

			<!-- Pointer-only, and deliberately so: it is unreachable by Tab and invisible
			     to assistive tech, because →/← page the deck and cannot be borrowed to
			     scrub. The chapter buttons below ARE the accessible seek. -->
			<button
				type="button"
				class="track"
				bind:this={track}
				on:click={seekFromClick}
				tabindex="-1"
				aria-hidden="true"
			>
				<span class="fill" style="width: {percent}%"></span>
				<!-- Unkeyed: two bookmarks may legitimately share a time (a moment with
				     two things to say about it), and a keyed each would throw on that. -->
				{#each marks as mark, i}
					<span
						class="tick"
						class:active={i === active}
						style="left: {progressPercent(mark.time, duration)}%"
					></span>
				{/each}
			</button>

			<span class="time">{formatTime(currentTime)} / {formatTime(duration)}</span>

			<button
				type="button"
				class="ctrl"
				title={isMuted ? 'Unmute' : 'Mute'}
				aria-label={isMuted ? 'Unmute' : 'Mute'}
				on:click={() => (isMuted = !isMuted)}
			>
				{#if isMuted}
					<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
						<path d="M4 9v6h4l5 4V5L8 9H4z" />
						<path
							d="M16 9l5 6M21 9l-5 6"
							stroke="currentColor"
							stroke-width="2"
							stroke-linecap="round"
							fill="none"
						/>
					</svg>
				{:else}
					<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
						<path d="M4 9v6h4l5 4V5L8 9H4z" />
						<path
							d="M16.5 8.5a5 5 0 0 1 0 7M19 6a8.5 8.5 0 0 1 0 12"
							stroke="currentColor"
							stroke-width="2"
							stroke-linecap="round"
							fill="none"
						/>
					</svg>
				{/if}
			</button>
		</div>
	{/if}

	{#if showChapters}
		<ul class="marks">
			{#each marks as mark, i}
				<li class:active={i === active}>
					<button
						type="button"
						class="ts"
						title="Jump to {formatTime(mark.time)}"
						aria-current={i === active ? 'true' : undefined}
						on:click={() => seekTo(mark.time)}>{formatTime(mark.time)}</button
					>
					{#if mark.tag}<span class="tag">{mark.tag}</span>{/if}
					<span class="label">{mark.label}</span>
				</li>
			{/each}
		</ul>
	{/if}
</div>

<style>
	.video {
		display: flex;
		flex-direction: column;
		box-sizing: border-box;
		overflow: hidden;
		border: 1px solid color-mix(in srgb, var(--video-border, #CCCCCC) 45%, transparent);
		border-radius: 8px;
		background: var(--video-chrome-bg, #1E1E1E);
	}

	/* `min-height: 0` lets the stage shrink inside the flex column instead of being
	   floored at the video's intrinsic height, which would push the bar out of the box. */
	.stage {
		flex: 1 1 auto;
		min-height: 0;
		background: var(--video-bg, #000000);
	}

	video {
		display: block;
		width: 100%;
		height: 100%;
		/* Letterbox rather than crop: a demo recording's edges usually carry the point. */
		object-fit: contain;
	}

	.bar {
		flex: 0 0 auto;
		display: flex;
		align-items: center;
		gap: 0.6em;
		padding: 0.35em 0.6em;
		background: var(--video-chrome-bg, #1E1E1E);
		color: var(--video-chrome-fg, #C0F1FF);
		border-top: 1px solid color-mix(in srgb, var(--video-border, #CCCCCC) 30%, transparent);
		font-size: 0.6em;
		line-height: 1.6;
	}

	.ctrl {
		flex: 0 0 auto;
		display: grid;
		place-items: center;
		width: 2.2em;
		height: 2.2em;
		padding: 0;
		color: inherit;
		cursor: pointer;
		background: transparent;
		border: 1px solid color-mix(in srgb, var(--video-chrome-fg, #C0F1FF) 35%, transparent);
		border-radius: 50%;
	}
	.ctrl:hover {
		background: color-mix(in srgb, var(--video-accent, #2980B9) 30%, transparent);
	}
	.ctrl svg {
		width: 1.2em;
		height: 1.2em;
	}

	.track {
		position: relative;
		flex: 1 1 auto;
		height: 0.6em;
		padding: 0;
		cursor: pointer;
		border: 0;
		border-radius: 999px;
		background: color-mix(in srgb, var(--video-track, #C0F1FF) 25%, transparent);
	}

	.fill {
		position: absolute;
		inset: 0 auto 0 0;
		border-radius: inherit;
		background: var(--video-accent, #2980B9);
	}

	/* A chapter, marked on the track. Centred on its time, and lit once passed, so
	   the bar shows the same structure the chapter list spells out. */
	.tick {
		position: absolute;
		top: 50%;
		width: 0.25em;
		height: 1.1em;
		transform: translate(-50%, -50%);
		border-radius: 1px;
		background: color-mix(in srgb, var(--video-chrome-fg, #C0F1FF) 55%, transparent);
	}
	.tick.active {
		background: var(--video-chrome-fg, #C0F1FF);
	}

	.time {
		flex: 0 0 auto;
		font-family: monospace;
		font-variant-numeric: tabular-nums;
		opacity: 0.75;
	}

	/* The chapter list scrolls rather than growing the box: inside a Block the author
	   fixed the height, and the video must not be squeezed out by a long list. */
	.marks {
		flex: 0 1 auto;
		overflow-y: auto;
		margin: 0;
		padding: 0.4em 0.6em;
		list-style: none;
		font-size: 0.62em;
		line-height: 1.7;
		color: var(--video-chrome-fg, #C0F1FF);
		border-top: 1px solid color-mix(in srgb, var(--video-border, #CCCCCC) 30%, transparent);
	}

	.marks li {
		display: flex;
		align-items: baseline;
		gap: 0.6em;
		padding: 0.1em 0.3em;
		border-radius: 4px;
		opacity: 0.6;
	}
	.marks li.active {
		opacity: 1;
		background: color-mix(in srgb, var(--video-accent, #2980B9) 22%, transparent);
	}

	.ts {
		flex: 0 0 auto;
		font: inherit;
		font-family: monospace;
		font-variant-numeric: tabular-nums;
		color: inherit;
		cursor: pointer;
		padding: 0 0.5em;
		border-radius: 999px;
		border: 1px solid color-mix(in srgb, var(--video-chrome-fg, #C0F1FF) 35%, transparent);
		background: transparent;
	}
	.ts:hover {
		background: color-mix(in srgb, var(--video-accent, #2980B9) 30%, transparent);
	}

	.tag {
		flex: 0 0 auto;
		font-family: monospace;
		font-size: 0.85em;
		letter-spacing: 0.06em;
		padding: 0 0.4em;
		border-radius: 3px;
		background: color-mix(in srgb, var(--video-chrome-fg, #C0F1FF) 18%, transparent);
	}

	.label {
		flex: 1 1 auto;
		min-width: 0;
	}

	/* A text artifact has no fixed canvas: `height: 100%` against an auto-height
	   parent would collapse the player to its chrome. */
	.text-mode {
		min-height: 320px;
	}
</style>
