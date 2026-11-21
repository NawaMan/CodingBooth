<!--
  StepDots — "this slide is a build, and here is how far in".

  A canvas-level singleton, like Spotlight: SlideDeck mounts it once and no slide
  places it. It reads the `activeSteps` store, which every Space-driven build
  registers with (a <Steps> run of Fragments, a Terminal with keys="global", a
  Video stepping its chapters), so whichever kind of build the slide has, the same
  row of dots appears near the bottom of the canvas (or at any edge or corner —
  `position`, set from SlideDeck's `stepDotsAt` or a slide's `stepDots` entry):

    ● ● ◉ ○ ○      filled = taken, the larger one = just taken, ring = still to come

  At rest it is faint, so it never competes with the slide. On arrival and on every
  step it brightens for a moment and settles back. When the last step is taken all
  the dots fill and the row fades out entirely — the speaker's cue that the next
  Space pages the deck. Above STEP_DOTS_MAX steps it draws one segmented bar instead.

  THE CUE. Once the build has sat still for `cueDelayMs` (a second) — the step taken AND
  done playing, per the build's `busy` report — the row comes up to full strength, the
  next dot blinks, and a tooltip says "SPACE for next step"; once every step is taken it
  says "SPACE for next slide" instead (and only when there is one). It clears the moment
  the next step is taken. SlideDeck switches it off in kiosk mode, while a presenter
  console is live, while recording or replaying, and with `stepCue: false`. Reduced
  motion: no blink, tooltip only. Tokens: --stepdots-cue, --stepdots-cue-bg/-fg.

  THE AUTO LEVELS (`auto`, from SlideDeck; auto/stepAutoCore.ts). Where the deck's author
  gave a wait, the "next step" cue is also a control. `normal`: it ends in a round
  countdown — the seconds left, on their own background — and the step is taken when it
  runs out; a click holds it. `pause`: the round shows pause bars and a click releases
  it. Resting the pointer on it freezes the countdown. The "next slide" cue never counts:
  the page turn is the viewer's. With no wait set (`manual`) the cue is exactly as above.
  The countdown itself is SlideDeck's (auto/stepTimer.ts); this only draws
  `stepCountdown`. Tokens: --stepdots-count-bg/-fg/-spent, --stepdots-count-held-bg.

  Renders nothing without a build (or in SSR, where no build has registered), so a
  slide with no Steps is untouched. Tagged `no-print`, so CAPTURE, print and `?shot`
  leave it out like the rest of the chrome — but deliberately NOT `gp-chrome`: that
  marker would let `fadeChrome` ghost an already-faint row into nothing. SlideDeck
  also holds it back under `?clean`. Opt out with `<SlideDeck stepDots={false}>` for a deck or
  `stepDots: false` on a pages.ts entry for one slide.

  Anchored with `top`, not `bottom`: canvas-space chrome anchored to the far edge
  misprints (see the handout notes in AGENTS.md), so it stays left/top like the rest.

  Role tokens (themes/roles.css): --stepdots-fg, --stepdots-idle, --stepdots-size,
  --stepdots-gap, --stepdots-inset. Maths in utils/stepDotsCore.ts.
-->
<script lang="ts">
	import { onDestroy } from 'svelte';
	import { activeSteps } from '$lib/stores/activeSteps';
	import {
		STEP_CUE_DELAY_MS,
		STEP_CUE_NEXT,
		STEP_CUE_SPENT,
		stepCue,
		stepDotsView,
		stepDotsLabel,
		stepDotsPlacement,
		stepDotsAnchorStyle,
		type StepDotsPosition
	} from '$lib/utils/stepDotsCore';
	import {
		STEP_AUTO_HOLD,
		STEP_AUTO_RESUME,
		secondsLeft,
		type StepAuto
	} from '$lib/auto/stepAutoCore';
	import { countdownLeft } from '$lib/auto/stepTimer';
	import { stepCountdown, stepHoverFrozen, toggleStepHold } from '$lib/stores/stepAuto';

	/** Canvas size, to anchor the row against the chosen edge. */
	export let canvasWidth = 1920;
	export let canvasHeight = 1080;
	/** Which edge (its midpoint) or corner the row sits at. On 'left' / 'right' the
	    row stands up and runs along that edge. Unknown values fall back to 'bottom'. */
	export let position: StepDotsPosition = 'bottom';
	/** Cue the speaker once the build is waiting for Space: the next dot blinks and a
	    tooltip says so. SlideDeck turns it off where no speaker should see it (kiosk, a
	    live console, a recording, `stepCue: false`). */
	export let cue: boolean = false;
	/** How long the build must sit still before the cue shows. */
	export let cueDelayMs: number = STEP_CUE_DELAY_MS;
	/** The tooltip while a step remains. */
	export let cueNext: string = STEP_CUE_NEXT;
	/** The tooltip once every step is taken (only when there is a next slide). */
	export let cueSpent: string = STEP_CUE_SPENT;
	/** The auto level here (auto/stepAutoCore.ts). In `normal` the "next step" cue ends in
	    a round countdown and a click holds it; in `pause` the round shows it is held and a
	    click releases it. `manual` (no wait set) and `kiosk` leave the cue as it always
	    was: nothing to count, nothing to click. */
	export let auto: StepAuto = 'manual';
	/** The cue's tooltips in the two toggleable levels. */
	export let autoHold: string = STEP_AUTO_HOLD;
	export let autoResume: string = STEP_AUTO_RESUME;
	/** Is there a slide for a spent build's Space to page to? */
	export let hasNextSlide: boolean = true;
	/** Inline style for the root element, applied last so it wins. */
	export let style: string = '';
	/** DOM id for the root element. */
	export let id: string = '';
	/** Extra class(es) for the root element. */
	let klass: string = '';
	export { klass as class };

	$: view = stepDotsView($activeSteps?.index, $activeSteps?.total);
	$: placement = stepDotsPlacement(position);
	$: busy = !!$activeSteps?.busy;

	// `settled`: the build has sat still for `cueDelayMs` since its last change (a step,
	// a step finishing). Any change restarts the wait.
	let settled = false;
	let timer: ReturnType<typeof setTimeout> | undefined;
	$: restartCue(cue, view.kind, view.kind === 'none' ? 0 : view.index, busy);
	function restartCue(on: boolean, kind: string, _index: number, isBusy: boolean) {
		settled = false;
		clearTimeout(timer);
		if (on && kind !== 'none' && !isBusy) timer = setTimeout(() => (settled = true), cueDelayMs);
	}
	onDestroy(() => clearTimeout(timer));

	$: cueState = cue ? stepCue(view, { busy, settled, hasNextSlide }) : 'none';

	// The cue as a control: only the "next step" one, and only where the author gave a
	// wait. The countdown belongs to the step, never to the page turn.
	$: toggles = cueState === 'next' && (auto === 'normal' || auto === 'pause');
	$: counting = toggles && auto === 'normal' && $stepCountdown !== null;
	// The pointer leaves no `mouseleave` behind when the cue goes away under it.
	$: if (!toggles) stepHoverFrozen.set(false);

	// A click must not leave the button focused: Space is not a step while a button has
	// focus (utils/stepKeys.ts), and the viewer's next Space has to be one.
	function onToggle(e: MouseEvent) {
		toggleStepHold();
		(e.currentTarget as HTMLElement | null)?.blur();
	}

	// The seconds left, re-read a few times a second while a countdown runs. The sweep
	// is CSS; only the number needs a clock.
	let nowMs = Date.now();
	let ticker: ReturnType<typeof setInterval> | undefined;
	$: watch(counting && !!$stepCountdown?.running);
	function watch(on: boolean) {
		clearInterval(ticker);
		ticker = undefined;
		nowMs = Date.now();
		if (on) ticker = setInterval(() => (nowMs = Date.now()), 200);
	}
	onDestroy(() => {
		clearInterval(ticker);
		stepHoverFrozen.set(false);
	});
	$: seconds = secondsLeft(countdownLeft($stepCountdown, nowMs));
	// The sweep starts where the countdown stands, and stops with it.
	$: sweep = $stepCountdown
		? `animation-duration:${$stepCountdown.totalMs}ms;` +
			` animation-delay:${-($stepCountdown.totalMs - $stepCountdown.leftMs)}ms;` +
			` animation-play-state:${$stepCountdown.running ? 'running' : 'paused'};`
		: '';
</script>

{#if view.kind !== 'none'}
	<div
		class="step-dots no-print {klass}"
		class:vertical={placement.vertical}
		class:cueing={cueState !== 'none'}
		class:toggling={toggles}
		data-position={placement.position}
		id={id || undefined}
		role="progressbar"
		aria-valuemin="0"
		aria-valuemax={view.total}
		aria-valuenow={view.index}
		aria-label={stepDotsLabel(view)}
		style="{stepDotsAnchorStyle(placement, canvasWidth, canvasHeight)} {style}"
	>
		<!-- Keyed on the step, so each one restarts the brighten-and-settle animation. -->
		{#key view.index}
			<div class="row" class:spent={view.spent}>
				{#if view.kind === 'dots'}
					{#each view.dots as dot, i}
						<span class="dot {dot}" class:next={cueState === 'next' && i === view.index}></span>
					{/each}
				{:else}
					<span class="bar" class:next={cueState === 'next'}>
						<span
							class="fill"
							style="{placement.vertical ? 'height' : 'width'}: {(view.fraction * 100).toFixed(3)}%"
						></span>
					</span>
				{/if}
			</div>
		{/key}
		{#if toggles}
			<!-- The one part of the indicator that takes the pointer: hold or release the
			     auto-step. Resting on it freezes the countdown, so it cannot step out from
			     under the click. -->
			<button
				type="button"
				class="cue-tip toggle"
				class:held={auto === 'pause'}
				aria-pressed={auto === 'pause'}
				aria-label="{cueNext}. {auto === 'pause' ? autoResume : autoHold}"
				title={auto === 'pause' ? autoResume : autoHold}
				on:mousedown|preventDefault
				on:click={onToggle}
				on:mouseenter={() => stepHoverFrozen.set(true)}
				on:mouseleave={() => stepHoverFrozen.set(false)}
			>
				{cueNext}
				{#if counting}
					{#key $stepCountdown?.seq}
						<span class="count" aria-hidden="true"
							><span class="sweep" style={sweep}></span><span class="num">{seconds}</span></span
						>
					{/key}
				{:else}
					<span class="count held" aria-hidden="true"><span class="bars"></span></span>
				{/if}
			</button>
		{:else if cueState !== 'none'}
			<span class="cue-tip" aria-hidden="true">{cueState === 'next' ? cueNext : cueSpent}</span>
		{/if}
	</div>
{/if}

<style>
	.step-dots {
		position: absolute;
		z-index: 30;
		pointer-events: none;
		color: var(--stepdots-fg, #c0f1ff);
	}
	.row {
		display: flex;
		align-items: center;
		gap: var(--stepdots-gap, 14px);
		opacity: var(--stepdots-idle, 0.3);
		animation: stepdots-pulse 1.6s ease-out;
	}
	.row.spent {
		opacity: 0;
		animation: stepdots-spent 2.2s ease-in;
	}
	.vertical .row {
		flex-direction: column;
	}
	.dot {
		box-sizing: border-box;
		width: var(--stepdots-size, 12px);
		height: var(--stepdots-size, 12px);
		border-radius: 50%;
		border: 2px solid currentColor;
		transition:
			transform 240ms ease,
			background-color 240ms ease;
	}
	.dot.done,
	.dot.current {
		background: currentColor;
	}
	.dot.current {
		transform: scale(1.35);
	}
	.bar {
		display: block;
		width: 240px;
		height: calc(var(--stepdots-size, 12px) / 2);
		border-radius: 999px;
		background: color-mix(in srgb, currentColor 30%, transparent);
		overflow: hidden;
	}
	.vertical .bar {
		width: calc(var(--stepdots-size, 12px) / 2);
		height: 240px;
	}
	.fill {
		display: block;
		height: 100%;
		background: currentColor;
		transition:
			width 240ms ease,
			height 240ms ease;
	}
	.vertical .fill {
		width: 100%;
	}

	/* The cue: the row comes up to full strength (a spent one stops fading out), the next
	   dot blinks, and the tooltip sits beside the row on the canvas side of it. */
	.step-dots.cueing .row {
		opacity: 1;
		animation: none;
	}
	.dot.next {
		color: var(--stepdots-cue, #ffb84d);
		animation: stepdots-blink 1s ease-in-out infinite;
	}
	.bar.next {
		animation: stepdots-blink 1s ease-in-out infinite;
	}
	.cue-tip {
		position: absolute;
		white-space: nowrap;
		padding: 2px 10px;
		border-radius: 999px;
		font-size: 22px;
		font-weight: 600;
		letter-spacing: 0.04em;
		background: var(--stepdots-cue-bg, rgba(0, 0, 0, 0.78));
		color: var(--stepdots-cue-fg, #ffb84d);
		animation: stepdots-tip-in 240ms ease-out;
	}
	[data-position^='bottom'] .cue-tip {
		bottom: calc(100% + 14px);
	}
	[data-position^='top'] .cue-tip {
		top: calc(100% + 14px);
	}
	[data-position='bottom'] .cue-tip,
	[data-position='top'] .cue-tip {
		left: 50%;
		transform: translateX(-50%);
	}
	[data-position$='-left'] .cue-tip {
		left: 0;
	}
	[data-position$='-right'] .cue-tip {
		right: 0;
	}
	[data-position='left'] .cue-tip,
	[data-position='right'] .cue-tip {
		top: 50%;
		transform: translateY(-50%);
	}
	[data-position='left'] .cue-tip {
		left: calc(100% + 14px);
	}
	[data-position='right'] .cue-tip {
		right: calc(100% + 14px);
	}

	/* The cue as a control (auto levels). Above the ANNOTATE ink surface (40) while it
	   can be clicked, or an armed pen would take the click. */
	.step-dots.toggling {
		z-index: 44;
	}
	.cue-tip.toggle {
		display: inline-flex;
		align-items: center;
		gap: 8px;
		padding-right: 6px;
		border: 0;
		margin: 0;
		font-family: inherit;
		cursor: pointer;
		pointer-events: auto;
	}
	.cue-tip.toggle:focus-visible {
		outline: 3px solid var(--stepdots-cue, #ffb84d);
		outline-offset: 3px;
	}
	/* The round area at the end of the sentence: the seconds left, on its own
	   background, with a sweep that empties as the wait runs out. */
	.count {
		position: relative;
		display: inline-grid;
		place-items: center;
		font-size: 0.78em;
		width: 1.2em;
		height: 1.2em;
		border-radius: 50%;
		overflow: hidden;
		background: var(--stepdots-count-bg, #ffb84d);
		color: var(--stepdots-count-fg, #181818);
		font-variant-numeric: tabular-nums;
		line-height: 1;
	}
	.sweep {
		position: absolute;
		inset: 0;
		background: var(--stepdots-count-spent, rgba(0, 0, 0, 0.28));
		transform-origin: 50% 100%;
		transform: scaleY(0);
		animation: stepdots-count-drain linear both;
	}
	.num {
		position: relative;
	}
	/* Held: the same round, dimmed, with pause bars where the number was. */
	.count.held {
		background: var(--stepdots-count-held-bg, rgba(255, 255, 255, 0.16));
		color: var(--stepdots-cue-fg, #ffb84d);
	}
	.bars {
		width: 0.5em;
		height: 0.7em;
		border-left: 0.17em solid currentColor;
		border-right: 0.17em solid currentColor;
		box-sizing: border-box;
	}
	@keyframes stepdots-count-drain {
		from {
			transform: scaleY(0);
		}
		to {
			transform: scaleY(1);
		}
	}

	@keyframes stepdots-blink {
		0%,
		100% {
			opacity: 1;
			background-color: currentColor;
		}
		50% {
			opacity: 0.25;
			background-color: transparent;
		}
	}
	@keyframes stepdots-tip-in {
		from {
			opacity: 0;
		}
	}

	@keyframes stepdots-pulse {
		0%,
		50% {
			opacity: 1;
		}
		100% {
			opacity: var(--stepdots-idle, 0.3);
		}
	}
	@keyframes stepdots-spent {
		0%,
		50% {
			opacity: 1;
		}
		100% {
			opacity: 0;
		}
	}

	/* No flashing for a viewer who asked for less motion: the row sits at its rest
	   opacity, and a finished build simply stays there, all filled. */
	@media (prefers-reduced-motion: reduce) {
		.row,
		.row.spent {
			animation: none;
			opacity: var(--stepdots-idle, 0.3);
		}
		.dot,
		.fill {
			transition: none;
		}
		/* The cue still shows — tooltip, full-strength row, the next dot in the cue colour —
		   it just doesn't blink. */
		.dot.next,
		.bar.next,
		.cue-tip {
			animation: none;
		}
		/* The number still counts; only the sweep is dropped. */
		.sweep {
			display: none;
		}
		.step-dots.cueing .row {
			opacity: 1;
		}
	}
</style>
