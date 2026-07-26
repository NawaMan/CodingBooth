<!--
  Terminal — a fake console: a typed command, then its output.

  The tech-talk staple. A command types itself out character by character behind a
  prompt, the console pauses as if thinking, and the output lands line by line.

  A Terminal is, in the end, a VIDEO OF A SESSION — so it wears Video's clothes: a
  centre play button, a transport bar, and a marker per command. A presenter already
  knows what those do.

  THE TYPING IS CSS, NOT A TIMER, and everything else follows from that. A finite
  `@keyframes` animation is also a Web Animations object, so the session can be paused,
  seeked and replayed by moving one clock — no timer to desynchronise from the text, and
  a scrub backwards puts every character back where it was. What a timer-driven
  typewriter cannot do, this can.

  CONTROL comes in two flavours, and they are not the same thing:

    - TRANSPORT (`controls`, default on): play / pause, a click-to-seek track, restart,
      and a tick per command. The session opens HELD at frame 0 behind a play button
      unless `autoplay`.
    - STEPPING (`keys="global"`, opt-in): Space plays forward to the end of the next
      command's output and stops there — you watch it type, it halts, you talk.
      Shift+Space jumps back to the previous stop, and from the first one to the
      beginning. Once the last command is behind the playhead, Space falls through and
      PAGES THE DECK, exactly as a <Steps> build does: the Terminal registers with the
      same `activeSteps` store, so `spaceIntent` arbitrates the handoff, and
      NavigationBar's CONTINUE button and the presenter console's `gp:continue` pulse
      drive it for free.

      Space *plays to* the next checkpoint rather than seeking to it — the deliberate
      difference from <Video>, which jumps. Footage is worth jumping through; a
      typewriter you would never see type. Backwards is a jump, because re-watching a
      command type on the way back is nobody's idea of stepping back.

      Both directions walk the SAME stops: `0` (a blank console) and every checkpoint.
      Shift+Space must undo Space, so it cannot step to a command's *start* — that is a
      state no forward step ever produces, and from the first command's start there is
      nothing earlier, so Shift+Space would page the deck away instead of rewinding.

      Opt-in because only ONE build per slide may own Space (a <Steps> run and a
      stepping Terminal would fight over it and over the store).

  ONE OWNER PER CLOCK. <AnimationBar> collects every finite CSS animation in the slide's
  `.content` — including this one's. With `controls` on, the Terminal drives its own
  playhead, so an AnimationBar on the same slide would fight it (its Play would run
  straight past your markers). Pass `controls={false}` to render a bare console and hand
  the clock back to an AnimationBar. That is the only supported way to combine them.

  Usage:

    <script>
      import Terminal from '$lib/components/Terminal.svelte';
    </script>

    <Terminal
      title="zsh — geekpresent"
      keys="global"
      lines={[
        { cmd: 'pnpm build' },
        { out: 'vite v5.4.2 building SSR bundle...' },
        { out: '✓ 42 modules transformed', tone: 'ok' },
        { out: 'warning: 1 chunk is larger than 500 kB', tone: 'warn' },
      ]}
    />

  A bare string in `lines` is shorthand for an output line. Tones are `ok` / `warn` /
  `error` / `muted` / `plain`; every colour is a roles.css token (`--terminal-*`).

  In normal slide flow the console hugs its content. Wrap it in a <Block> to pin and
  size it — Block fills its content by default, so the console stretches to the box and
  the screen scrolls if the session is taller than the space given.

  Not a code viewer: for syntax-highlighted source use Code / CodeBox (Monaco), and for
  a short static snippet use QuickCode.

  It also renders WHOLE on the server: the transcript is in the markup from props alone,
  and the animation only ever hides what is already there. So a `text` artifact ships the
  full session as static HTML. (A SLIDE'S markup never reaches the static build —
  SlideDeck gates its content behind `initialized` — so that benefit is a Text-artifact
  one. What SSR-safety buys a slide is no mount-time flash.)

  Three CSS/DOM mechanics worth knowing before editing:

    - The reveal is the WIDTH of the typed span, clipped to a whole number of `ch` and
      walked by `steps()`. That only means anything in a monospace font — the premise of
      a console anyway.
    - Every reveal keyframe declares only a `from`. The implicit `to` is the property's
      own cascaded value, so one rule serves every line length and every tone (a muted
      line fades 0 → 0.6, not 0 → 1) without generating per-line keyframes.
    - The caret's blink is INFINITE, so it is excluded from the clock: it keeps blinking
      while the session is paused, which is exactly what a real prompt does.
-->
<script lang="ts">
	import { browser } from '$app/environment';
	import { onDestroy, onMount } from 'svelte';
	import { getMode } from '$lib/presentation';
	import { activeSteps } from '$lib/stores/activeSteps';
	import { kioskActive } from '$lib/stores/kiosk';
	import { spaceIntent } from '$lib/utils/stepKeys';
	// Driving a group of staggered animations is one problem with one implementation,
	// shared with AnimationBar and the presenter console. (Do not inline `a.play()`.)
	import { pauseGroup, playGroup } from '$lib/utils/slideAnim';
	// The track is the same geometry as the Video scrubber's; one implementation.
	import { seekFraction } from '$lib/utils/videoCore';
	import {
		checkpointsOf,
		markersOf,
		nextCheckpoint,
		percentOf,
		prevCheckpoint,
		reachedCount,
		scheduleLines,
		snapTime,
		stepsFor,
		type TerminalInput,
		type TerminalTiming
	} from '$lib/utils/terminalCore';

	/** The session: `{ cmd }` is typed, `{ out }` (or a bare string) is printed. */
	export let lines: TerminalInput[] = [];
	/** The shell prompt drawn before each command. `''` drops it. */
	export let prompt: string = '$';
	/** Title-bar caption. Only shown when `chrome` is on. */
	export let title: string = '';
	/** Fake window chrome: title bar with the three dots. */
	export let chrome: boolean = true;
	/** Type the session out. `false` prints it whole (and is implied by `text` mode). */
	export let typing: boolean = true;
	/** Show the caret: it rides the end of each command as it types, then rests. */
	export let caret: boolean = true;
	/** Our own transport: play/pause, seek track, command ticks, restart. */
	export let controls: boolean = true;
	/** Run the session on load instead of holding it behind the play button. */
	export let autoplay: boolean = false;
	/** `'global'` lets Space/Shift+Space step the session command by command. */
	export let keys: 'global' | 'off' = 'off';
	/** Also step on the presenter console's CONTINUE pulse (gp:continue). Needs `keys`. */
	export let continueKey: boolean = true;
	/** ms per typed character. */
	export let charMs: number = 55;
	/** ms of dead air before the first line. */
	export let startMs: number = 300;
	/** ms the console "thinks" after a command, before its output. */
	export let pauseMs: number = 350;
	/** ms for one output line to fade in. */
	export let outMs: number = 180;
	/** Extra inline CSS appended to the console (e.g. spacing tweaks per slide). */
	export let style: string = '';
	/** DOM id for the root element. */
	export let id: string = '';
	/** Extra class(es) for the root element. NOTE: a slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS (global.css / roles.css / a
	    :global(...) block) or a utility class. See AGENTS.md. */
	let klass: string = '';
	export { klass as class };

	// A `text` artifact is read at the reader's pace, not the presenter's: there is no
	// slide to hold, nothing to scrub, and a line that types itself as you scroll past
	// is just a line you can't read. Print the session whole. (The call Steps makes.)
	const isText = getMode() === 'text';
	const token = {}; // identity for the activeSteps registration

	$: timing = { charMs, startMs, pauseMs, outMs } satisfies TerminalTiming;
	$: schedule = scheduleLines(lines, timing);
	$: markers = markersOf(schedule);
	$: animating = typing && !isText;

	// Never a dead console: with no transport, no stepping and no autoplay there would be
	// nothing left that could ever start the session, so it starts itself. (`degrade,
	// never blank` — the same instinct as WebSite's IntersectionObserver fallback.)
	$: runsItself = autoplay || (!controls && keys === 'off');

	let screenEl: HTMLElement;
	let trackEl: HTMLElement;

	let anims: Animation[] = [];  // the finite CSS animations of THIS session
	let playhead = 0;             // ms into the envelope
	let playing = false;
	let ready = false;            // a real, seekable clock was found
	let target: number | null = null; // where a forward step must stop (null = play on)
	let raf = 0;
	let dragging = false;

	$: duration = schedule.envelopeMs;
	$: fillPct = percentOf(playhead, duration);
	// The ticks ARE the stops: one per command, drawn where Space parks (the end of that
	// command's output), and lit once the playhead has passed it.
	$: checkpoints = checkpointsOf(markers);
	$: reached = reachedCount(markers, playhead);

	// Transport and stepping both need a clock. Reduced motion removes the animations
	// outright (see the media query below), so `ready` goes false and the chrome — which
	// could not drive anything — never renders. No matchMedia needed.
	$: hasTransport = animating && controls && ready && duration > 0;
	// While the kiosk is running it drives the session itself (via the activeSteps build),
	// so the ▶ button is not a gate the viewer must clear — hide it rather than flash a
	// dead play button on a booth screen for the first step's dwell.
	$: showOverlay = hasTransport && !playing && playhead <= 0 && !$kioskActive;

	$: build = {
		hasNext: nextCheckpoint(markers, playhead) !== null,
		hasPrev: prevCheckpoint(markers, playhead) !== null
	};

	// Only the keyboard-owning instance publishes itself, matching who Space would drive.
	$: drivesChrome = browser && animating && ready && keys === 'global' && markers.length > 0;
	$: if (drivesChrome) activeSteps.set({ owner: token, ...build, next: stepNext });

	// --- The clock -------------------------------------------------------------------
	// One group, one playhead. Each animation is clamped to its own end so the staggered
	// delays settle coherently — the same discipline as AnimationBar's seek().

	const endTimeOf = (a: Animation): number => {
		const e = a.effect?.getComputedTiming().endTime;
		return typeof e === 'number' && Number.isFinite(e) ? e : 0;
	};

	function collect() {
		if (!browser || !screenEl || typeof screenEl.getAnimations !== 'function') return;
		// Infinite animations (the caret blink) have no end time, so they fall out here —
		// which is why the caret keeps blinking while the session is paused.
		anims = screenEl.getAnimations({ subtree: true }).filter((a) => endTimeOf(a) > 0);
		ready = anims.length > 0;
	}

	function sample(): number {
		let t = 0;
		for (const a of anims) {
			const ct = typeof a.currentTime === 'number' ? a.currentTime : 0;
			t = Math.max(t, Math.min(ct, endTimeOf(a)));
		}
		return t;
	}

	function seek(t: number) {
		const clamped = Math.max(0, Math.min(t, duration));
		for (const a of anims) a.currentTime = Math.min(clamped, endTimeOf(a));
		playhead = clamped;
	}

	function pauseClock() {
		pauseGroup(anims);
		playing = false;
		target = null;
		stopLoop();
	}

	function playClock() {
		// `playGroup`, never a bare a.play() loop: play() on an animation whose currentTime
		// has reached its end rewinds it to 0 and runs it again. Every line of the session is
		// its own animation with its own end, so resuming at a checkpoint would replay every
		// command already typed, alongside the one now typing. See slideAnim.playGroup.
		playGroup(anims);
		playing = true;
		startLoop();
	}

	function loop() {
		playhead = sample();
		// A forward step stops dead on its checkpoint. Sampling lands a hair past it, so
		// snap back to the exact time — otherwise the stop drifts later every step.
		if (target !== null && playhead >= target) {
			seek(target);
			pauseClock();
			return;
		}
		if (playhead >= duration) {
			seek(duration);
			pauseClock();
			return;
		}
		raf = requestAnimationFrame(loop);
	}
	function startLoop() { if (!raf && browser) raf = requestAnimationFrame(loop); }
	function stopLoop()  { if (raf) { cancelAnimationFrame(raf); raf = 0; } }

	// --- Transport actions -------------------------------------------------------------

	/** Play on to the end of the session (the play button's meaning). */
	export function play() {
		if (!ready) return;
		if (playhead >= duration) seek(0); // a finished session replays from the top
		target = null;
		playClock();
	}
	export function pause() { if (ready) pauseClock(); }
	export function toggle() { playing ? pause() : play(); }
	export function restart() { if (!ready) return; seek(0); pauseClock(); }

	/** Jump to a time and hold there. */
	export function jumpTo(t: number) {
		if (!ready) return;
		pauseClock();
		seek(t);
	}

	/** Play forward to the end of the next command's output, then stop. */
	export function stepNext() {
		if (!ready) return;
		const cp = nextCheckpoint(markers, playhead);
		if (cp === null) return; // spent — Space pages the deck instead
		target = cp;
		playClock();
	}

	/** Jump back to the previous stop — the state the last forward step came from. */
	export function stepPrev() {
		if (!ready) return;
		const stop = prevCheckpoint(markers, playhead);
		if (stop === null) return; // already at the beginning — Shift+Space pages back
		jumpTo(stop);
	}

	// --- Pointer seeking on the track ---------------------------------------------------
	// Click anywhere on the rail to seek; press and drag to scrub. The knob is
	// `pointer-events: none` and the rail carries an invisible grab strip taller than the
	// knob, so pressing the white circle lands on the TRACK and drags — which also means
	// nothing else may sit on the rail and swallow the press. (The ticks are inert marks
	// for exactly that reason: Space parks the playhead ON a tick, so a clickable tick
	// would be sitting under the knob at precisely the moment you reach for it.)
	//
	// The deck owns →/← unconditionally (NavigationBar's window listener), so a scrub bar
	// can never have them; the track is `tabindex="-1"` and `aria-hidden` accordingly.
	//
	// Do NOT reach for Video's `detail === 0` guard here. That one lives on a CLICK
	// handler, where `detail` is the click count and 0 means a keyboard activation
	// carrying no coordinates. On a POINTER event `detail` is always 0 — so the same
	// line here rejects every real press, and the rail goes dead. (It did. Enter never
	// fires pointerdown, so there is nothing for that guard to catch anyway.)
	//
	// A scrub PAUSES, as AnimationBar's does: the playhead is following the pointer now.

	/** Snap a seek to a tick within this fraction of the envelope. */
	const SNAP = 0.015;

	function timeAt(clientX: number): number {
		if (!trackEl) return 0;
		const raw = seekFraction(clientX, trackEl.getBoundingClientRect()) * duration;
		return snapTime(raw, checkpoints, duration * SNAP);
	}
	function onTrackDown(e: PointerEvent) {
		// Primary button only, and only the first finger of a multi-touch gesture.
		if (e.button !== 0 || e.isPrimary === false) return;
		dragging = true;
		pauseClock();
		seek(timeAt(e.clientX));
		trackEl.setPointerCapture?.(e.pointerId);
	}
	function onTrackMove(e: PointerEvent) { if (dragging) seek(timeAt(e.clientX)); }
	function onTrackUp(e: PointerEvent) {
		dragging = false;
		trackEl.releasePointerCapture?.(e.pointerId);
	}

	// --- Keyboard -----------------------------------------------------------------------

	function onKeydown(e: KeyboardEvent) {
		// Both this listener and NavigationBar's ask the same question of the same build
		// state, so their firing order cannot matter. With no clock there is no build —
		// otherwise `hasNext` would claim a step we cannot take, and Space would neither
		// step nor page, trapping the presenter on the slide.
		const intent = spaceIntent(e, ready ? build : null);
		if (intent === 'reveal') { e.preventDefault(); stepNext(); }
		else if (intent === 'peel') { e.preventDefault(); stepPrev(); }
	}
	function onContinue() { stepNext(); }

	onMount(() => {
		if (!animating) return;
		// getAnimations() flushes style, so the animations normally exist by the time
		// onMount runs — i.e. before first paint, so a held session never types a frame.
		// They can still attach a frame late (AnimationBar hits the same), and a frame of
		// the opening `startMs` dead air shows nothing anyway. Look once more, then give up
		// and let the session run uncontrolled rather than freeze it.
		const take = () => {
			collect();
			if (!ready) return;
			if (runsItself) { playing = true; startLoop(); }
			else { seek(0); pauseClock(); }
		};
		collect();
		if (ready) take();
		else requestAnimationFrame(take);

		if (browser && keys === 'global') {
			window.addEventListener('keydown', onKeydown);
			if (continueKey) window.addEventListener('gp:continue', onContinue);
		}
	});

	onDestroy(() => {
		stopLoop();
		if (browser && keys === 'global') {
			window.removeEventListener('keydown', onKeydown);
			window.removeEventListener('gp:continue', onContinue);
		}
		// Only clear the store if we are still the registered build (a later one may own it).
		activeSteps.update((v) => (v && v.owner === token ? null : v));
	});

	// A typed command reveals by growing its own width in whole characters, so the
	// timing function needs the character count. Everything else is plain ms.
	const typedStyle = (chars: number, delayMs: number, durationMs: number) =>
		`--n:${chars}; animation-delay:${delayMs}ms; animation-duration:${durationMs}ms;` +
		` animation-timing-function: steps(${stepsFor(chars)}, end);`;

	// The row itself only fades in. A command's row appears the instant it starts
	// typing (1ms — the prompt should not fade in), an output line takes its `outMs`.
	const rowStyle = (kind: 'cmd' | 'out', delayMs: number, durationMs: number) =>
		`animation-delay:${delayMs}ms; animation-duration:${kind === 'cmd' ? 1 : durationMs}ms;`;
</script>

<!-- NOTE: command rows are `white-space: pre`, so the markup below is packed tight —
     a newline between the prompt and the typed span would render as a space. -->
<div class="terminal {klass}" class:anim={animating} id={id || undefined} {style}>
	{#if chrome}
		<div class="bar">
			<span class="dots" aria-hidden="true"><i></i><i></i><i></i></span>
			{#if title}<span class="title">{title}</span>{/if}
		</div>
	{/if}

	<div class="stage">
		<div class="screen" bind:this={screenEl}>
			{#each schedule.lines as line, i (i)}
				{#if line.kind === 'cmd'}
					<div class="line cmd" style={rowStyle('cmd', line.delayMs, line.durationMs)}>{#if prompt}<span
								class="prompt"
								aria-hidden="true">{prompt}</span>{/if}<span
							class="typed"
							style={typedStyle(line.chars, line.delayMs, line.durationMs)}>{line.text}</span>{#if caret && animating}<span
							class="gate"
							style="animation-delay:{line.delayMs}ms; animation-duration:{line.durationMs}ms;"
							aria-hidden="true"><span class="caret"></span></span>{/if}</div>
				{:else}
					<div class="line out tone-{line.tone}" style={rowStyle('out', line.delayMs, line.durationMs)}>{line.text}</div>
				{/if}
			{/each}

			{#if caret}
				<!-- The resting caret on a fresh prompt: where the session leaves the machine. The
				     ROW waits out the envelope too — otherwise its `$` (duration 0s, fill both →
				     already finished) would sit under the blank transcript from the first frame. -->
				<div class="line cmd rest" style={rowStyle('cmd', schedule.envelopeMs, 1)}>{#if prompt}<span class="prompt" aria-hidden="true">{prompt}</span>{/if}<span
						class="gate rest-gate"
						style="animation-delay:{schedule.envelopeMs}ms;"
						aria-hidden="true"><span class="caret"></span></span></div>
			{/if}
		</div>

		{#if showOverlay}
			<!-- The one-shot start. It UNMOUNTS on play, which also releases focus back to the
			     body — so the presenter's next Space steps the session instead of re-pressing
			     this button (a focused <button> keeps Space's native meaning, by design:
			     see stepKeys.isInteractiveTarget). -->
			<button class="overlay" on:click={play} aria-label="Play the session">
				<span class="disc" aria-hidden="true">
					<svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z" /></svg>
				</span>
			</button>
		{/if}
	</div>

	{#if hasTransport}
		<div class="transport">
			<button class="icon" on:click={toggle} aria-label={playing ? 'Pause' : 'Play'}>
				{#if playing}
					<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z" /></svg>
				{:else}
					<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8 5v14l11-7z" /></svg>
				{/if}
			</button>

			<!-- Pointer-only, like Video's: tabindex -1 + aria-hidden, because the deck's
			     arrow keys are spoken for and a scrub bar that answered Enter would rewind. -->
			<div
				class="track"
				bind:this={trackEl}
				tabindex="-1"
				aria-hidden="true"
				on:pointerdown={onTrackDown}
				on:pointermove={onTrackMove}
				on:pointerup={onTrackUp}
			>
				<div class="fill" style="width:{fillPct}%"></div>
				{#each checkpoints as cp, i (i)}
					<!-- A tick per command, drawn at the STOP it represents — the end of that
					     command's output, which is exactly where Space parks. (Drawn at the
					     commands' STARTS instead, the first Space looks like it skips the first
					     tick: it halts at the first command's end, which sits under the SECOND
					     tick.) The last tick is therefore the end of the session.

					     An inert MARK, like Video's, never a button: the knob parks on a tick
					     after every step, and a clickable tick there would eat the press meant
					     for the knob. A click near one lands on it anyway, via `snapTime`. No
					     chapter LIST either: unlike a video's, a terminal's chapters are already
					     on screen — printing them again would be noise. -->
					<div
						class="tick"
						class:active={i < reached}
						style="left:{percentOf(cp, duration)}%"
						aria-hidden="true"
					></div>
				{/each}
				<div class="knob" style="left:{fillPct}%"></div>
			</div>

			<button class="icon" on:click={restart} aria-label="Restart">
				<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5V1L7 6l5 5V7c3.31 0 6 2.69 6 6s-2.69 6-6 6-6-2.69-6-6H4c0 4.42 3.58 8 8 8s8-3.58 8-8-3.58-8-8-8z" /></svg>
			</button>
		</div>
	{/if}
</div>

<style>
	.terminal {
		/* One row height, shared by the screen's line-height and by the inline-blocks
		   that must sit on that same rhythm (the clipped span and the caret gate). */
		--row-h: 1.65em;

		display: flex;
		flex-direction: column;
		box-sizing: border-box;
		height: 100%;
		min-height: 0;
		/* The console stays dark in every theme — like Video's letterbox, this is a
		   screen being shown, not a surface being themed. */
		background: var(--terminal-bg, #0c0c0c);
		color: var(--terminal-fg, #e6edf3);
		border: 1px solid color-mix(in srgb, var(--terminal-border, #cccccc) 35%, transparent);
		border-radius: 8px;
		overflow: hidden;
		font-family: 'Fira Code', monospace;
		font-size: 0.85em;
		text-align: left;
	}

	.bar {
		flex: 0 0 auto;
		display: flex;
		align-items: center;
		gap: 0.8em;
		padding: 0.45em 0.8em;
		background: var(--terminal-chrome-bg, #1e1e1e);
		color: var(--terminal-chrome-fg, #c0f1ff);
		border-bottom: 1px solid color-mix(in srgb, var(--terminal-border, #cccccc) 25%, transparent);
	}
	.dots {
		display: inline-flex;
		gap: 0.4em;
		flex: 0 0 auto;
	}
	.dots i {
		width: 0.72em;
		height: 0.72em;
		border-radius: 50%;
		background: currentColor;
		opacity: 0.32;
	}
	.title {
		font-size: 0.85em;
		opacity: 0.75;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	/* The screen, plus the overlay that sits over it. */
	.stage {
		position: relative;
		flex: 1 1 auto;
		min-height: 0;
		display: flex;
	}
	.screen {
		flex: 1 1 auto;
		min-height: 0;
		overflow: auto;
		padding: 0.7em 1em;
		line-height: var(--row-h);
	}

	/* Output wraps like a real console; a command must not (its reveal is a width). */
	.line {
		white-space: pre-wrap;
		word-break: break-word;
	}
	.line.cmd {
		white-space: pre;
	}
	.line.rest {
		min-height: var(--row-h);
	}

	.prompt {
		margin-right: 0.6ch;
		color: var(--terminal-prompt, #00b356);
		font-weight: bold;
	}

	/* `overflow: hidden` makes an inline-block's baseline its bottom margin edge, which
	   would sink the typed text below the prompt. Pinning the box to exactly one row
	   and aligning its TOP sidesteps the baseline entirely: the inner line box then
	   lines up with the row's, so prompt and command share a baseline again. */
	.typed,
	.gate {
		display: inline-block;
		height: var(--row-h);
		line-height: var(--row-h);
		vertical-align: top;
	}
	.typed {
		white-space: pre;
		overflow: hidden;
	}
	.anim .typed {
		width: calc(var(--n) * 1ch);
		animation-name: terminal-type;
		animation-fill-mode: both;
	}
	@keyframes terminal-type {
		from {
			width: 0;
		}
	}

	.anim .line {
		animation-name: terminal-in;
		animation-fill-mode: both;
		animation-timing-function: linear;
	}
	@keyframes terminal-in {
		from {
			opacity: 0;
		}
	}

	.tone-ok {
		color: var(--terminal-ok, #00b356);
	}
	.tone-warn {
		color: var(--terminal-warn, #f0a33e);
	}
	.tone-error {
		color: var(--terminal-error, #e5484d);
	}
	.tone-muted {
		opacity: 0.6;
	}

	/* The caret rides the end of the typed text for free: `.typed` is an inline-block
	   whose width grows, so a caret next to it in flow tracks the last character.

	   The gate is a WINDOW — it animates `visibility: visible` under fill-mode `none`,
	   so the caret exists only between its command's start and end, then vanishes with
	   the command it belongs to. The resting gate instead fills `forwards`: it opens at
	   the end of the session and stays. The inner span blinks on `opacity`, a different
	   property, so the two animations never fight over one declaration. */
	.gate {
		visibility: hidden;
	}
	.anim .gate {
		animation-name: terminal-caret-window;
		animation-fill-mode: none;
		animation-timing-function: steps(1, end);
	}
	.anim .rest-gate {
		animation-name: terminal-caret-rest;
		animation-fill-mode: forwards;
		animation-duration: 1ms;
	}
	/* Static console (typing={false} / text mode): nothing animates, so the resting
	   caret is simply present, and the per-command carets are never rendered at all. */
	.terminal:not(.anim) .rest-gate {
		visibility: visible;
	}
	@keyframes terminal-caret-window {
		from {
			visibility: visible;
		}
		to {
			visibility: visible;
		}
	}
	@keyframes terminal-caret-rest {
		to {
			visibility: visible;
		}
	}

	.caret {
		display: inline-block;
		width: 0.6ch;
		height: 1.05em;
		vertical-align: middle;
		background: var(--terminal-caret, #00b356);
		/* Infinite, so it is excluded from the clock: the caret keeps blinking while the
		   session is paused, exactly as a real prompt does. */
		animation: terminal-blink 1.06s steps(1, end) infinite;
	}
	@keyframes terminal-blink {
		50% {
			opacity: 0;
		}
	}

	/* --- The centre play button ------------------------------------------------------ */
	.overlay {
		position: absolute;
		inset: 0;
		display: grid;
		place-items: center;
		padding: 0;
		border: 0;
		cursor: pointer;
		background: color-mix(in srgb, var(--terminal-bg, #0c0c0c) 55%, transparent);
	}
	.disc {
		display: grid;
		place-items: center;
		width: 3.4em;
		height: 3.4em;
		border-radius: 50%;
		color: var(--on-accent, #ffffff);
		background: color-mix(in srgb, var(--terminal-accent, #2980b9) 85%, transparent);
		transition: transform 120ms ease-out;
	}
	.overlay:hover .disc {
		transform: scale(1.08);
	}
	.overlay:focus-visible {
		outline: 2px solid var(--terminal-accent, #2980b9);
		outline-offset: -4px;
	}
	.disc svg {
		width: 1.6em;
		height: 1.6em;
		margin-left: 0.15em; /* optical centre of a triangle */
		fill: currentColor;
	}

	/* --- The transport ---------------------------------------------------------------- */
	.transport {
		flex: 0 0 auto;
		display: flex;
		align-items: center;
		gap: 0.7em;
		padding: 0.35em 0.8em 0.45em;
		background: var(--terminal-chrome-bg, #1e1e1e);
		color: var(--terminal-chrome-fg, #c0f1ff);
		border-top: 1px solid color-mix(in srgb, var(--terminal-border, #cccccc) 25%, transparent);
	}
	.icon {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		flex: none;
		width: 1.9em;
		height: 1.9em;
		padding: 0;
		cursor: pointer;
		color: currentColor;
		background: transparent;
		border: 0;
		border-radius: 5px;
	}
	.icon:hover {
		color: var(--on-accent, #ffffff);
		background: var(--terminal-accent, #2980b9);
	}
	.icon:focus-visible {
		outline: 2px solid var(--terminal-accent, #2980b9);
		outline-offset: 1px;
	}
	.icon svg {
		display: block;
		width: 1.15em;
		height: 1.15em;
		fill: currentColor;
	}
	.track {
		position: relative;
		flex: 1;
		height: 0.3em;
		border-radius: 999px;
		background: color-mix(in srgb, var(--terminal-track, #e6edf3) 22%, transparent);
		cursor: pointer;
		touch-action: none; /* we own the horizontal drag */
	}
	/* Invisible grab strip: the rail is thin but the knob is not, so extend the pointer
	   target vertically past the knob without thickening the rail. */
	.track::before {
		content: '';
		position: absolute;
		left: 0;
		right: 0;
		top: 50%;
		height: 1.3em;
		transform: translateY(-50%);
	}
	.fill {
		position: absolute;
		left: 0;
		top: 0;
		height: 100%;
		border-radius: 999px;
		background: var(--terminal-accent, #2980b9);
	}
	.knob {
		position: absolute;
		top: 50%;
		width: 0.68em;
		height: 0.68em;
		border-radius: 50%;
		background: var(--on-accent, #ffffff);
		border: 2px solid var(--terminal-accent, #2980b9);
		transform: translate(-50%, -50%);
		pointer-events: none;
	}
	/* One tick per command: where the session stops if you keep pressing Space. A MARK,
	   never a target — it must not intercept the press that grabs the knob parked on it. */
	.tick {
		position: absolute;
		top: 50%;
		width: 0.34em;
		height: 1em;
		border-radius: 2px;
		transform: translate(-50%, -50%);
		pointer-events: none;
		background: color-mix(in srgb, var(--terminal-track, #e6edf3) 65%, transparent);
	}
	.tick.active {
		background: var(--terminal-caret, #00b356);
	}

	/* A reader who asked for less motion gets the finished session, not a slow one.
	   Removing the animations also empties the clock, so `ready` stays false and the
	   transport — which would have nothing to drive — never renders.
	   Selectors mirror the animating rules so they win on source order, not weight. */
	@media (prefers-reduced-motion: reduce) {
		.anim .typed {
			width: auto;
			animation-name: none;
		}
		.anim .line {
			animation-name: none;
		}
		.anim .gate {
			animation-name: none;
		}
		.anim .rest-gate {
			visibility: visible;
		}
		.caret {
			animation-name: none;
		}
	}
</style>
