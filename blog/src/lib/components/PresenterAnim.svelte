<!--
  PresenterAnim — the presenter console's ANIMATE control.

  Unlike AnimationBar (which lives in a slide and controls only THAT window), this
  drives the AUDIENCE window. It reads/steers the presenter's OWN local slide
  animations too — they run invisibly here (the slide is visibility:hidden), which
  powers the rail read-out — and on every action relays {playing, fraction} via
  `onCommand`, which SlideDeck publishes on the anim channel for the audience to
  apply (utils/slideAnim.applyState). Renders nothing on a slide with no finite,
  seekable @keyframes animation — same convention as AnimationBar.
-->
<script lang="ts">
	import { browser } from '$app/environment';
	import { afterNavigate } from '$app/navigation';
	import { onMount, onDestroy } from 'svelte';
	import { collectFinite, envelope, sampleFraction, isPlaying, endTimeOf, playGroup, pauseGroup } from '$lib/utils/slideAnim';
	import type { AnimState } from '$lib/utils/slideAnim';

	/** Relay a command to the audience window. */
	export let onCommand: ((cmd: AnimState) => void) | null = null;
	/** Selector for the local slide subtree searched for animations. */
	export let scope = '.content';

	let anims: Animation[] = [];
	let duration = 0;
	let hasAnim = false;
	let playing = false;
	let fraction = 0;
	let track: HTMLElement;
	let raf = 0;

	function collect() {
		if (!browser) return;
		const root = (document.querySelector(scope) ?? document) as Element | Document;
		anims = collectFinite(root);
		duration = envelope(anims);
		hasAnim = anims.length > 0 && duration > 0;
		if (hasAnim) {
			playing = isPlaying(anims);
			fraction = sampleFraction(anims);
		}
	}

	function emit() {
		onCommand?.({ playing, fraction });
	}

	function loop() {
		fraction = sampleFraction(anims);
		if (playing && !anims.every((a) => a.playState === 'finished')) {
			raf = requestAnimationFrame(loop);
		} else {
			if (anims.length && anims.every((a) => a.playState === 'finished')) { playing = false; fraction = 1; emit(); }
			raf = 0;
		}
	}
	function startLoop() { if (!raf && browser) raf = requestAnimationFrame(loop); }
	function stopLoop() { if (raf) { cancelAnimationFrame(raf); raf = 0; } }

	function seekTo(f: number) {
		fraction = Math.max(0, Math.min(1, f));
		const t = fraction * duration;
		for (const a of anims) a.currentTime = Math.min(t, endTimeOf(a));
	}

	function play() {
		// Judge "spent" on the playhead, not playState: a scrubbed-to-the-end group is
		// *paused* at its end, never 'finished', and playGroup will not restart it.
		if (sampleFraction(anims) >= 1) seekTo(0);
		// Not a bare a.play() loop: that rewinds any animation already at its end, and a
		// staggered reveal (drawDelay) is full of them mid-timeline. See slideAnim.playGroup.
		playGroup(anims);
		playing = true;
		startLoop();
		emit();
	}
	function pause() {
		pauseGroup(anims);
		playing = false;
		stopLoop();
		emit();
	}
	function toggle() { playing ? pause() : play(); }
	function restart() { seekTo(0); play(); }

	// --- scrubbing: pointer x on the rail -> fraction, dragging detaches from clock
	let dragging = false;
	function fracAt(clientX: number): number {
		const r = track.getBoundingClientRect();
		return (clientX - r.left) / r.width;
	}
	function onPointerDown(e: PointerEvent) {
		dragging = true;
		pause();
		seekTo(fracAt(e.clientX));
		emit();
		// Optional, like the release below: pointer capture is a nicety for dragging past the
		// rail's edge, not a requirement, and it is absent in some environments.
		track.setPointerCapture?.(e.pointerId);
	}
	function onPointerMove(e: PointerEvent) { if (dragging) { seekTo(fracAt(e.clientX)); emit(); } }
	function onPointerUp(e: PointerEvent) {
		dragging = false;
		track.releasePointerCapture?.(e.pointerId);
	}

	function refresh() {
		stopLoop();
		collect();
		// CSS animations can attach a frame after paint — look once more if empty.
		if (!hasAnim) requestAnimationFrame(collect);
		else if (playing) startLoop();
	}

	onMount(refresh);
	afterNavigate(refresh);
	onDestroy(stopLoop);
</script>

{#if hasAnim}
<div class="anim">
	<button class="icon" aria-label={playing ? 'Pause' : 'Play'} on:click={toggle}>
		{#if playing}
			<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z" /></svg>
		{:else}
			<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8 5v14l11-7z" /></svg>
		{/if}
	</button>
	<div
		class="track"
		bind:this={track}
		role="slider"
		tabindex="0"
		aria-label="Animation progress (audience)"
		aria-valuemin={0}
		aria-valuemax={100}
		aria-valuenow={Math.round(fraction * 100)}
		on:pointerdown={onPointerDown}
		on:pointermove={onPointerMove}
		on:pointerup={onPointerUp}
	>
		<div class="fill" style="width:{fraction * 100}%"></div>
		<div class="knob" style="left:{fraction * 100}%"></div>
	</div>
	<button class="icon" aria-label="Restart" on:click={restart}>
		<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5V1L7 6l5 5V7c3.31 0 6 2.69 6 6s-2.69 6-6 6-6-2.69-6-6H4c0 4.42 3.58 8 8 8s8-3.58 8-8-3.58-8-8-8z" /></svg>
	</button>
	<span class="label">ANIMATE</span>
</div>
{/if}

<style>
	.anim {
		display: flex;
		align-items: center;
		gap: 8px;
		min-width: 220px;
	}
	.icon {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		flex: none;
		width: 34px;
		height: 34px;
		padding: 0;
		cursor: pointer;
		color: #9aa7b0;
		background: #20262e;
		border: 0;
		border-radius: 6px;
	}
	.icon:hover { color: #fff; background: #2980b9; }
	.icon:active { transform: translateY(2px); }
	.icon svg { display: block; width: 22px; height: 22px; fill: currentColor; }
	.track {
		position: relative;
		flex: 1;
		/* The rail was only ~70px (leftover space in the 220px row). Floor it at ~3×
		   so the audience playhead is comfortably scrubbable; the row grows to fit. */
		min-width: 220px;
		height: 6px;
		border-radius: 999px;
		background: #333b45;
		cursor: pointer;
		touch-action: none;
	}
	.track::before {
		content: '';
		position: absolute;
		left: 0; right: 0; top: 50%;
		height: 22px;
		transform: translateY(-50%);
	}
	.track:focus-visible { outline: 2px solid #2980b9; outline-offset: 3px; }
	.fill {
		position: absolute;
		left: 0; top: 0; height: 100%;
		border-radius: 999px;
		background: #2980b9;
	}
	.knob {
		position: absolute;
		top: 50%;
		width: 13px; height: 13px;
		border-radius: 50%;
		background: #fff;
		border: 2px solid #2980b9;
		transform: translate(-50%, -50%);
		pointer-events: none;
	}
	.label {
		font-size: 0.8rem;
		font-weight: 700;
		letter-spacing: 0.04em;
		color: #7a8894;
	}
</style>
