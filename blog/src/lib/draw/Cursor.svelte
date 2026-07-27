<!--
  Cursor — a fake mouse pointer, for demonstrating a UI without a live app.

  An author-placed glyph that glides between named targets and can flash a
  click ripple on arrival — a scriptable stand-in for "then I click Save",
  so a slide can SHOW the gesture instead of cutting to a screen recording.

      <Draw>
        <Cursor path={["menu-btn", { at: "save-btn", click: true }]} animate={1.4} />
      </Draw>

  NOT A NEW ENGINE: it's a Sprite wearing a pointer. Cursor resolves `path`
  into canvas points — a Block NAME through stores/blockAnchors.ts (the same
  registry Connector/Spotlight/Toast read, so a target dragged in ADJUST
  carries the cursor along with it) or a literal [x, y] — turns them into
  Sprite `stops` (cursorCore.ts, pure), and flies a LOCKED <Sprite> underneath.
  `lock` is Sprite's own escape hatch for generated geometry: it still flies,
  but registers no ADJUST editor and shows no chrome, so there is exactly one
  source of truth for Copy — the <Cursor> tag itself — and nothing to
  save on the Sprite side. Motion is pure generated CSS, so it prerenders and
  the AnimationBar scrubs it exactly like every other shape's animation.

  An unresolved name drops the WHOLE flight (Connector's rule): never a
  cursor stranded at a fallback point. A single `path` entry is a static
  cursor (no flight) — useful for just marking a spot with an optional click.

  CLICK is authored as a keyframe marker (`click: true` on a waypoint), not a
  separate build step — the flight already lives on one continuous timeline,
  and a marker needs no second clock. Each ripple is a plain SVG circle whose
  `animation-delay` lands it exactly when the glyph arrives (cursorCore's
  `cursorRipples`), using ONE static @keyframes shared by every ripple (only
  the delay varies) rather than Sprite's per-instance generated CSS, since
  every ripple looks the same. It honours prefers-reduced-motion — the flash
  is a flourish, not the taught content, unlike the flight itself.

  CHAINING (`script`): a list of warpTo/moveTo/around commands instead of an
  evenly-timed waypoint list — see cursorScriptCore.ts for the full contract
  (a direct one-way move by default, an opt-in there-and-back shake at
  `times` ≥ 2, orbit laps, an instant warp). It compiles to the SAME
  generated `stops`, so it rides the same locked Sprite; `around` needs no
  new Draw PathShape because the ellipse is sampled into literal stops by
  the compiler, not ridden as a shape.

  STARTING FROM A NOTE (`startOn`): a checked `<Note data-trigger="name">`
  line fires a named pulse (stores/triggers, relayed console → audience by
  stores/presenter's publishTrigger/subscribeTrigger, exactly like the
  note-driven Spotlight highlight). `startOn="name"` makes Cursor wait —
  idle, at its first pose, `paused` on the Sprite underneath — until that
  pulse arrives, then play once; a fresh pulse (re-checking the line)
  replays it from the top via a keyed remount, since resuming a PAUSED
  animation can't restart one that already finished. Unset (default): the
  flight autoplays on mount, unchanged from before.

  Deliberately NOT in this pass: distinct hover/drag pointer states — just
  move + a click ripple, which is what every use so far has needed. The glyph
  itself is swappable via the default slot (an emoji, a custom SVG) for a
  themed pointer.
-->
<script module lang="ts">
	import type { Point } from './types';

	/** A Block `name` or a literal canvas point. */
	export type CursorAt = string | Point;
	/** A waypoint: where to go, whether arriving there flashes a ripple, and
	 *  an optional per-waypoint size override (falls back to Cursor's own
	 *  `size` prop). */
	export interface CursorWaypoint {
		at: CursorAt;
		click?: boolean;
		size?: number;
	}
	/** Built-in glyph presets — `arrow` (default) is the pointer path;
	 *  `dot`/`ring` are simple vector shapes for a laser-pointer-style cue.
	 *  For anything else (an emoji, custom art), use the default slot
	 *  instead — presets and `children` are mutually exclusive; `children`
	 *  wins if both are given. */
	export type CursorShape = 'arrow' | 'dot' | 'ring';
</script>

<script lang="ts">
	import type { Snippet } from 'svelte';
	import { blockAnchors } from '$lib/stores/blockAnchors';
	import { lastTrigger } from '$lib/stores/triggers';
	import Sprite from './Sprite.svelte';
	import { cursorRipples, cursorSpriteStops } from './cursorCore';
	import { compileScript, type CursorCommand, type ResolvedCursorCommand } from './cursorScriptCore';

	interface Props {
		/** Where the pointer travels: ≥1 entries, each a Block name, a literal
		 *  [x, y], or a `{ at, click }` waypoint. Two or more animate a glide
		 *  across them (evenly timed); one is a static cursor with no flight.
		 *  A name not yet registered drops the WHOLE flight (Connector's rule).
		 *  Ignored when `script` is set. */
		path?: (CursorAt | CursorWaypoint)[];
		/** A CHAINED flight instead of an evenly-timed waypoint list —
		 *  warpTo/moveTo/around commands, each with its own timing (see
		 *  cursorScriptCore.ts). Takes precedence over `path`; when set, the
		 *  script's own per-command durations drive the flight and `animate`
		 *  is ignored. */
		script?: CursorCommand[];
		/** Seconds for the whole glide across every leg (evenly split).
		 *  Ignored when `script` is set. */
		animate?: number;
		/** Seconds to hold at the first point before departing. */
		delay?: number;
		/** CSS timing function for the whole flight (default ease-in-out).
		 *  Ignored when `script` is set — each command already has its own
		 *  pacing; a whole-flight easing curve would fight it. */
		ease?: string;
		/** Default glyph box size, canvas px — the ambient size at the start
		 *  of the flight. A `path` waypoint's own `size`, or a `script`
		 *  command's own `size`, overrides it from that point on. */
		size?: number;
		/** Extra static rotation (deg) on the glyph, e.g. to match custom art. */
		rotate?: number;
		/** Built-in glyph preset — `arrow` (default) / `dot` / `ring`. Ignored
		 *  when `children` is given. */
		shape?: CursorShape;
		/** The name of a trigger pulse (stores/triggers) that starts this
		 *  flight — fired by a checked `<Note data-trigger="…">` line, or
		 *  directly via `fireTrigger(name)`. Unset (default): the flight
		 *  autoplays on mount, scrubbable by AnimationBar — today's
		 *  behaviour. Set: the cursor sits idle at its first pose until the
		 *  named pulse arrives, then plays once; a fresh pulse (re-checking
		 *  the line) replays it from the top. */
		startOn?: string;
		/** Shown only in devtools/tests — Cursor has no ADJUST handles of its
		 *  own (the Sprite underneath is locked), so this is not a Copy name. */
		name?: string;
		/** Override the default pointer glyph. */
		children?: Snippet;
		/** Inline style for the root element, applied last so it wins. */
		style?: string;
		/** DOM id for the root element. */
		id?: string;
		/** Extra class(es) for the root element. NOTE: a slide's own scoped styles
		 *  will NOT match — use global CSS (global.css / roles.css / a :global(...)
		 *  block) or a utility class. See AGENTS.md. */
		class?: string;
	}

	let {
		path,
		script,
		animate = 1.2,
		delay = 0,
		ease = 'ease-in-out',
		size = 40,
		rotate = 0,
		shape = 'arrow',
		startOn = '',
		name = '',
		children,
		style = '',
		id = '',
		class: klass = ''
	}: Props = $props();

	const anchors = $derived($blockAnchors);

	/** A name resolves to its Block's live centre; an unregistered name is
	 *  null — the whole flight then renders nothing (Connector's rule). */
	function resolvePoint(at: CursorAt): Point | null {
		if (typeof at === 'string') {
			const box = anchors.get(at);
			return box ? [box.x + box.width / 2, box.y + box.height / 2] : null;
		}
		return at;
	}

	// --- path mode: the original, evenly-timed waypoint list --------------
	function normalize(w: CursorAt | CursorWaypoint): CursorWaypoint {
		return typeof w === 'object' && !Array.isArray(w) ? w : { at: w };
	}
	const waypoints = $derived((path ?? []).map(normalize));
	const resolvedPath = $derived(waypoints.map((w) => resolvePoint(w.at)));
	const pathUnresolved = $derived((path?.length ?? 0) > 0 && resolvedPath.some((p) => p === null));
	const pathTargets = $derived(
		pathUnresolved
			? []
			: resolvedPath.map((p, i) => ({
					x: p![0],
					y: p![1],
					click: !!waypoints[i].click,
					size: waypoints[i].size
				}))
	);

	// --- script mode: chained warpTo/moveTo/around commands ---------------
	const usingScript = $derived(!!script && script.length > 0);
	function resolveCommand(cmd: CursorCommand): ResolvedCursorCommand | null {
		const click = !!cmd.click;
		if (cmd.kind === 'attention')
			return {
				kind: 'attention',
				times: cmd.times ?? 1,
				period: cmd.period ?? 0.5,
				scale: cmd.scale ?? 1.4,
				click,
				size: cmd.size
			};
		const at = resolvePoint(cmd.at);
		if (!at) return null;
		if (cmd.kind === 'warpTo') return { kind: 'warpTo', at, click, size: cmd.size };
		if (cmd.kind === 'moveTo')
			return { kind: 'moveTo', at, times: cmd.times ?? 1, period: cmd.period ?? 3, click, size: cmd.size };
		return {
			kind: 'around',
			at,
			rx: cmd.rx,
			ry: cmd.ry,
			times: cmd.times ?? 1,
			period: cmd.period ?? 3,
			click,
			size: cmd.size
		};
	}
	const resolvedScript = $derived(usingScript ? (script ?? []).map(resolveCommand) : null);
	// An unresolved name drops the WHOLE script — Connector's rule, same as `path`.
	const scriptUnresolved = $derived(!!resolvedScript && resolvedScript.some((c) => c === null));
	const scriptResult = $derived(
		resolvedScript && !scriptUnresolved
			? compileScript(resolvedScript as ResolvedCursorCommand[], size)
			: null
	);

	// --- unified: whichever mode is active drives the flight ---------------
	const stops = $derived(usingScript ? (scriptResult?.stops ?? []) : cursorSpriteStops(pathTargets, size));
	const effectiveAnimate = $derived(usingScript ? (scriptResult?.totalSeconds ?? 0) : animate);
	const safeDelay = $derived(Number.isFinite(delay) ? delay : 0);
	// A script's ripples are timed relative to ITS OWN start (compileScript
	// doesn't know about Cursor's outer `delay`); path mode's cursorRipples
	// already folds `delay` in. Fold it in here too, so both modes agree on
	// what a ripple's delaySec means: seconds from MOUNT.
	const ripples = $derived(
		usingScript
			? (scriptResult?.ripples ?? []).map((r) => ({ ...r, delaySec: r.delaySec + safeDelay }))
			: cursorRipples(pathTargets, delay, animate, size)
	);
	const hasFlight = $derived(stops.length > 0);

	// --- startOn: idle until a matching named pulse, then play once; a
	// fresh pulse (re-checking the note line) replays from the top.
	//
	// `firedTs` LATCHES the last MATCHING pulse's timestamp rather than just
	// mirroring $lastTrigger — otherwise an unrelated, LATER trigger firing
	// (a different Cursor's startOn) would flip this one back to "idle" the
	// moment $lastTrigger's single module-wide slot moved on to a new name.
	//
	// The effect never runs during SSR (Svelte effects are client-only), so
	// a startOn Cursor always prerenders idle/paused — no autoplay leaks
	// into the built markup.
	const armed = $derived(!!startOn);
	let firedTs = $state<number | null>(null);
	$effect(() => {
		const p = $lastTrigger;
		if (p && startOn && p.name === startOn) firedTs = p.ts;
	});
</script>

{#snippet pointerGlyph()}
	<svg viewBox="0 0 24 24" width="100%" height="100%" class="cursor-glyph">
		<path
			d="M3 3 L10.07 19.97 L12.58 12.58 L19.97 10.07 Z"
			fill="var(--cursor-fill, #F0A33E)"
			stroke="var(--cursor-outline, rgba(0, 0, 0, 0.55))"
			stroke-width="1.4"
			stroke-linejoin="round"
		/>
	</svg>
{/snippet}

{#snippet dotGlyph()}
	<svg viewBox="0 0 24 24" width="100%" height="100%" class="cursor-glyph">
		<circle
			cx="12"
			cy="12"
			r="8"
			fill="var(--cursor-fill, #F0A33E)"
			stroke="var(--cursor-outline, rgba(0, 0, 0, 0.55))"
			stroke-width="1.4"
		/>
	</svg>
{/snippet}

{#snippet ringGlyph()}
	<svg viewBox="0 0 24 24" width="100%" height="100%" class="cursor-glyph">
		<circle cx="12" cy="12" r="8" fill="none" stroke="var(--cursor-fill, #F0A33E)" stroke-width="2.5" />
	</svg>
{/snippet}

{#snippet flight(paused: boolean, showRipples: boolean)}
	<Sprite
		lock
		{paused}
		{name}
		animate={effectiveAnimate}
		delay={safeDelay}
		{ease}
		{size}
		{rotate}
		orient={false}
		{stops}
	>
		{#if children}
			{@render children()}
		{:else if shape === 'dot'}
			{@render dotGlyph()}
		{:else if shape === 'ring'}
			{@render ringGlyph()}
		{:else}
			{@render pointerGlyph()}
		{/if}
	</Sprite>
	{#if showRipples}
		{#each ripples as r, i (i)}
			<circle
				class="cursor-ripple"
				cx={r.x}
				cy={r.y}
				r={r.r}
				style="animation-delay:{r.delaySec}s"
			/>
		{/each}
	{/if}
{/snippet}

{#if hasFlight}
	<g id={id || undefined} class="draw-cursor {klass}" style={style || undefined} aria-hidden="true">
		{#if !armed}
			{@render flight(false, true)}
		{:else if firedTs !== null}
			{#key firedTs}
				{@render flight(false, true)}
			{/key}
		{:else}
			<!-- Idle: frozen at the first pose, and — crucially — the ripples
			     aren't mounted at all, not merely delayed. A ripple's own
			     animation-delay counts down from MOUNT, independent of the
			     Sprite's paused state; if it were sitting in the DOM this
			     whole time, it would fire out of sync with a flight that
			     hasn't actually started yet. -->
			{@render flight(true, false)}
		{/if}
	</g>
{/if}

<style>
	.cursor-ripple {
		fill: none;
		stroke: var(--cursor-ripple, #f0a33e);
		stroke-width: 3;
		opacity: 0;
		transform-box: fill-box;
		transform-origin: center;
		/* No fill-mode: with `both`/`backwards`, the browser applies the 0%
		   keyframe's styles DURING animation-delay, which would make every
		   ripple visible (a static translucent ring) from mount until its
		   delay elapses — exactly the "before the checkpoint" leak this
		   component promises not to have. Plain `opacity: 0` above already
		   covers the resting state correctly, before AND after. */
		animation: cursor-ripple-pulse 0.6s ease-out;
	}
	@keyframes cursor-ripple-pulse {
		0% {
			opacity: 0.9;
			transform: scale(0.35);
		}
		100% {
			opacity: 0;
			transform: scale(1.6);
		}
	}
	@media (prefers-reduced-motion: reduce) {
		.cursor-ripple {
			animation: none;
			opacity: 0;
		}
	}
</style>
