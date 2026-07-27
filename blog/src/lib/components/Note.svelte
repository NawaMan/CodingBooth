<!--
  Note — a speaker note. Three homes for the same authored content:

  - In a normal deck window, it renders just below the slide in the canvas
    coordinate space (so it scales with the slide), shown only in SCALED display
    mode — there the slide is at an exact factor and the note sits below it,
    reachable by scrolling. In FITTED mode the slide fills the window, so it hides.
    It ALSO hides once a live ?present console for this deck is carrying the notes
    (consoleLive) — the console's own panel is then the single notes surface and the
    below-slide copy is redundant. With no console open it stays as the fallback.

  - In a presenter window (loaded with ?present, see stores/presenter), the same
    note renders as the console's notes panel: pinned to the viewport, always
    visible. SlideDeck hides the whole slide with `visibility:hidden`; the note
    flips ITSELF back to visible (visibility is inherited and individually
    overridable), so no portal is needed to lift it out of the hidden slide.

  - In a printable handout (routes/_handout/[deck].html), it becomes the band of prose
    below the printed slide — but only if the reader asked for notes. There the
    display mode does not get a vote; see `handout` below.
-->
<script lang="ts">
	import { browser } from '$app/environment';
	import { page } from '$app/stores';
	import { displayMode } from '$lib/stores/displayMode';
	import {
		presenterMode, consoleLive, deckKeyFromPath, loadChecks, saveChecks, publishHighlight,
		publishTrigger
	} from '$lib/stores/presenter';
	import { setHighlight } from '$lib/stores/highlightTarget';
	import { fireTrigger } from '$lib/stores/triggers';
	import { printNotes } from '$lib/stores/printNotes';
	import { getHandout } from '$lib/presentation';
	import { kioskActive, kioskPaces, setKioskNoteItems, clearKioskNotes } from '$lib/stores/kiosk';
	import { noteItemsFrom } from '$lib/kiosk/kioskCore';

	/** Inline style for the root element, applied last so it wins. */
	export let style: string = '';
	/** DOM id for the root element. */
	export let id: string = '';
	/** Extra class(es) for the root element. NOTE: a slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS (global.css / roles.css / a
	    :global(...) block) or a utility class. See AGENTS.md. */
	let klass: string = '';
	export { klass as class };

	// The handout (routes/_handout/[deck].html) is a third home for the same note, and it OVERRIDES
	// the other two rather than adding to them: there, whether a note is in the document is
	// the reader's decision, printed or not printed, and not a consequence of a display mode
	// the speaker happened to leave on SCALED weeks ago. See presentation.ts.
	const handout = getHandout();

	// …and `?notes` on a single slide is the same request, made of the deck instead of the
	// handout: print THIS slide with its note under it. It ADDS to the screen rules rather than
	// replacing them, because it is a print instruction and the deck is still a deck.
	// The below-slide SCALED note yields once a live ?present console is carrying the
	// notes ($consoleLive — set by SlideDeck's audience branch from the console's
	// heartbeat). It is redundant then: the console shows the note in its own pinned
	// panel, and duplicating it under an already-shrunken slide only eats height. With
	// no console open $consoleLive is false and the below-slide note stays as the
	// fallback. The presenter panel ($presenterMode) and print/handout are untouched —
	// this drops ONLY the audience-window duplicate.
	// Kiosk "use speaker notes": keep the note in the DOM so we can publish its
	// *lines* (direct children — same as the presenter checklist) one-by-one.
	// The caption is a window-level panel; fixed inside the scaled canvas would
	// pin to the transform, not the window.
	$: kioskShowNotes = $kioskActive && $kioskPaces.useNotes;
	$: visible = handout
		? handout.notes
		: $printNotes || ($displayMode === 'SCALED' && !$consoleLive) || $presenterMode || kioskShowNotes;
	$: kioskSourceOnly =
		kioskShowNotes &&
		!($printNotes || ($displayMode === 'SCALED' && !$consoleLive) || $presenterMode || handout);

	// The deck + slide this note belongs to — the key its check states persist under.
	$: slidePath = $page.url.pathname.replace(/\/+$/, '').split('/').pop() || '';
	$: deckKey = browser ? deckKeyFromPath($page.url.pathname) : '/';

	/** Publish ordered note lines for the kiosk caption + step clock. */
	function publishKioskText(node: HTMLElement, opts: { enabled: boolean }) {
		let enabled = opts.enabled;
		const push = () => {
			if (!enabled) return;
			setKioskNoteItems(noteItemsFrom(node));
		};
		const mo = typeof MutationObserver !== 'undefined'
			? new MutationObserver(push)
			: null;
		mo?.observe(node, { childList: true, subtree: true, characterData: true });
		queueMicrotask(push);
		return {
			update(next: { enabled: boolean }) {
				enabled = next.enabled;
				if (enabled) push();
				else clearKioskNotes();
			},
			destroy() {
				mo?.disconnect();
				clearKioskNotes();
			}
		};
	}

	// Presenter check-off: give each note "line" (direct child element) a leading
	// checkbox the speaker can tick as they cover it. Click toggles just that line;
	// Shift+Click checks that line AND everything above it (a "covered up to here"
	// marker). State is persisted per deck+slide (survives reload/navigation) and can
	// be cleared page-wide or deck-wide from the console (gp:checks-clear event, after
	// it wipes the relevant localStorage). Only in the presenter panel; the SCALED
	// below-slide note stays untouched.
	interface CheckCtx { enabled: boolean; deckKey: string; slidePath: string; }
	function checklist(node: HTMLElement, ctx: CheckCtx) {
		let lines: HTMLElement[] = [];
		let cleanups: Array<() => void> = []; // per-line dblclick listeners to detach
		const setChecked = (line: HTMLElement, on: boolean) => {
			line.classList.toggle('gp-checked', on);
			line.querySelector(':scope > .gp-check')?.setAttribute('aria-checked', String(on));
		};
		const persist = () => saveChecks(ctx.deckKey, ctx.slidePath, lines.map((l) => l.classList.contains('gp-checked')));
		// Toggle line `i`; Shift = cumulative (check it AND everything above). Fired by
		// a checkbox click OR a double-click anywhere on the line.
		const toggle = (e: MouseEvent, i: number) => {
			e.stopPropagation();
			if (e.shiftKey) {
				for (let k = 0; k <= i; k++) setChecked(lines[k], true); // cumulative: up to here
			} else {
				const turningOn = !lines[i].classList.contains('gp-checked');
				setChecked(lines[i], turningOn);
				// A plain check-ON fires this line's named trigger (if any) — "I just
				// covered this live". Shift's cumulative catch-up and unchecking do NOT
				// fire: neither one is a speaker doing the thing right now.
				if (turningOn) fire(lines[i]);
			}
			persist();
		};
		// Console-initiated clear: the localStorage was already wiped (page or deck), so
		// just visually uncheck the current lines.
		const onClear = () => lines.forEach((l) => setChecked(l, false));
		// Note-driven spotlight: a line carrying `data-highlight="db"` lights the Block
		// named "db" while the speaker's pointer is over it — "covering the line" — and
		// clears when it leaves. Drives the LOCAL store (this window) and RELAYS to the
		// audience window (the console's slide is hidden, so the relay is what the
		// audience actually sees; see Spotlight / stores/highlightTarget). Reuses this
		// same per-line pass rather than a second scan of the note.
		const light = (name: string | null) => { setHighlight(name); publishHighlight(ctx.deckKey, name); };
		// Note-driven trigger: a line carrying `data-trigger="save-cursor"` fires that
		// name — locally AND relayed to the audience window (see stores/triggers /
		// presenter's publishTrigger) — the instant its checkbox is checked. A
		// discrete "start this now" pulse, unlike the highlight's hover-driven state.
		const fire = (line: HTMLElement) => {
			const name = line.getAttribute('data-trigger');
			if (name) { fireTrigger(name); publishTrigger(ctx.deckKey, name); }
		};
		function setup() {
			teardown();
			if (!ctx.enabled) return;
			lines = Array.from(node.children).filter((c): c is HTMLElement => c instanceof HTMLElement);
			const saved = loadChecks(ctx.deckKey, ctx.slidePath);
			lines.forEach((line, i) => {
				line.classList.add('gp-note-line');
				const box = document.createElement('span');
				box.className = 'gp-check';
				box.setAttribute('role', 'checkbox');
				box.addEventListener('click', (e) => toggle(e as MouseEvent, i)); // removed with the box
				line.insertBefore(box, line.firstChild);
				// Double-click anywhere on the line toggles too (Shift = cumulative). The
				// line element persists (slot content), so track this listener for cleanup.
				const onDbl = (e: Event) => toggle(e as MouseEvent, i);
				line.addEventListener('dblclick', onDbl);
				cleanups.push(() => line.removeEventListener('dblclick', onDbl));
				// A `data-highlight="name"` line becomes a spotlight trigger: hover to
				// light the named Block, leave to clear. Ephemeral by design — the cue
				// tracks the speaker's attention, it is not a persistent check.
				const hl = line.getAttribute('data-highlight');
				if (hl) {
					line.classList.add('gp-hl-line');
					const onEnter = () => light(hl);
					const onLeave = () => light(null);
					line.addEventListener('pointerenter', onEnter);
					line.addEventListener('pointerleave', onLeave);
					cleanups.push(() => {
						line.classList.remove('gp-hl-line');
						line.removeEventListener('pointerenter', onEnter);
						line.removeEventListener('pointerleave', onLeave);
					});
				}
				if (line.hasAttribute('data-trigger')) line.classList.add('gp-trigger-line');
				setChecked(line, !!saved[i]); // restore persisted state
			});
			window.addEventListener('gp:checks-clear', onClear);
		}
		function teardown() {
			window.removeEventListener('gp:checks-clear', onClear);
			cleanups.forEach((fn) => fn());
			cleanups = [];
			light(null); // never leave a spotlight stuck when the note re-sets or unmounts
			lines.forEach((line) => {
				line.classList.remove('gp-note-line', 'gp-checked', 'gp-trigger-line');
				line.querySelector(':scope > .gp-check')?.remove();
			});
			lines = [];
		}
		setup();
		return {
			update(next: CheckCtx) { ctx = next; setup(); },
			destroy: teardown
		};
	}
</script>

{#if visible}
<div
	class="note no-print {klass}"
	class:presenter={$presenterMode}
	class:kiosk-source={kioskSourceOnly}
	id={id || undefined}
	style={style || undefined}
	use:checklist={{ enabled: $presenterMode, deckKey, slidePath }}
	use:publishKioskText={{ enabled: kioskShowNotes }}
>
	<slot></slot>
</div>
{/if}

<style>
.note {
	position: absolute;
	display: block;
	width: calc(100% - 30px);
	top: calc(100% + 30px);
	left: 0;
	padding: 15px;

	color: #000;
	background-color: beige;

	border: 1.5px solid #fff;
	border-radius: 7.5px;

	min-height: 225px;
	max-height: 225px;
	overflow-y: scroll;

	font-size: larger;
	font-family: ui-sans-serif, system-ui, Segoe UI, Helvetica, Apple Color Emoji, Arial, sans-serif, Segoe UI Emoji, Segoe UI Symbol;
}

/* Kiosk text source only — caption is rendered outside the scaled canvas. */
.note.kiosk-source {
	position: absolute !important;
	width: 1px !important;
	height: 1px !important;
	min-height: 0 !important;
	max-height: none !important;
	padding: 0 !important;
	margin: -1px !important;
	overflow: hidden !important;
	clip: rect(0, 0, 0, 0) !important;
	border: 0 !important;
	white-space: nowrap !important;
	pointer-events: none !important;
}

/* Presenter console: the note becomes the right-hand notes panel, pinned to the
   viewport (not the slide). `visibility:visible` overrides the hidden slide
   SlideDeck sits it inside. Geometry reads the SAME --gp-* layout vars
   PresenterView sets on <body.gp-present> (inherited here), so the panel's left
   edge lands a half-gap RIGHT of --gp-split and butts the preview column with an
   exact --gp-gap between them — no overlap. */
.note.presenter {
	position: fixed;
	visibility: visible;
	top: var(--gp-inset, 20px);
	left: calc(var(--gp-split, 50vw) + var(--gp-gap, 16px) / 2);
	right: var(--gp-inset, 20px);
	/* Override the SCALED-mode `width: calc(100% - 30px)`, which would otherwise win
	   over left+right and push the panel off the right edge. left+right size it. */
	width: auto;
	bottom: calc(var(--gp-bar-h, 130px) + var(--gp-inset, 20px));
	/* Override the SCALED-mode below-slide box: fill the panel instead. */
	min-height: 0;
	max-height: none;
	z-index: 60;

	padding: 24px 28px;
	font-size: 1.5rem;
	line-height: 1.5;
	border-radius: 10px;
	box-shadow: 0 6px 24px rgba(0, 0, 0, 0.35);
}

/* Per-line check-off (added to slotted children by the `checklist` action, so
   these must be :global). The leading box is inline-block, which stops the checked
   line's line-through from striking the checkbox glyph itself. */
/* Lines are double-click-to-toggle targets, so suppress the text selection a
   double-click would otherwise make (it's a check-off aid, not prose to select). */
.note.presenter :global(.gp-note-line) {
	user-select: none;
}
/* A spotlight-trigger line: hovering it lights a Block on the audience slide.
   Advertise it as a target — a pointer cursor and a faint accent tint — so the
   speaker knows which lines drive a highlight. */
.note.presenter :global(.gp-hl-line) {
	cursor: pointer;
}
.note.presenter :global(.gp-hl-line:hover) {
	color: var(--spotlight-ring, #F0A33E);
}
.note.presenter :global(.gp-check) {
	display: inline-block;
	margin-right: 0.5em;
	cursor: pointer;
	user-select: none;
	color: #2563a8;
	line-height: 1;
}
.note.presenter :global(.gp-check)::before {
	content: '\2610'; /* ☐ */
}
.note.presenter :global(.gp-checked) > :global(.gp-check)::before {
	content: '\2611'; /* ☑ */
}
.note.presenter :global(.gp-checked) {
	text-decoration: line-through;
	opacity: 0.5;
}
</style>
