<!--
  Typewriter — text that types itself out, one character at a time.

  <Terminal> already types, but it types inside a fake console: its reveal is the WIDTH
  of a span clipped to whole `ch` units, which only means anything in a monospace font
  and only on one unwrapped line. This is the same idea lifted onto ordinary slide text —
  a headline, a quote, a punchline — in whatever font the deck uses, wrapping like the
  prose it is.

  THE TYPING IS CSS, NOT A TIMER, and everything follows from that. Each character gets
  one finite `@keyframes` animation with its own delay, so:

    - <AnimationBar> scrubs it for free. The bar collects every finite CSS animation in
      the slide (`slideAnim.ts`), so this one is on the slide's clock without asking. Drag
      backwards and every character goes back where it was — a timer-driven typewriter
      can do none of that.
    - It renders WHOLE on the server. The text is in the markup from props alone; the
      animation only ever HIDES what is already there. So a Text artifact, a handout, a
      reader with `prefers-reduced-motion`, or a browser that never runs the animation all
      show the finished sentence rather than an empty box.

  THE LINE HOLDS ITS SPACE. A character waiting its turn is `visibility: hidden`, not
  absent, so the paragraph is laid out at full size from the first frame: nothing around
  it reflows, a centred line does not creep sideways as it fills, and the wrap points
  never move. (Fragment makes the same call, for the same reason.)

  Usage:

    <script>
      import Typewriter from '$lib/components/Typewriter.svelte';
    </script>

    <Typewriter tag="h1" text="One character at a time." />
    <Typewriter text={`Two lines,\nboth typed.`} charMs={40} punctuationMs={400} />

  Props: `text`, `tag`, `charMs`, `startMs`, `punctuationMs`, `caret`, `typing`,
  `startOn`, plus `style` / `id` / `class`.

  STARTING: by default it types on mount. `startOn="name"` holds it at frame 0 instead
  until a named trigger pulse — a `<Note data-trigger="name">` line the speaker checks
  off in the presenter console, or a `fireTrigger('name')` call — exactly as
  `<Cursor startOn>` does. A fresh pulse replays it from the top.

  ONE CLOCK, MANY TYPEWRITERS. Nothing here owns a transport, so several may share a
  slide (stagger them with `startMs`) and an `<AnimationBar />` drives them all together.
  That is the difference from Terminal, which brings its own transport and must not be
  paired with a bar.

  Two mechanics worth knowing before editing:

    - Every reveal keyframe declares only a `from`. The implicit `to` is the property's
      own cascaded value — which is `visible` — so ONE keyframe serves every character,
      and the un-animated state is the finished text.
    - The caret is a `::before` on the character being typed, at its left edge: the
      character is hidden during its own window, so the caret marks the spot the letter
      is about to land in. `visibility` is inherited but overridable, which is exactly
      why the reveal animates visibility rather than opacity — an `opacity: 0` parent
      could not show a caret at all.
-->
<script lang="ts">
	import { getMode } from '$lib/presentation';
	import { lastTrigger } from '$lib/stores/triggers';
	import { scheduleChars, type TypewriterTiming } from '$lib/utils/typewriterCore';

	/** The text to type. `\n` starts a new line; spacing is preserved as authored. */
	export let text: string = '';
	/** Element to render. Match the surrounding markup (h1/h2/p/span/…). */
	export let tag: string = 'div';
	/** ms per character. */
	export let charMs: number = 55;
	/** ms of dead air before the first character — stagger several typewriters with it. */
	export let startMs: number = 300;
	/** ms of extra beat after a clause ender (`.` `,` `?` …). 0 types at a flat rate. */
	export let punctuationMs: number = 0;
	/** Show the caret: it rides the character being typed, then rests, blinking, at the end. */
	export let caret: boolean = true;
	/** Type it out. `false` renders the finished text (and is implied by `text` mode). */
	export let typing: boolean = true;
	/** Hold at frame 0 until this named trigger pulses. `''` types on mount. */
	export let startOn: string = '';
	/** Inline style for the root element, applied last so it wins. */
	export let style: string = '';
	/** DOM id for the root element. */
	export let id: string = '';
	/** Extra class(es) for the root element. NOTE: a slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS (global.css / roles.css / a
	    :global(...) block) or a utility class. See AGENTS.md. */
	let klass: string = '';
	export { klass as class };

	// A `text` artifact is read at the reader's pace, not the presenter's: there is no
	// slide to hold and nothing to scrub, and a line that types itself as you scroll past
	// is just a line you can't read. Print it whole. (The call Terminal and Steps make.)
	const isText = getMode() === 'text';

	$: timing = { charMs, startMs, punctuationMs } satisfies TypewriterTiming;
	$: schedule = scheduleChars(text, timing);
	$: animating = typing && !isText && schedule.chars.length > 0;

	// --- startOn: idle until a matching named pulse, then type once; a fresh pulse
	// (re-checking the note line) replays from the top.
	//
	// `runToken` COUNTS the matching pulses rather than mirroring `$lastTrigger` — two
	// separate reasons, and both matter:
	//   - an unrelated, later trigger (another element's `startOn`) must not flip this one
	//     back to "idle" when that single module-wide slot moves on. Cursor latches for
	//     the same reason;
	//   - keying the run on the count, not on the pulse's timestamp, means two pulses in
	//     the SAME millisecond are still two replays. A timestamp would silently swallow
	//     the second.
	// It also re-creates the spans, which is the only way to restart a CSS animation that
	// has already finished — there is no `.play()` on a keyframe, only a fresh element.
	// (The store is null during SSR, so a `startOn` typewriter always prerenders held.)
	let runToken = 0;
	const onPulse = () => (runToken += 1);
	$: if ($lastTrigger && startOn && $lastTrigger.name === startOn) onPulse();
	$: held = animating && !!startOn && runToken === 0;

	// The window a character owns; the caret's ::before reads the same two customs.
	const charStyle = (delayMs: number, durationMs: number) =>
		`--d:${delayMs}ms; --w:${durationMs}ms;`;
</script>

<!-- NOTE: the run is `white-space: pre-wrap`, so the markup below is packed tight — a
     newline between two character spans would render as a space. -->
<svelte:element
	this={tag}
	class="typewriter {klass}"
	class:anim={animating}
	class:held
	class:no-caret={!caret}
	id={id || undefined}
	{style}
>{#if text}{#key runToken}<span class="run">{#each schedule.chars as char (char.index)}<span
					class="ch"
					style={charStyle(char.delayMs, char.durationMs)}>{char.text}</span>{/each}{#if caret && animating}<span
				class="rest"
				style={charStyle(schedule.envelopeMs, 1)}
				aria-hidden="true"><i class="caret"></i></span>{/if}</span>{/key}{:else}<slot />{/if}</svelte:element>

<style>
	.typewriter {
		/* No typography of its own: it types in whatever the slide already reads as. */
		margin: 0;
	}

	/* `pre-wrap` keeps the author's spacing and newlines while still wrapping. The
	   per-character spans are plain `inline`, so they add no break opportunities of their
	   own — line breaking is decided by the text content, exactly as if the run were one
	   text node. */
	.run {
		white-space: pre-wrap;
	}

	/* `relative` so the caret pseudo-element has this character's box to anchor to. */
	.ch {
		position: relative;
	}

	/* The reveal. Only a `from` frame: the implicit `to` is the cascaded `visible`, so one
	   keyframe serves every character AND the un-animated state is the finished text. */
	.anim .ch,
	.anim .rest {
		animation-name: typewriter-in;
		animation-duration: var(--w);
		animation-delay: var(--d);
		animation-timing-function: steps(1, end);
		animation-fill-mode: both;
	}
	@keyframes typewriter-in {
		from {
			visibility: hidden;
		}
	}

	/* The caret rides the character being typed, at its LEFT edge — the character is
	   hidden through its own window, so the bar stands where the letter is about to land.

	   Fill mode `forwards` makes it a WINDOW: before its delay there is no fill, so the
	   base `hidden` holds; through the window `steps(1, end)` holds the `from` (visible);
	   at the end the implicit `to` — the cascaded `hidden` — takes it away again.

	   It sets `visibility` explicitly, which is why the reveal animates visibility rather
	   than opacity: a hidden PARENT can be overridden by a visible child, an `opacity: 0`
	   one cannot. */
	.anim .ch::before {
		content: '';
		position: absolute;
		left: -0.04em;
		top: 50%;
		width: 0.09em;
		height: 1.1em;
		margin-top: -0.55em;
		background: var(--typewriter-caret, #00b356);
		visibility: hidden;
		animation-name: typewriter-caret;
		animation-duration: var(--w);
		animation-delay: var(--d);
		animation-timing-function: steps(1, end);
		animation-fill-mode: forwards;
	}
	@keyframes typewriter-caret {
		from {
			visibility: visible;
		}
	}
	/* No caret at all when the author turned it off — the reveal is unaffected. */
	.typewriter.no-caret .ch::before {
		animation-name: none;
	}

	/* The caret that stays behind: it appears when the last character lands, and blinks
	   there like a cursor left in a field. */
	.caret {
		display: inline-block;
		width: 0.09em;
		height: 1.1em;
		vertical-align: middle;
		background: var(--typewriter-caret, #00b356);
		/* Infinite, so it is excluded from the slide's clock (`endTimeOf` reports no finite
		   end): the caret keeps blinking while the AnimationBar is paused, exactly as a
		   real cursor does. */
		animation: typewriter-blink 1.06s steps(1, end) infinite;
	}
	@keyframes typewriter-blink {
		50% {
			opacity: 0;
		}
	}

	/* `startOn`, before its pulse: every animation frozen in its delay phase, which the
	   `backwards` half of fill-mode `both` renders as "nothing typed yet". The blink is
	   frozen too — an idle typewriter shows no caret at all, so there is nothing to blink. */
	.typewriter.held .ch,
	.typewriter.held .ch::before,
	.typewriter.held .rest,
	.typewriter.held .caret {
		animation-play-state: paused;
	}

	/* Reduced motion: no typing, no blink. The base state is the finished text with a
	   resting caret, which is the right still frame — and the same one the server renders. */
	@media (prefers-reduced-motion: reduce) {
		.anim .ch,
		.anim .ch::before,
		.anim .rest,
		.caret {
			animation-name: none;
		}
	}
</style>
