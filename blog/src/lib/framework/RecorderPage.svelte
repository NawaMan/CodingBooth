<!--
  VOD Recorder — records a deck's slides window to a video file and writes down the
  timeline of what the speaker did; REPLAY drives the deck through a (hand-edited)
  timeline and records again. Opened from the presenter console (● REC / R).
  See specs/VOD-RECORD-1.md.

  This window never navigates, which is the whole reason it exists: the slides window and
  the console both reload on every page turn, so neither can hold a recording.
-->
<script lang="ts">
	import { onMount } from 'svelte';
	import { get } from 'svelte/store';
	import { browser } from '$app/environment';
	import { inkBook } from '$lib/stores/annotation';
	import type { InkBook } from '$lib/annotate/annotateCore';
	import {
		listen,
		post,
		publishState,
		STATUS_BEAT_MS,
		type HereInfo,
		type RecorderState
	} from '$lib/record/recordBus';
	import {
		appendEvent,
		bookClear,
		bookErase,
		bookPut,
		diffInk,
		formatClock,
		formatTimeline,
		inkKey,
		inkSnapshot,
		landingPath,
		outputSizes,
		parseTimeline,
		recordingName,
		relativeHref,
		type TimelineAction,
		type TimelineError,
		type TimelineEvent
	} from '$lib/record/timelineCore';
	import { ReplayRunner, type InkOp } from '$lib/record/replayCore';
	import {
		captureUnsupportedReason,
		chooseVideoFile,
		downloadBlob,
		expectedExtension,
		openCapture,
		type Capture,
		type FileSink
	} from '$lib/record/recordCapture';
	import { startTicker } from '$lib/record/ticker';

	let deck = '';
	let slides: HereInfo | null = null;
	let lastHereAt = 0;
	let state: RecorderState = 'idle';
	let busy = ''; // "Starting…" / "Saving…" while a transition runs

	// Settings.
	let sizeIndex = 1; // the canvas size
	let fps = 30;
	let mic = false;
	let micDeviceId = '';
	let micDevices: MediaDeviceInfo[] = [];
	let tabAudio = false;
	let keepInk = false;
	let sink: FileSink | null = null;

	// The take.
	let capture: Capture | null = null;
	let t0 = 0;
	let rolling = false;
	let events: TimelineEvent[] = [];
	let takeName = '';
	let elapsed = formatClock(0);
	let lastGotoPath = '';
	let prevBook: InkBook = {};
	let runner: ReplayRunner | null = null;
	let stopTake: () => void = () => {};

	// The timeline editor.
	let timelineText = '';
	let errors: TimelineError[] = [];
	let log: { kind: 'info' | 'warn' | 'error'; text: string }[] = [];
	let fileInput: HTMLInputElement;

	$: canvasW = slides?.width || 1920;
	$: canvasH = slides?.height || 1080;
	$: sizes = outputSizes(canvasW, canvasH);
	$: size = sizes[sizeIndex] ?? sizes[1];
	$: connected = !!slides;
	$: idle = state === 'idle' && !busy;
	$: unsupported = browser ? captureUnsupportedReason() : '';

	function say(kind: 'info' | 'warn' | 'error', text: string) {
		log = [...log.slice(-30), { kind, text }];
	}

	function setState(next: RecorderState) {
		state = next;
		publishState(deck, next);
	}

	const now = () => (performance.now() - t0) / 1000;
	const delay = (ms: number) => new Promise((r) => setTimeout(r, ms));

	/** Resolve once `test()` holds (true) or `ms` passes (false). Driven by `here` messages. */
	let waiters: (() => void)[] = [];
	function waitUntil(test: () => boolean, ms: number): Promise<boolean> {
		if (test()) return Promise.resolve(true);
		return new Promise((resolve) => {
			const timer = setTimeout(() => done(false), ms);
			const check = () => test() && done(true);
			const done = (ok: boolean) => {
				clearTimeout(timer);
				waiters = waiters.filter((w) => w !== check);
				resolve(ok);
			};
			waiters = [...waiters, check];
		});
	}

	// --- Messages from the slides window ------------------------------------------------

	// The freeze across a page turn: `leaving` holds the video on the slide still showing,
	// and the next `here` lets it go — a moment later, since `here` is said as the new slide
	// paints and the capture runs a frame or two behind. A page that never lands lets go on
	// its own, so the video can't stay frozen for the rest of the take.
	const HOLD_TAIL_MS = 150;
	const HOLD_LIMIT_MS = 8000;
	let holdTimer: ReturnType<typeof setTimeout> | undefined;
	function holdFrame() {
		if (!capture) return;
		capture.hold(true);
		clearTimeout(holdTimer);
		holdTimer = setTimeout(releaseFrame, HOLD_LIMIT_MS);
	}
	function releaseFrame(after = 0) {
		clearTimeout(holdTimer);
		const cap = capture;
		if (!after) return void cap?.hold(false);
		holdTimer = setTimeout(() => cap?.hold(false), after);
	}

	function onHere(here: HereInfo) {
		slides = here;
		lastHereAt = Date.now();
		releaseFrame(HOLD_TAIL_MS);
		runner?.here(here.path);
		// A page reached some way navigate() never saw (a plain link, the browser's Back)
		// still belongs in the timeline: write it down as a goto when it lands.
		if (rolling && state === 'recording' && here.path !== lastGotoPath) {
			record({ kind: 'goto', href: relativeHref(here.href, deck, window.location.origin) });
		}
		for (const w of waiters) w();
	}

	function record(action: TimelineAction, lead = 0) {
		if (!rolling || state !== 'recording') return;
		if (action.kind === 'goto') lastGotoPath = landingPath(action.href, deck);
		events = appendEvent(events, action, now() - lead);
	}

	function onInkChange(book: InkBook) {
		if (rolling && state === 'recording') {
			for (const c of diffInk(prevBook, book, deck)) record(c.action, c.lead);
		}
		prevBook = book;
	}

	// --- Ink, as replay writes it -------------------------------------------------------

	function writeInk(op: InkOp) {
		const ts = Date.now();
		inkBook.update((b) => {
			if (op.op === 'put') return bookPut(b, inkKey(op.slide, deck), op.stroke, ts);
			if (op.op === 'erase') return bookErase(b, inkKey(op.slide, deck), op.ids, ts);
			return bookClear(b, op.slide === '*' ? null : inkKey(op.slide, deck), deck);
		});
	}

	function clearDeckInk() {
		inkBook.update((b) => bookClear(b, null, deck));
	}

	// --- Starting and stopping ----------------------------------------------------------

	function captureOptions() {
		return { width: size.width, height: size.height, fps, mic, micDeviceId, tabAudio };
	}

	async function pickFile() {
		const name = recordingName(deck, new Date());
		const chosen = await chooseVideoFile(name, expectedExtension({ mic, tabAudio }));
		if (chosen) {
			sink = chosen;
			say('info', `The next take streams into ${chosen.name}.`);
		} else if (!('showSaveFilePicker' in window)) {
			say('warn', 'This browser cannot stream to a chosen file; the video downloads when you stop.');
		}
	}

	/** Ask for the tab (and mic). null when the speaker cancelled. */
	async function share(): Promise<Capture | null> {
		try {
			const cap = await openCapture(captureOptions());
			for (const w of cap.warnings) say('warn', w);
			return cap;
		} catch (e) {
			say('error', `No recording: ${(e as Error)?.message || 'the share was cancelled'}.`);
			return null;
		}
	}

	/** Bars away and the slide FITTED, a beat for that to settle, then roll. */
	async function roll(cap: Capture, as: 'recording' | 'replaying') {
		setState(as);
		await delay(800);
		takeName = recordingName(deck, new Date());
		await cap.start(sink);
		t0 = performance.now();
		rolling = true;
		cap.onEnded(() => void stop('The share was ended from the browser.'));
	}

	async function startRecording() {
		if (!idle || !slides) return;
		const cap = await share();
		if (!cap) return;
		capture = cap;
		busy = 'Starting…';
		try {
			setState('armed');
			if (!keepInk) clearDeckInk();
			// Start from a fresh load of the slide on screen — exactly how REPLAY starts, so a
			// half-revealed build or a playing animation cannot make the two takes differ.
			const href = relativeHref(slides.href, deck, window.location.origin);
			const path = landingPath(href, deck);
			slides = null;
			post({ type: 'cmd', deck, action: { kind: 'goto', href } });
			if (!(await waitUntil(() => slides?.path === path, 8000))) say('warn', 'The slides window did not reload — recording anyway.');

			events = [];
			lastGotoPath = path;
			await roll(cap, 'recording');
			events = appendEvent(events, { kind: 'goto', href }, 0);
			if (keepInk) for (const a of inkSnapshot(get(inkBook), deck)) events = appendEvent(events, a, 0);
			prevBook = get(inkBook);
			stopTake = startTicker(100, () => (elapsed = formatClock(now())));
			say('info', `Recording ${size.width}×${size.height} @ ${fps} fps (${cap.mime || 'browser default'}).`);
		} catch (e) {
			say('error', `Could not start: ${(e as Error)?.message ?? e}`);
			cap.dispose();
			capture = null;
			setState('idle');
		} finally {
			busy = '';
		}
	}

	async function startReplay() {
		if (!idle || !slides) return;
		const parsed = parseTimeline(timelineText);
		errors = parsed.errors;
		if (errors.length) {
			say('error', `The timeline has ${errors.length} line(s) that do not parse — fix them first.`);
			return;
		}
		if (parsed.timeline.events.length === 0) {
			say('error', 'The timeline is empty — record a take, or LOAD one.');
			return;
		}
		const cap = await share();
		if (!cap) return;
		capture = cap;
		busy = 'Starting…';
		try {
			setState('armed');
			clearDeckInk();
			const r = new ReplayRunner(parsed.timeline.events, deck, {
				send: (action) => post({ type: 'cmd', deck, action }),
				ink: writeInk,
				warn: (m) => say('warn', m)
			});
			runner = r;
			// The opening goto (and anything else at 0) before the clock runs, so the video
			// does not open on a page mid-load.
			r.prime(0);
			if (r.waiting && !(await waitUntil(() => !r.waiting, 8000))) say('warn', 'The first slide did not finish loading — replaying anyway.');

			await roll(cap, 'replaying');
			stopTake = startTicker(20, () => {
				const t = now();
				elapsed = formatClock(t);
				r.tick(t);
				if (r.done) void stop('');
			});
			say('info', `Replaying ${formatClock(r.duration)} at ${size.width}×${size.height} @ ${fps} fps.`);
		} catch (e) {
			say('error', `Could not start: ${(e as Error)?.message ?? e}`);
			cap.dispose();
			capture = null;
			runner = null;
			setState('idle');
		} finally {
			busy = '';
		}
	}

	let stopping = false;
	async function stop(reason: string) {
		if (stopping || !capture) return;
		stopping = true;
		const wasRecording = state === 'recording';
		busy = 'Saving…';
		try {
			stopTake();
			stopTake = () => {};
			if (wasRecording && rolling) events = appendEvent(events, { kind: 'end' }, now());
			rolling = false;
			runner = null;
			if (reason) say('warn', reason);

			const cap = capture;
			releaseFrame();
			const name = takeName || recordingName(deck, new Date());
			const usedSink = sink;
			const blob = await cap.stop();
			setState('idle');
			if (blob) {
				downloadBlob(blob, `${name}.${cap.ext}`);
				say('info', `Saved the video as ${name}.${cap.ext} (in your downloads).`);
			} else if (usedSink) say('info', `Saved the video into ${usedSink.name}.`);

			if (wasRecording) {
				timelineText = formatTimeline({
					header: {
						deck,
						canvas: `${canvasW}x${canvasH}`,
						recorded: new Date().toISOString(),
						video: usedSink ? usedSink.name : `${name}.${cap.ext}`
					},
					events
				});
				errors = [];
				downloadBlob(new Blob([timelineText], { type: 'text/plain' }), `${name}.timeline.txt`);
				say('info', `Saved the timeline as ${name}.timeline.txt — edit it below (or the file) and REPLAY.`);
			} else say('info', 'Replay finished.');
		} finally {
			capture = null;
			sink = null; // every take chooses its own file
			busy = '';
			stopping = false;
		}
	}

	// --- Timeline file -----------------------------------------------------------------

	async function loadFile(e: Event) {
		const file = (e.currentTarget as HTMLInputElement).files?.[0];
		if (!file) return;
		timelineText = await file.text();
		errors = parseTimeline(timelineText).errors;
		say('info', `Loaded ${file.name}${errors.length ? ` — ${errors.length} line(s) need fixing` : ''}.`);
		(e.currentTarget as HTMLInputElement).value = '';
	}

	function saveFile() {
		const name = takeName || recordingName(deck, new Date());
		downloadBlob(new Blob([timelineText], { type: 'text/plain' }), `${name}.timeline.txt`);
	}

	function checkTimeline() {
		errors = parseTimeline(timelineText).errors;
		if (!errors.length) say('info', 'The timeline parses.');
	}

	async function listMics() {
		try {
			// Labels are only readable once the mic has been allowed.
			const probe = await navigator.mediaDevices.getUserMedia({ audio: true });
			probe.getTracks().forEach((t) => t.stop());
			micDevices = (await navigator.mediaDevices.enumerateDevices()).filter((d) => d.kind === 'audioinput');
		} catch {
			say('warn', 'The microphone was refused.');
			mic = false;
		}
	}
	$: if (browser && mic && micDevices.length === 0) void listMics();

	onMount(() => {
		deck = new URL(window.location.href).searchParams.get('deck') || '/slides/';
		document.title = `● REC — ${deck}`;
		const stopListen = listen(deck, (m) => {
			if (m.type === 'here') onHere(m.here);
			else if (m.type === 'leaving') holdFrame();
			else if (m.type === 'action') record(m.action);
		});
		const stopInk = inkBook.subscribe(onInkChange);
		post({ type: 'hello', deck });
		// The heartbeat: keep the state fresh for slides windows that load mid-take, and
		// look for the slides window again whenever it has gone quiet.
		const stopBeat = startTicker(STATUS_BEAT_MS, () => {
			if (state !== 'idle') publishState(deck, state);
			if (Date.now() - lastHereAt > 3000) {
				if (lastHereAt && Date.now() - lastHereAt > 6000 && state === 'idle') slides = null;
				post({ type: 'hello', deck });
			}
		});
		const onUnload = () => publishState(deck, 'idle');
		window.addEventListener('pagehide', onUnload);
		const onBefore = (e: BeforeUnloadEvent) => {
			if (state !== 'idle') e.preventDefault();
		};
		window.addEventListener('beforeunload', onBefore);
		return () => {
			stopListen();
			stopInk();
			stopBeat();
			stopTake();
			window.removeEventListener('pagehide', onUnload);
			window.removeEventListener('beforeunload', onBefore);
			publishState(deck, 'idle');
		};
	});
</script>

<svelte:head>
	<title>● REC — {deck}</title>
</svelte:head>

<main class="rec">
	<header>
		<h1><span class="dot" class:on={state === 'recording' || state === 'replaying'}>●</span> Recorder <small>{deck}</small></h1>
		<p class="slides" class:missing={!connected}>
			{#if slides}
				Slides window: <b>{slides.title}</b> — {slides.href} ({canvasW}×{canvasH})
			{:else}
				No slides window found for {deck}. Open the deck (keep this window open), or reload it.
			{/if}
		</p>
		{#if unsupported}<p class="err">{unsupported}</p>{/if}
	</header>

	<section class="transport">
		<button class="rec-btn" disabled={!idle || !connected || !!unsupported} on:click={startRecording}>● REC</button>
		<button disabled={!idle || !connected || !!unsupported || !timelineText.trim()} on:click={startReplay}>▶ REPLAY</button>
		<button disabled={state === 'idle' || !capture || !!busy} on:click={() => stop('')}>■ STOP</button>
		<span class="clock">{elapsed}</span>
		<span class="state">{busy || (state === 'idle' ? 'ready' : state)}</span>
	</section>

	<section class="settings">
		<label>Size
			<select bind:value={sizeIndex} disabled={!idle}>
				{#each sizes as s, i}<option value={i}>{s.label}</option>{/each}
			</select>
		</label>
		<label>Frame rate
			<select bind:value={fps} disabled={!idle}>
				<option value={30}>30 fps</option>
				<option value={60}>60 fps</option>
			</select>
		</label>
		<label class="check"><input type="checkbox" bind:checked={mic} disabled={!idle} /> Microphone</label>
		{#if mic && micDevices.length}
			<label>Mic
				<select bind:value={micDeviceId} disabled={!idle}>
					<option value="">Default</option>
					{#each micDevices as d}<option value={d.deviceId}>{d.label || d.deviceId}</option>{/each}
				</select>
			</label>
		{/if}
		<label class="check"><input type="checkbox" bind:checked={tabAudio} disabled={!idle} /> Tab sound</label>
		<label class="check" title="Off: the deck's ink is cleared when a recording starts. On: it stays, and the timeline writes it down so a replay starts with it too.">
			<input type="checkbox" bind:checked={keepInk} disabled={!idle} /> Keep ink already drawn
		</label>
		<span class="file">
			<button disabled={!idle} on:click={pickFile}>Save to…</button>
			{sink ? sink.name : 'downloads'}
		</span>
	</section>

	<p class="hint">
		REC asks which tab to record — pick the <b>slides</b> tab. Then present as usual: page,
		step, draw, play animations, in the slides window or from the console. This window can sit
		behind; STOP saves the video and the timeline. Edit the timeline below and REPLAY to film
		it again, hands off.
	</p>

	<section class="timeline">
		<div class="tl-bar">
			<b>Timeline</b>
			<button on:click={() => fileInput.click()} disabled={!idle}>LOAD…</button>
			<input bind:this={fileInput} type="file" accept=".txt,text/plain" hidden on:change={loadFile} />
			<button on:click={saveFile} disabled={!timelineText.trim()}>SAVE…</button>
			<button on:click={checkTimeline} disabled={!timelineText.trim()}>CHECK</button>
		</div>
		<textarea
			bind:value={timelineText}
			spellcheck="false"
			readonly={!idle}
			placeholder="Record a take, or LOAD a timeline file. One action per line:  00:04.250 goto intro.html"
		></textarea>
		{#if errors.length}
			<ul class="errors">
				{#each errors as e}<li>line {e.line}: {e.message}</li>{/each}
			</ul>
		{/if}
		<details>
			<summary>Timeline lines</summary>
			<pre>{`00:04.250 goto intro.html            page turn (back / end: PREV landing spent)
00:07.900 step                       a build step   (step back: Shift+Space)
00:08.500 continue                   the slide's own CONTINUE hook
00:09.000 anim play 0.250            animations play from 25%  (anim pause 0.6)
00:10.000 trigger demo               a named trigger
00:11.000 highlight api              spotlight a Block  (highlight off)
00:12.000 ink intro.html draw 0.84 {…}   a stroke drawn over 0.84 s
00:13.000 ink intro.html erase <id>  /  ink intro.html clear  /  ink * clear
shift +2                             move every following line by 2 s
01:02.500 end                        replay stops here`}</pre>
		</details>
	</section>

	{#if log.length}
		<section class="log">
			{#each log as l}<p class={l.kind}>{l.text}</p>{/each}
		</section>
	{/if}
</main>

<style>
	.rec {
		color: #c0f1ff;
		font-family: system-ui, sans-serif;
		font-size: 14px;
		padding: 14px 16px 24px;
		max-width: 760px;
		margin: 0 auto;
		box-sizing: border-box;
	}
	h1 {
		font-size: 20px;
		margin: 0 0 6px;
	}
	h1 small {
		font-weight: normal;
		opacity: 0.7;
		font-size: 14px;
	}
	.dot {
		color: #666;
	}
	.dot.on {
		color: #ff4040;
		animation: blink 1s steps(2, start) infinite;
	}
	@keyframes blink {
		to {
			visibility: hidden;
		}
	}
	.slides {
		margin: 0 0 10px;
		word-break: break-all;
	}
	.slides.missing,
	.err,
	.log .error {
		color: #ff8a80;
	}
	.log .warn {
		color: #ffd27f;
	}
	section {
		margin: 10px 0;
	}
	.transport {
		display: flex;
		align-items: center;
		gap: 8px;
		flex-wrap: wrap;
	}
	button {
		background: #2a2a2a;
		color: #c0f1ff;
		border: 1px solid #555;
		border-radius: 4px;
		padding: 6px 12px;
		font: inherit;
		cursor: pointer;
	}
	button:disabled {
		opacity: 0.4;
		cursor: default;
	}
	.rec-btn:not(:disabled) {
		border-color: #ff4040;
		color: #ff8080;
	}
	.clock {
		font-family: ui-monospace, monospace;
		font-size: 18px;
		margin-left: 8px;
	}
	.state {
		opacity: 0.7;
	}
	.settings {
		display: flex;
		flex-wrap: wrap;
		gap: 8px 16px;
		align-items: center;
	}
	select {
		background: #222;
		color: inherit;
		border: 1px solid #555;
		margin-left: 4px;
		font: inherit;
	}
	.check {
		white-space: nowrap;
	}
	.hint {
		opacity: 0.75;
		line-height: 1.4;
	}
	.tl-bar {
		display: flex;
		gap: 8px;
		align-items: center;
		margin-bottom: 6px;
	}
	textarea {
		width: 100%;
		box-sizing: border-box;
		height: 300px;
		background: #101010;
		color: #e0f7ff;
		border: 1px solid #444;
		font: 12px/1.45 ui-monospace, monospace;
		padding: 8px;
		resize: vertical;
		white-space: pre;
	}
	.errors {
		color: #ff8a80;
		font-family: ui-monospace, monospace;
		font-size: 12px;
		padding-left: 18px;
	}
	pre {
		font-size: 11px;
		overflow-x: auto;
		opacity: 0.85;
	}
	.log p {
		margin: 2px 0;
		font-size: 12px;
	}
</style>
