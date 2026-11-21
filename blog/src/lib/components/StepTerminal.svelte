<!--
  StepTerminal — a Terminal that plays one command per step of the slide's <Steps>.

  A plain Terminal steps only by itself (`keys="global"`), and only one build per slide
  may own Space — so a slide with several consoles cannot step them in one sequence.
  Inside a <Steps>, a StepTerminal's commands ARE steps of that build, in document order
  with every Fragment and other StepTerminal in it:

    <Steps>
      <StepTerminal lines={setup} autoplay />   ← 1st command plays on arrival, then a Space each
      <Fragment tag="p">Now the second box:</Fragment>   ← the next Space
      <StepTerminal lines={deploy} />           ← one Space per command after that
    </Steps>

  A step forward PLAYS the command (you watch it type) and holds at the end of its
  output. A step back, or any jump — paging back onto the slide opens the build spent —
  puts the console straight at that stop. Before its first step a console shows its
  window and nothing in it. A command continued with `cont: true` is one step with the
  line above it.

  `stopAt` names the stops instead — for one command with a long run of output, or a
  program that asks questions. `n` stops once line n has landed; `{ before: n }` stops as
  line n begins: a command's row with its prompt up and nothing typed, a console waiting
  for input. The last step plays to the end. Indexes are into `lines`:

    <StepTerminal autoplay stopAt={[{ before: 2 }, 5]} lines={init} />   ← 3 steps

  `autoplay`: the first command takes no step of its own; it plays together with the step
  before it (on arrival, if the console comes first in the build), so it claims one step
  fewer.

  While a command is typing the build reports itself BUSY, so <StepDots> waits for the
  output to land before it cues the next Space.

  Every other prop goes to the Terminal. The transport (play button, track) is hidden —
  the steps are the control — and the console never takes Space itself. Outside a
  <Steps> (an article, say) it is an ordinary Terminal, its props passed as given.
  In `text` mode the Steps shows everything and the Terminal prints whole.

  Logic it shares with Terminal: utils/terminalCore.ts (markersOf — the logical commands).
  The <Steps> contract: utils/stepsContext.ts.
-->
<script lang="ts">
	import { onDestroy, onMount } from 'svelte';
	import Terminal from '$lib/components/Terminal.svelte';
	import { getStepsContext } from '$lib/utils/stepsContext';
	import {
		scheduleLines,
		stepStopsOf,
		type TerminalInput,
		type TerminalStop
	} from '$lib/utils/terminalCore';

	/** The session: `{ cmd }` is typed, `{ out }` (or a bare string) is printed. */
	export let lines: TerminalInput[] = [];
	/** Where to stop, in place of the end of each command: `n` once line n has landed,
	    `{ before: n }` as line n begins. The last step plays to the end. Read once, when the
	    console claims its steps. */
	export let stopAt: TerminalStop[] | undefined = undefined;
	/** The first command plays with the step before it instead of taking a Space of its own. */
	export let autoplay: boolean = false;
	/** Timing, passed on to the Terminal; the stops are worked out from the same values. */
	export let charMs: number = 55;
	export let startMs: number = 300;
	export let pauseMs: number = 350;
	export let outMs: number = 180;

	/** Inline style for the root element, applied last so it wins. */
	export let style: string = '';
	/** DOM id for the root element. */
	export let id: string = '';
	/** Extra class(es) for the root element. NOTE: a slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS. See AGENTS.md. */
	let klass: string = '';
	export { klass as class };

	const ctx = getStepsContext();

	// The stops: 0 (an empty console), then the end of each logical command's output — or
	// the points `stopAt` names — up to the end of the session (terminalCore.stepStopsOf).
	$: stops = stepStopsOf(scheduleLines(lines, { charMs, startMs, pauseMs, outMs }), stopAt);

	// Steps are claimed once, at init, in document order — so the count is fixed then.
	const count =
		stepStopsOf(scheduleLines(lines, { charMs, startMs, pauseMs, outMs }), stopAt).length - 1;
	const ride = autoplay ? 1 : 0; // the first command rides the step before it
	const first = ctx ? ctx.register(count - ride) : 0;
	const revealed = ctx?.revealed;

	let term: Terminal;
	let mounted = false;
	let at: number | null = null; // the stop the console is at, or playing to
	let run = 0; // which play the busy flag belongs to
	const token = {};

	$: want = Math.max(0, Math.min(count, ($revealed ?? 0) - first + ride));
	$: if (mounted) go(want);

	function go(k: number) {
		if (!term || !ctx || k === at) return;
		const from = at;
		at = k;
		run++;
		// Forward by one: play it. The very first stop on arrival plays too (the autoplay
		// case), unless the build opened spent — a page-back lands, it doesn't replay.
		const playIt = from === null ? k === 1 && !ctx.arrivedAtEnd : k === from + 1;
		if (!playIt) {
			ctx.setBusy(token, false);
			term.jumpTo(stops[k]);
			return;
		}
		const mine = run;
		term.jumpTo(stops[k - 1]);
		ctx.setBusy(token, true);
		term.playTo(stops[k]).then(() => {
			if (mine === run) ctx.setBusy(token, false);
		});
	}

	onMount(() => {
		if (!ctx) return;
		// The Terminal finds its animation clock on mount, or one frame later.
		requestAnimationFrame(() => {
			mounted = true;
		});
	});
	onDestroy(() => {
		run++;
		ctx?.setBusy(token, false);
	});
</script>

{#if ctx}
	<Terminal
		bind:this={term}
		{...$$restProps}
		class="step-terminal {klass}"
		{id}
		{style}
		controls={false}
		autoplay={false}
		keys="off"
		driven
		{lines}
		{charMs}
		{startMs}
		{pauseMs}
		{outMs}
	/>
{:else}
	<Terminal
		{...$$restProps}
		class={klass}
		{id}
		{style}
		{autoplay}
		{lines}
		{charMs}
		{startMs}
		{pauseMs}
		{outMs}
	/>
{/if}
