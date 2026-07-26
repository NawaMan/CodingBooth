<!--
  SlideDeck — the reusable shell for a Presentation artifact.

  A Presentation is many discrete, fixed-size slide pages. This component is the
  whole canvas: it draws a fixed width x height box and shows it in one of two
  display modes (see $lib/stores/displayMode):
    - FITTED: scale the box to fit the window, preserving aspect (present mode).
    - SCALED: show the box at an exact factor (1 = native px), centred and
      pannable when it overflows the window (inspect mode), with a minimap.
  It also mounts the slide chrome (Table of Contents, display-mode control,
  copyright). The slides themselves flow in via the default <slot/>.

  Orientation lives HERE, set by a deck's +layout.svelte through the width/height
  props — never a runtime toggle. A landscape deck wraps its <slot/> in
  <SlideDeck width={1920} height={1080}>; a portrait deck (e.g. a YouTube Short)
  uses <SlideDeck width={1080} height={1920}>. Each slide's layout is authored
  for its deck's fixed dimension, so a deck is landscape OR portrait, full stop.

  Note: the deck's +layout.svelte must still call setPages(pages) itself — the
  slotted slide content is lexically owned by the layout, so it reads the
  layout's context, not this component's. `pages` is passed here only for the
  Table of Contents rendered inside this shell.
-->
<script lang="ts">
	import '$lib/styles/global.css';
	import '$lib/styles/note.css';
	import '$lib/styles/presentation.css';
	import '$lib/styles/tooltip.css';

	import Copyright      from '$lib/components/Copyright.svelte';
	import TableOfContent from '$lib/components/TableOfContent.svelte';
	import OverviewPage  from '$lib/components/OverviewPage.svelte';
	import SlideToolbar   from '$lib/components/SlideToolbar.svelte';
	import ControlBar     from '$lib/components/ControlBar.svelte';
	import NavigationBar  from '$lib/components/NavigationBar.svelte';
	import SlideMap       from '$lib/components/SlideMap.svelte';
	import PresenterView  from '$lib/components/PresenterView.svelte';
	import Seo            from '$lib/components/Seo.svelte';
	import { SITE_DESCRIPTION } from '$lib/seo/config';
	import { pageRule, sheetMetrics } from '$lib/handout/handoutCore';
	import { applyPageRule } from '$lib/handout/pageRuleDom';
	import { printNotes } from '$lib/stores/printNotes';
	import { overviewOpen } from '$lib/stores/overviewOpen';
	import {
		pageSourceCanView,
		pageSourceCanEdit,
		pageSourceHasOwner,
		deckSourceFallback,
		openPageSource,
		openPageSourceEdit,
		closePageSource
	} from '$lib/stores/pageSource';
	import {
		chromeArmed,
		armChrome,
		disarmChrome,
		keepChromeArmed,
		requestTocOpen,
		requestDisplayMenu,
		openMoreMenu,
		closeMoreMenu,
		toggleMoreMenu,
		moreMenuOpen
	} from '$lib/stores/chromeArm';
	import {
		chromeKeyIntent,
		moreMenuKeyIntent,
		isAdjustSaveChord,
		isChromeTypingTarget
	} from '$lib/chrome/chromeArmCore';
	import {
		arrowDir,
		focusIndexOf,
		nextNavIndex,
		toolbarNavZone
	} from '$lib/chrome/chromeToolbarNavCore';
	import CodeBox from '$lib/components/CodeBox.svelte';

	// Deck-level SOURCE CodeBox (slides without ViewSource). Opened by openPageSource
	// when it fills deckSourceFallback; closing the box clears the fallback.
	// Track "just appeared" so we open without fighting the user's CLOSE click
	// (a bare `$: if (fallback) expanded = true` would re-open every tick).
	let deckSourceExpanded = false;
	let deckSourceHadFallback = false;
	$: {
		const has = !!$deckSourceFallback;
		if (has && !deckSourceHadFallback) deckSourceExpanded = true;
		if (!has) deckSourceExpanded = false;
		if (has && deckSourceHadFallback && !deckSourceExpanded) closePageSource();
		deckSourceHadFallback = has;
	}

	import { browser }    from '$app/environment';
	import { page }       from '$app/stores';
	import { base }       from '$app/paths';
	import { onMount, tick } from 'svelte';
	import { displayMode, displayFactor, clampFactor } from '$lib/stores/displayMode';
	import type { DisplayMode } from '$lib/stores/displayMode';
	import { adjustMode, canAdjust, canSave, setAdjustOffered, applyAdjustParam } from '$lib/stores/adjustMode';
	import Annotate from '$lib/components/Annotate.svelte';
	import {
		annotationMode,
		canAnnotate,
		setAnnotateOffered,
		applyAnnotateParam,
		setInkPath,
		inkStaleAfterMs
	} from '$lib/stores/annotation';
	import { captureSlide, downloadBlob } from '$lib/capture/captureSlide';
	import { captureFileName, readCaptureParam, refusalText, resolveCanCapture, readSticky } from '$lib/capture/captureCore';
	import { saveAdjust } from '$lib/stores/adjustSave';
	import { getViewTransitions } from '$lib/presentation';
	import KioskDialog from '$lib/components/KioskDialog.svelte';
	import KioskIndicator from '$lib/components/KioskIndicator.svelte';
	import KioskRunner from '$lib/components/KioskRunner.svelte';
	import {
		canKiosk,
		kioskActive,
		kioskPanelPinned,
		kioskDeckDefaults,
		setCanKiosk,
		applyKioskParam,
		bootKioskFromUrl,
		resolveOffered as resolveKioskOffered,
		openKioskDialog,
		toggleKioskPause
	} from '$lib/stores/kiosk';
	import { DEFAULT_PAGE_MS, DEFAULT_STEP_MS, DEFAULT_WPM } from '$lib/kiosk/kioskCore';
	import {
		presenterMode, publishCurrentSlide, subscribeCurrentSlide, subscribeAnimCommand,
		subscribeContinue, subscribeHighlight, subscribeTrigger, deckKeyFromPath, openPresenterWindow,
		consoleLive, publishConsoleAlive, subscribeConsoleAlive, loadConsoleBeat
	} from '$lib/stores/presenter';
	import { consoleIsLive, CONSOLE_BEAT_MS, CONSOLE_TTL_MS } from '$lib/utils/consoleLiveCore';
	import { roleOf } from '$lib/utils/relayCore';
	import Spotlight from '$lib/components/Spotlight.svelte';
	import { setHighlight } from '$lib/stores/highlightTarget';
	import { fireTrigger } from '$lib/stores/triggers';
	import { collectFinite, applyState } from '$lib/utils/slideAnim';
	import { navigate } from '$lib/utils/deckNav';
	import { documentTitle, getPageNavigation } from '$lib/utils/navigate';
	import type { Page }  from '$lib/utils/navigate';

	/** This deck's slide list — for the Table of Contents rendered in the shell. */
	export let pages: Array<Page> = [];
	/** Presentation-level document title (the deck name) — the <title> counterpart
	    to the presentation favicon a +layout.svelte sets. Composed with the current
	    slide's own `title` into the browser-tab <title>; falls back to the site
	    default (SITE_TITLE) when left undefined. */
	export let title: string | undefined = undefined;
	/** Presentation-level SEO description, used for every slide that doesn't set its
	    own in pages.ts. Defaults to the site description. */
	export let description: string = SITE_DESCRIPTION;
	/** Presentation-level social/OG image (absolute URL or site-relative path), used
	    for slides without their own. Undefined falls back to the site-default image. */
	export let image: string | undefined = undefined;
	/** Presentation-level alt text for the social image, used for slides without
	    their own. Undefined falls back to the default card alt (see Seo). */
	export let imageAlt: string | undefined = undefined;
	/** Canvas size in px. Landscape: 1920x1080. Portrait (Tall): 1080x1920. */
	export let width  = 1920;
	export let height = 1080;
	/* Base font-size lever: every em-based size in the reused components scales
	   from here in one place. The landscape canvas grew x1.5 from the original
	   1280x720, hence 1.5em; a narrower portrait canvas wants a smaller base
	   (routes/portrait sets its own).

	   It is the ONE knob for the deck's text size: turn it and every em-sized
	   component in every reused template moves together. What does NOT move is
	   anything measured in canvas PIXELS — a <Block>'s x/y/width/height, an image, a
	   Connector — because those are placements, not type. So turning it down shrinks a
	   slide's prose INSIDE its Block while the Block stays where its author put it,
	   which is why 1.2em was tried here and put back: the two stop agreeing.

	   Keep it equal to handoutCore.DEFAULT_BASE_FONT (the handout cannot read this
	   default, so it restates it; tests/SlideDeckPrint.test.ts pins the pair). */
	export let baseFontSize = '1.5em';
	/* Optional extra classes for the outer frame — the hook a deck uses to opt into
	   a theme. Pass "gp-deck theme-green" (and import themes.css + roles.css in the
	   deck's +layout.svelte) to recolour the whole canvas via the role tokens. Left
	   empty by default, so existing decks render exactly as before. */
	export let deckClass = '';
	/* Exact-fit mode. When false (the landscape default) the content box keeps its
	   legacy slack (+20 width / -30 height / 15 padding) — values hand-tuned for the
	   1920 canvas, whose wider-than-frame aspect leaves a small symmetric letterbox.
	   That gap is a tiny fraction at 1920 but visible on the much smaller portrait
	   render, so a Tall opts into fill=true: the content box IS the canvas
	   (border-box, no slack), so it shares the frame's aspect exactly and fills it
	   edge to edge. Either way the FITTED view scale (adjustSize) is an exact
	   Math.min fit, so content always sits inside the frame border. */
	export let fill = false;
	/* Optional per-deck overrides for the content surface — for themed decks (e.g.
	   GeekLight) that want a custom background (a watercolor image) or font while
	   reusing all the canvas/scaling machinery. Undefined keeps the standard dark
	   surface + Noto Sans. Passed through as CSS vars the .content rule falls back on. */
	export let contentBackground: string | undefined = undefined;
	export let contentFont: string | undefined = undefined;

	/* Show the TOC's extra link (article view, "back to home", …). Off by default —
	   only decks that want it should enable it. `articleText`/`articleHref` customise
	   the label and target (href is relative to the current slide URL). */
	export let article = false;
	export let articleText = 'View as article';
	export let articleHref = '../text.html';

	/* Fade the deck's own controls (NAV, TOC, DISPLAY/minimap, ADJUST) down to a
	   ghost until the pointer reaches them, so the slide — not the chrome — is what
	   the audience looks at. Especially wanted where the chrome sits over someone
	   else's pixels (a full-canvas WebPage). Opt-in: a deck that says nothing keeps
	   the controls at full strength.

	   The controls keep their full hit area while faded (opacity, not visibility),
	   and any that are OPEN or PINNED stay lit — you can't hunt for a menu you are
	   already using. Touch devices have no hover to reveal with, so the fade is
	   disabled there outright. */
	export let fadeChrome = false;

	/* Bottom ControlBar (TOC + FIRST/PREV/NEXT/LAST + hosted AnimationBar). On by
	   default — opt OUT with `controlBar={false}` for a bare canvas (e.g. a kiosk
	   deck, or one that brings its own pager). Keyboard paging still works if a
	   NavigationBar is mounted elsewhere; this only removes the window-edge bar.
	   Independent of `toolBar`. Hidden either way under `?clean` / `?present`. */
	export let controlBar = true;

	/* Top tool bar (PRESENT / ANNOTATE / ADJUST / DISPLAY / ☰ OVERVIEW·CAPTURE·
	   PRINT·SOURCE·EDIT). On by default — opt OUT with `toolBar={false}` when the
	   deck is audience-facing and the authoring cluster would only distract. Many
	   of those rows are *more* useful in vite dev (SOURCE/EDIT write-back, ADJUST
	   SAVE, CAPTURE experiments); a published talk can drop the whole bar and
	   keep `controlBar` for navigation. Independent of `controlBar`. Hidden either
	   way under `?clean` / `?present`. */
	export let toolBar = true;

	/* Offer the ADJUST authoring control on EVERY slide of this deck, even in a build.
	   Almost no deck wants this — ADJUST is off in production by default, and the usual
	   way to demo it is per-slide: set `adjust: true` on the individual pages.ts entries
	   for the slides that actually teach it (see Page.adjust), which is what the /slides
	   deck does. This deck-wide switch exists for the rare deck that is ENTIRELY about
	   authoring.

	   Either way it makes ADJUST *available*, not *active*: the mode still starts off, so
	   the audience sees a normal slide until the speaker flips it. `vite dev` offers the
	   control regardless, and a sticky `?adjust=off` outranks both (adjust/adjustAccessCore). */
	export let adjust = false;

	/* Offer the ANNOTATE control — the speaker's pen. Deck-wide and nothing else, because
	   annotation is a SPEAKER tool, not an authoring one: ADJUST is per-slide since the
	   slide being authored has an opinion about whether you should be dragging on it,
	   whereas the slide the speaker happens to be standing on has no opinion about whether
	   they may circle a word on it. So there is no per-slide `annotate` flag to match
	   `adjust: true` — see annotate/annotateAccessCore.

	   Available, not active: the mode still starts off. `vite dev` offers the pen
	   regardless, and a sticky `?annotate` / `?annotate=off` outranks this prop. */
	export let annotate = false;

	/* Ink PERSISTS per slide, across reloads — so it can also go stale. A slide whose marks
	   are older than this says so on arrival and offers to clear them. In HOURS; a day by
	   default, so today's marks never nag and a previous sitting's always do. */
	export let inkStaleAfter = 24;

	/* The pen's swatches. The FIRST is the theme's own colour (null → painted by the
	   --annot-* role token), so the default follows a re-theme rather than freezing a hex. */
	export let inkColors: (string | null)[] = [null, '#E5484D', '#3FA9F5', '#4BD07A', '#FFFFFF'];

	/* Keep a highlighter swipe LEVEL: the band sits on the row you swiped rather than sloping
	   along with the hand that drew it. A highlighter is not a pen — nobody wants a wonky
	   highlight. Set false for a genuinely freehand highlighter. */
	export let levelHighlight = true;

	/* Offer CAPTURE — download the current slide as a PNG at TRUE canvas resolution (1920x1080),
	   not at whatever size the window is showing it. Annotations are included; the deck's own
	   chrome is not. Like ANNOTATE this is deck-wide and sticky (`?capture`), because taking a
	   screenshot is the speaker's decision, not the slide's. */
	export let capture = false;

	/* Multiply the captured PNG's resolution (2 → a 3840x2160 file from a 1920x1080 canvas).
	   The slide is re-rendered, not upscaled, so it stays crisp. */
	export let captureScale = 1;

	/* Offer Kiosk / auto-advance (☰ → Kiosk, sticky `?kiosk`). Deck-wide speaker tool —
	   same access shape as ANNOTATE / CAPTURE: vite dev always, sticky URL, or this prop.
	   Available is not active: the mode starts off until the dialog's Start or `?kiosk`. */
	export let kiosk = false;

	/* Deck defaults for kiosk dwell (ms). The setup dialog can override per browser;
	   step is for in-slide builds (Space-style), page is after the build finishes. */
	export let kioskStepMs = DEFAULT_STEP_MS;
	export let kioskPageMs = DEFAULT_PAGE_MS;

	/* Words-per-minute when "use speaker notes for page timing" is on. */
	export let kioskWpm = DEFAULT_WPM;

	let viewport:  HTMLElement;
	let container: HTMLElement;
	let content:   HTMLElement;

	let mode: DisplayMode = $displayMode;
	let factor = clampFactor($displayFactor);
	let initialized = false;
	// On-screen scale of the slide content set by adjustSize() (the FITTED fit factor,
	// or the SCALED zoom factor), exposed to the content as --view-scale for any chrome
	// that needs to counter the slide transform. (DISPLAY no longer uses it — it's a
	// viewport control now, sized independently of the slide.)
	let viewScale = 1;
	$: isFitted = mode === 'FITTED';
	$: aspectRatio = width / height;

	// Minimap state (SCALED only): which slice of the slide is currently on screen,
	// as fractions of the scaled slide. Recomputed on scroll / resize / mode change.
	let mapVisible = false;
	let mapRect = { left: 0, top: 0, width: 1, height: 1 };
	const clamp01 = (n: number) => Math.max(0, Math.min(1, n));

	// The top-centre tool cluster (PRESENT + the menu) and DISPLAY both live in the
	// window-fixed overlay now (see <SlideToolbar>) — window controls, reachable no matter
	// how the slide is scaled or panned — so there is nothing frame-relative to recompute
	// here. updateOverlay is kept as the minimap's recompute hook.
	function updateOverlay() {
		updateMap();
	}

	// Page-level favicon. The shell renders at SSR (only the slide *content* below
	// is gated on onMount), so emitting the current slide's favicon HERE puts it in
	// the prerendered HTML — no flicker, works without JS. Last <link rel="icon">
	// wins, so a slide's favicon (declared in its pages.ts entry) overrides both the
	// site default (app.html) and any presentation favicon set in the deck's layout.
	$: currentSlide   = $page.url.pathname.replace(/\/+$/, '').split('/').pop();
	$: currentIndex   = pages.findIndex((p) => p.path === currentSlide);
	// The current slide's neighbours in the linear order, for the ControlBar's ONE
	// deck-level pager — the same helper each template used to call for its own bar,
	// now computed once here. Hidden/appendix slides resolve to all-undefined links
	// (and their own template keeps its RETURN pager, so this one goes dormant anyway).
	$: deckNavigation = getPageNavigation(pages, currentSlide ?? '', './');
	$: currentFavicon = pages.find((p) => p.path === currentSlide)?.favicon;
	// `?clean` hides all shell chrome (ToC, display-mode control, copyright, nav bar,
	// minimap) for an unobstructed screen capture — e.g. the /tests calibration
	// target. `browser &&` short-circuits so url.searchParams is never read during
	// prerender (SvelteKit forbids it — a prerendered page can't vary by query
	// string). Client hydration re-evaluates with browser=true and picks up ?clean.
	// `?shot` implies `?clean`: a screenshot never wants the nav bar, the TOC or the buttons.
	$: clean = browser && ($page.url.searchParams.has('clean') || $page.url.searchParams.has('shot'));
	// `?present` turns THIS window into the presenter console (see stores/presenter
	// + PresenterView). Browser-guarded like `?clean`, so it never affects SSR /
	// prerender output. presenterMode (the store <Note> and NavigationBar read) is
	// kept in step with it.
	$: present = browser && $page.url.searchParams.has('present');
	$: presenterMode.set(present);
	// `?shot` — the BUILD-TIME capture render (see utils/capture-slides.sh). The canvas at
	// exactly 1:1, top-left, no frame border, no letterbox, and no chrome: point a headless
	// browser at it with a window the size of the canvas and the viewport IS the slide, so the
	// PNG needs no cropping and no scaling. It implies `?clean` (which is why `clean` reads it
	// too), and it is the one mode that deliberately does NOT fit the slide to the window —
	// fitting is what a human wants and exactly what a screenshot must not do.
	$: shot = browser && $page.url.searchParams.has('shot');

	// PRINTING one slide. The deck is a viewport — a canvas scaled to whatever window it found —
	// and paper is not a window: it has a fixed size, no scrollbars and no JS. Left alone, Ctrl+P
	// photographs the viewport, which is how you get a slide chopped off down the right-hand side
	// of a portrait sheet. So print takes the same deal the handout takes: the SHEET becomes the
	// shape of the canvas (the @page rule in <svelte:head>) and the canvas is scaled onto it by
	// `--print-scale`. Computed here, not in CSS, because CSS cannot divide inches by pixels —
	// and taken from handoutCore so a printed slide and that slide inside a handout are the same
	// size, necessarily rather than by coincidence.
	//
	// `?notes` prints the slide WITH its speaker note beneath it, on the one page — the same flag
	// the handout takes, and the paper grows by the same three inches. It reaches the <Note>
	// through a store rather than context: a slide is the ADJUST's slot content, so it cannot see
	// anything this shell sets (the same reason setPages() lives in each deck's +layout.svelte).
	// See stores/printNotes.
	// `?notes` in the URL, OR the PRINT menu's "this slide + notes" (which prints without
	// navigating, so it drives a local override instead of the address bar).
	let printNotesOverride = false;
	$: wantsNotes = (browser && $page.url.searchParams.has('notes')) || printNotesOverride;
	$: printNotes.set(wantsNotes);
	$: printMetrics = sheetMetrics({ width, height }, wantsNotes);
	// Written to the head, not declared in <svelte:head> — see pageRuleDom for why that is not a
	// style choice: an {@html} in the head survives hydration unchanged, so `?notes` grew the
	// frame and left the paper the size the SERVER thought it should be.
	$: if (browser) applyPageRule(pageRule(printMetrics));
	// Cross-window sync: whoever navigates publishes the new slide path; the other
	// window follows. deckKey namespaces it per deck so /slides/ and /portrait/
	// consoles never cross-drive. This deck's paging strategy is read once for the
	// follower to navigate exactly like a click.
	const viewTransitions = getViewTransitions();
	$: deckKey = browser ? deckKeyFromPath($page.url.pathname) : '/';
	// Only the TOP window syncs. The presenter console renders the next slide in an
	// <iframe> (a full deck instance); without this guard that iframe would publish
	// ITS slide to the shared channel and drag every window onto the preview slide.
	$: isTopWindow = browser && window.self === window.top;
	// Every announcement is TAGGED with this window's role, and the follow below only
	// accepts a sender whose role differs. Without it the channel is a broadcast: two
	// ordinary tabs of one deck both publish and both follow, so paging in either yanks
	// the other. deckKey answers "which deck?"; the role answers "who may drive whom?".
	$: relayRole = roleOf(present);
	$: if (isTopWindow && currentSlide) publishCurrentSlide(deckKey, currentSlide, relayRole);
	// Does THIS slide offer ADJUST? Its own pages.ts `adjust` flag, or the deck-wide
	// `adjust` prop. Re-runs on every slide change, so paging off a ADJUST demo onto an
	// ordinary slide takes the control away again. The sticky `?adjust` flag outranks
	// both (adjust/adjustAccessCore). Browser-guarded so url.searchParams is never read
	// during prerender.
	$: slideOffersAdjust = pages.find((p) => p.path === currentSlide)?.adjust === true;
	$: adjustOffered = slideOffersAdjust || adjust;
	$: if (browser) setAdjustOffered(adjustOffered);
	$: if (browser) applyAdjustParam($page.url);

	// ANNOTATE (the speaker's pen) resolves from the DECK, not the slide — there is no
	// per-slide flag to fold in, so this is set once from the prop rather than per page.
	$: if (browser) setAnnotateOffered(annotate);
	$: if (browser) applyAnnotateParam($page.url);
	$: inkStaleAfterMs.set(Math.max(0, (Number(inkStaleAfter) || 24)) * 60 * 60 * 1000);

	// Point the ink at THIS slide. Ink is persisted per slide (stores/annotation.inkBook), so
	// navigation does not destroy it — it just changes which page of the book we are looking
	// at, and the drawing is still there when you come back. The full pathname is the key, so
	// /slides/intro.html and /portrait/intro.html never scribble on each other.
	$: if (browser) setInkPath($page.url.pathname.replace(/\/+$/, ''));

	// CAPTURE — the same precedence as the pen (dev > sticky ?capture > the deck's prop > off),
	// for the same reason: a screenshot is the speaker's decision and the slide has no opinion.
	// The sticky value is written here rather than in a store, since there is no mode to hold —
	// pressing the button IS the whole feature.
	$: if (browser) {
		const choice = readCaptureParam($page.url.searchParams);
		if (choice !== null) localStorage.setItem('canCapture', String(choice));
	}
	$: canCapture = browser
		? resolveCanCapture(import.meta.env.DEV, readSticky(localStorage.getItem('canCapture')), capture)
		: false;

	// Kiosk — offered like CAPTURE; running is a separate session (stores/kiosk).
	// Sticky flag only here; auto-start is one-shot in onMount (bootKioskFromUrl).
	$: if (browser) {
		kioskDeckDefaults.set({
			stepMs: kioskStepMs,
			pageMs: kioskPageMs,
			useNotes: false
		});
		applyKioskParam($page.url);
		setCanKiosk(resolveKioskOffered(import.meta.env.DEV, kiosk));
	}

	// CAPTURE refuses out loud rather than sitting greyed out, exactly as SAVE does: a disabled
	// button reads as "broken or missing", while one that answers when pressed teaches you why a
	// slide with a live embed cannot be rasterised.
	let captureLabel = 'CAPTURE';
	let captureTip = '';
	let capturing = false;

	async function onCapture() {
		if (capturing || !container) return;
		capturing = true;
		captureLabel = '…';
		captureTip = '';
		try {
			const { blob, blockers } = await captureSlide(container, width, height, captureScale);
			if (blockers.length > 0) {
				captureTip = refusalText(blockers);
				captureLabel = 'NOT ALLOWED';
			} else if (!blob) {
				captureTip = 'The browser refused to draw this slide';
				captureLabel = 'FAILED';
			} else {
				downloadBlob(blob, captureFileName($page.url.pathname));
				captureLabel = 'SAVED';
			}
		} catch {
			captureTip = 'The browser refused to draw this slide';
			captureLabel = 'FAILED';
		} finally {
			capturing = false;
			setTimeout(() => {
				captureLabel = 'CAPTURE';
				captureTip = '';
			}, 2600);
		}
	}

	// PRINT — nested flyout off the ☰ → PRINT row (hover or click). Six destinations:
	// current / whole / grid, each plain or +notes. Mnemonics cCwWtT (lower = no notes,
	// upper = with notes). Nested beside the row so it no longer floats as a second
	// centred popover over the hamburger (which looked like two menus fighting).
	let printMenuOpen = false;

	// The flyout opens on MOUSEENTER, so it needs a way out that does not depend on a matching
	// mouseleave. When the ☰ shuts with the pointer parked on the PRINT row, the row goes
	// pointer-events:none underneath it and the browser owes us no mouseleave — the latch would
	// stay set, and the flyout would be sitting open the next time the ☰ opened. Its parent
	// closing is the authoritative "you are gone".
	moreMenuOpen.subscribe((open) => {
		if (!open) printMenuOpen = false;
	});

	// Print the CURRENT slide, optionally with its <Note>. The notes toggle is a local
	// override rather than a navigation, so it must be applied to the DOM/CSS BEFORE the
	// (blocking) print opens — hence the `await tick()`. Cleared when the dialog closes.
	async function printThisSlide(withNotes: boolean) {
		printMenuOpen = false;
		printNotesOverride = withNotes;
		await tick();
		if (browser) window.print();
	}

	// The current deck's name, from the URL: `/slides/title.html` -> `slides`. The handout for it
	// lives OUTSIDE the deck at `/_handout/<deck>.html`, so whole-deck / grid options navigate
	// there rather than printing in place — the handout is a different document.
	$: deckName = ($page.url.pathname.replace(base, '').split('/').filter(Boolean)[0]) || '';
	function openHandout(query: string) {
		printMenuOpen = false;
		// A FULL navigation, not a client-side goto. The handout is a separate top-level document
		// (outside the deck's layout, rendering all 65 slides at once) — a hard load renders it
		// exactly as visiting the URL does, where a client-side hop into that other layout came up
		// blank. It is the printable document; landing on it fresh is the honest thing anyway.
		// `query` selects the layout: '' pages, '?notes' pages+notes, '?grid' the thumbnail grid,
		// '?grid&notes' the notes grid.
		if (browser) window.location.assign(`${base}/_handout/${deckName}.html${query}`);
	}

	/**
	 * Keyboard while the PRINT flyout is open: cCwWtT (case-sensitive), plus Escape.
	 *
	 * Returns whether it CLAIMED the key. It used to return nothing and the caller treated
	 * "flyout is open" as "the flyout owns the whole keyboard", so every unclaimed key —
	 * Alt+., m, the arrows — was swallowed. That is only ever one stuck `printMenuOpen`
	 * away from a deck that ignores the keyboard until the page is reloaded, and the flyout
	 * opens on HOVER, which is exactly the kind of latch that gets stuck.
	 */
	function onPrintMenuKey(e: KeyboardEvent): boolean {
		if (!printMenuOpen) return false;
		if (e.ctrlKey || e.metaKey || e.altKey) return false;
		if (e.key === 'Escape') {
			e.preventDefault();
			// Back one level: close the PRINT flyout only (☰ can stay for another pick).
			printMenuOpen = false;
			return true;
		}
		// Case-sensitive: lower = without notes, upper = with notes.
		const map: Record<string, () => void> = {
			c: () => printThisSlide(false),
			C: () => printThisSlide(true),
			w: () => openHandout(''),
			W: () => openHandout('?notes'),
			t: () => openHandout('?grid'),
			T: () => openHandout('?grid&notes')
		};
		const act = map[e.key];
		if (!act) return false;
		e.preventDefault();
		act();
		// A real destination was picked — put the whole ☰ away (flyout already cleared
		// itself inside printThisSlide / openHandout).
		closeMoreMenu();
		return true;
	}

	/** This deck's window-fixed chrome overlay — the scope for chrome DOM lookups. */
	let chromeOverlay: HTMLDivElement | undefined;

	/** Focusable controls on the top bar (PIN … ☰), not rows inside the ☰ drop. */
	function barFocusables(): HTMLElement[] {
		const root = chromeOverlay?.querySelector('.annot-tools');
		if (!root) return [];
		const nodes = root.querySelectorAll(
			':scope > button, :scope > .save-btn > button, :scope > .mode button, :scope > .annot-menu > .annot-hamburger'
		);
		return [...nodes].filter((el): el is HTMLElement => el instanceof HTMLElement && !(el as HTMLButtonElement).disabled);
	}

	/** Enabled ☰ drop rows (OVERVIEW / KIOSK / …). */
	function moreFocusables(): HTMLElement[] {
		const drop = chromeOverlay?.querySelector('.annot-drop');
		if (!drop) return [];
		return [...drop.querySelectorAll('button.annot-tool')].filter(
			(el): el is HTMLElement => el instanceof HTMLElement && !(el as HTMLButtonElement).disabled
		);
	}

	/** PRINT flyout destinations. */
	function printFocusables(): HTMLElement[] {
		const sub = chromeOverlay?.querySelector('.print-sub');
		if (!sub) return [];
		return [...sub.querySelectorAll('button')].filter(
			(el): el is HTMLElement => el instanceof HTMLElement && !(el as HTMLButtonElement).disabled
		);
	}

	function focusToolbarEl(el: HTMLElement | null | undefined) {
		if (!el) return;
		el.focus();
		el.scrollIntoView?.({ block: 'nearest' });
	}

	/**
	 * Arrow roving focus on the raised tool bar / ☰ drop / PRINT flyout.
	 * Returns true when the key was claimed (so deck paging must not move).
	 * Yields to SizeMode while its zoom menu is open.
	 */
	function onToolbarArrows(e: KeyboardEvent): boolean {
		const dir = arrowDir(e);
		if (!dir) return false;
		if (isChromeTypingTarget(e.target)) return false;

		const tools = chromeOverlay?.querySelector('.annot-tools');
		if (!tools) return false;

		// DISPLAY zoom menu owns ↑/↓ while open.
		if (tools.querySelector('.mode.expanded')) return false;

		const bar = barFocusables();
		const more = moreFocusables();
		const print = printFocusables();
		const ae = browser ? (document.activeElement as HTMLElement | null) : null;
		const hamburger = tools.querySelector('.annot-hamburger') as HTMLElement | null;
		const drop = tools.querySelector('.annot-drop');
		const printSub = tools.querySelector('.print-sub');
		const printRow = tools.querySelector('.print-flyout > .annot-tool') as HTMLElement | null;

		const zone = toolbarNavZone({
			armed: $chromeArmed,
			moreOpen: $moreMenuOpen,
			printOpen: printMenuOpen,
			sizeMenuOpen: false,
			focusInPrint: !!(printSub && ae && printSub.contains(ae)),
			focusInMoreDrop: !!(drop && ae && drop.contains(ae)),
			focusOnHamburger: !!(hamburger && ae && (ae === hamburger || hamburger.contains(ae))),
			focusOnBar: !!(ae && tools.contains(ae) && !(drop && drop.contains(ae)))
		});
		if (zone === 'none') return false;

		if (zone === 'bar') {
			// ↓ on ☰ opens the drop and focuses the first row.
			if (dir === 'down' && hamburger && ae && (ae === hamburger || hamburger.contains(ae))) {
				e.preventDefault();
				openMoreMenu();
				keepChromeArmed();
				queueMicrotask(() => focusToolbarEl(moreFocusables()[0] ?? hamburger));
				return true;
			}
			if (dir !== 'left' && dir !== 'right') return false;
			const i = focusIndexOf(bar, ae);
			const next = nextNavIndex('bar', dir, i, bar.length);
			if (next == null || !bar.length) return false;
			e.preventDefault();
			focusToolbarEl(bar[next]);
			keepChromeArmed();
			return true;
		}

		if (zone === 'more') {
			const onHamburger = !!(hamburger && ae && (ae === hamburger || hamburger.contains(ae)));
			const inDrop = !!(drop && ae && drop.contains(ae));

			// ←/→ while focus is still on a top-bar control (drop open but not focused):
			// keep walking the bar rather than trapping in "more" zone.
			if ((dir === 'left' || dir === 'right') && !onHamburger && !inDrop) {
				const i = focusIndexOf(bar, ae);
				const next = nextNavIndex('bar', dir, i, bar.length);
				if (next == null || !bar.length) return false;
				e.preventDefault();
				focusToolbarEl(bar[next]);
				keepChromeArmed();
				return true;
			}

			// → on PRINT opens the flyout and focuses its first destination.
			if (dir === 'right' && ae && ae.closest?.('.print-flyout')) {
				e.preventDefault();
				printMenuOpen = true;
				keepChromeArmed();
				queueMicrotask(() => focusToolbarEl(printFocusables()[0] ?? printRow));
				return true;
			}
			// ← from a row → ☰; ← on ☰ → previous bar control.
			if (dir === 'left') {
				if (inDrop) {
					e.preventDefault();
					focusToolbarEl(hamburger);
					keepChromeArmed();
					return true;
				}
				if (onHamburger) {
					const i = focusIndexOf(bar, hamburger);
					const next = nextNavIndex('bar', 'left', i, bar.length);
					if (next == null) return false;
					e.preventDefault();
					focusToolbarEl(bar[next]);
					keepChromeArmed();
					return true;
				}
			}
			if (dir === 'right' && onHamburger) {
				const i = focusIndexOf(bar, hamburger);
				const next = nextNavIndex('bar', 'right', i, bar.length);
				if (next == null) return false;
				e.preventDefault();
				focusToolbarEl(bar[next]);
				keepChromeArmed();
				return true;
			}

			let i = focusIndexOf(more, ae);
			if (onHamburger) i = -1;
			const next = nextNavIndex('more', dir, i, more.length);
			if (next == null) return false;
			e.preventDefault();
			if (next < 0) focusToolbarEl(hamburger);
			else focusToolbarEl(more[next]);
			keepChromeArmed();
			return true;
		}

		if (zone === 'print') {
			const i = focusIndexOf(print, ae);
			const next = nextNavIndex('print', dir, i, print.length);
			if (next == null) return false;
			e.preventDefault();
			if (next < 0) {
				printMenuOpen = false;
				focusToolbarEl(printRow);
			} else {
				focusToolbarEl(print[next]);
			}
			keepChromeArmed();
			return true;
		}

		return false;
	}

	/**
	 * Alt+. raises both window-edge bars; while armed, a/j/z/p/m/t pick a bar control
	 * and o/k/c/r/s/e pick a ☰ row (opening the drop if needed). Arrow keys rove focus
	 * along the bar and the ☰ drop. Esc disarms chrome and closes the ☰ drop.
	 * Print-menu keys win when that flyout is open.
	 */
	function onChromeKeys(e: KeyboardEvent) {
		// Ctrl/Cmd+S while ADJUST is active (offered AND on) writes the moved Blocks
		// back to source instead of popping the browser's save-page dialog. It routes
		// through onSave(), so NOT-ALLOWED / partial-save handling is inherited rather
		// than duplicated; on a normal slide the chord is inert and the browser keeps
		// its shortcut.
		if (isAdjustSaveChord(e, $canAdjust && $adjustMode)) {
			e.preventDefault();
			onSave();
			return;
		}

		// PRINT submenu gets first refusal on its own alphabet (including Esc) — but only the
		// keys it actually claims. Anything else falls through to the chrome mnemonics.
		if (onPrintMenuKey(e)) return;

		// Arrow roving on the raised bar / ☰ (before letter mnemonics and before deck paging).
		if (onToolbarArrows(e)) return;

		// ☰ rows (underlined O/K/C/R/S/E): while the drop is open, or while chrome is
		// armed so a letter can open the drop and fire the row. Handled before bar
		// letters so they never collide (bar uses a/j/z/p/m/t).
		const moreIntent = moreMenuKeyIntent(e, $moreMenuOpen, $chromeArmed);
		if (moreIntent !== 'ignore') {
			e.preventDefault();
			// Ensure the drop is latched open for PRINT (and any brief paint of a row).
			if (!$moreMenuOpen) openMoreMenu();
			switch (moreIntent) {
				case 'overview':
					overviewOpen.set(true);
					closeMoreMenu();
					break;
				case 'kiosk':
					// Live kiosk: K reveals/hides the panel instead of reopening setup
					// (still reachable by mouse via the panel's own ⚙ button). Off: K
					// opens the dialog, same as before — the only keyboard way to start.
					if ($kioskActive) kioskPanelPinned.update((v) => !v);
					else if ($canKiosk) openKioskDialog();
					closeMoreMenu();
					break;
				case 'capture':
					if (canCapture) onCapture();
					closeMoreMenu();
					break;
				case 'print':
					// Leave ☰ open; open the PRINT flyout so cCwWtT can take over.
					printMenuOpen = true;
					keepChromeArmed();
					break;
				case 'source':
					if ($pageSourceCanView) openPageSource();
					closeMoreMenu();
					break;
				case 'edit':
					if ($pageSourceCanEdit) openPageSourceEdit();
					closeMoreMenu();
					break;
			}
			keepChromeArmed();
			return;
		}

		const intent = chromeKeyIntent(e, $chromeArmed);
		if (intent === 'ignore') return;
		e.preventDefault();

		switch (intent) {
			case 'arm':
				armChrome();
				// Land focus on the first bar control so ←/→ have a starting point.
				queueMicrotask(() => focusToolbarEl(barFocusables()[0]));
				return;
			case 'disarm':
				// Drop the ☰ open latch, then un-arm. Alt+. puts focus on the top bar so ←/→
				// work; that focus keeps the top bar seated via CSS `:focus-within` even after
				// `armed` is false — so Esc must blur ANY focus inside the chrome overlay
				// (top tool bar or bottom control bar), not only the ☰. A pointer still
				// hovering a bar keeps that bar open — plain hover, leave to tuck.
				closeMoreMenu();
				printMenuOpen = false;
				if (browser && document.activeElement instanceof HTMLElement) {
					const el = document.activeElement;
					if (el.closest?.('.overlay') || el.closest?.('.annot-tools') || el.closest?.('.ctrl-bar')) {
						el.blur();
					}
				}
				disarmChrome();
				return;
			case 'annotate':
				if ($canAnnotate) annotationMode.update((v) => !v);
				keepChromeArmed();
				return;
			case 'adjust':
				if ($canAdjust) adjustMode.update((v) => !v);
				keepChromeArmed();
				return;
			case 'display':
				// Open (toggle) the DISPLAY zoom menu — same control a click on FITTED (Z)
				// opens — so ↑/↓ can walk the presets. Does not flip FITTED/SCALED by itself.
				requestDisplayMenu();
				return;
			case 'present':
				openPresenter();
				keepChromeArmed();
				return;
			case 'more': {
				// A real toggle now — the drop's own `moreMenuOpen` latch, not a hope that
				// focus lands and CSS reacts. Focus still moves to the ☰ when opening, so the
				// panel is where Tab continues from; scoped to THIS deck's overlay, because a
				// presenter console has a second toolbar mounted in the same document and a
				// bare document.querySelector would happily focus the other one.
				const opened = toggleMoreMenu();
				const btn = chromeOverlay?.querySelector<HTMLElement>('.annot-hamburger');
				if (opened) btn?.focus();
				else btn?.blur();
				keepChromeArmed();
				return;
			}
			case 'toc':
				requestTocOpen();
				return;
			case 'kiosk-pause':
				// Inert unless a kiosk is actually running/paused — U does nothing on a
				// deck that never offered or started one.
				if ($kioskActive) toggleKioskPause();
				keepChromeArmed();
				return;
		}
	}

	// "Save" writes the slide's moved Blocks back to source. It only reaches a source
	// tree under `vite dev` (the endpoint lives in the dev server — see
	// adjust/devSavePlugin); on a static host there is nothing to rewrite.
	//
	// The button looks and behaves like a NORMAL control either way — no pre-emptive
	// greying-out. Where it can't fire, it says so ON CLICK: the label flips to
	// NOT ALLOWED and a tooltip explains that saving isn't allowed in this setup. That
	// ordering is the whole point of a ADJUST demo. A button disabled from the start
	// invites the audience to assume the feature is missing or broken; a button that
	// answers when pressed teaches them that saving is *refused here*, and why — the
	// deck is static, and there is no source tree behind it to rewrite.
	//
	// `$canSave` is a store (not `import.meta.env.DEV` inline) precisely so this refusal
	// path survives into the build instead of being compiled away.
	//
	// Either way the button's OWN label carries the outcome (SAVE → SAVED / NONE / ERROR
	// / NOT ALLOWED) and then reverts, so there's no extra chrome. Detail (which tags
	// didn't land, any error) goes to the console.
	let saveLabel = 'SAVE';
	let saveRefused = false;
	/** How many tags SAVE could not place, when the write landed only partly. 0 =
	    not a partial save. Drives the tooltip's wording; `saveRefused` drives the
	    look, since both outcomes are "read this before you carry on". */
	let savePartial = 0;
	/** The distinct causes among the unplaced tags, so the tooltip tells the TRUE
	    story: 'not-found' (the tag isn't in the source in literal form — geometry
	    via expressions, or reformatted) reads very differently from 'ambiguous'
	    (a twin such as a code sample ties the match). One blanket message here
	    used to blame a twin for every failure, sending authors hunting for a
	    code sample that didn't exist. */
	let saveReasons: Array<'not-found' | 'ambiguous'> = [];
	let saveTimer: ReturnType<typeof setTimeout> | undefined;

	// Each unmatched cause gets its own honest sentence; a mixed batch gets both.
	const UNMATCH_STORY = {
		'not-found':
			"The tag isn't in the source in its literal form (geometry written as " +
			'expressions, or a reformatted tag), so there is nothing to rewrite — ' +
			'Copy it and paste by hand.',
		ambiguous:
			'A tag whose name AND geometry match another (a code sample of itself, ' +
			'say) is ambiguous, so it is never guessed at — Copy that one by hand.'
	} as const;
	$: saveTip = savePartial
		? `${savePartial === 1 ? '1 tag' : `${savePartial} tags`} not written — see the console. ` +
			(saveReasons.length ? saveReasons : (['not-found'] as const))
				.map((r) => UNMATCH_STORY[r])
				.join(' ')
		: 'Save not allowed in this setup.';

	function flashSave(label: string, ms: number) {
		saveLabel = label;
		clearTimeout(saveTimer);
		saveTimer = setTimeout(() => {
			saveLabel = 'SAVE';
			saveRefused = false;
			savePartial = 0;
			saveReasons = [];
		}, ms);
	}

	async function onSave() {
		if (!$canSave) {
			// Held longer than a normal outcome flash: this one has a tooltip to read,
			// and it's the beat the demo is built around.
			saveRefused = true;
			flashSave('NOT ALLOWED', 2600);
			return;
		}
		const r = await saveAdjust();
		if (!r.ok) {
			flashSave('ERROR', 1600);
			console.error('[adjust save] failed:', r.error);
		} else if (r.patched === 0 && r.unmatched.length === 0) {
			flashSave('NONE', 1600);
		} else if (r.unmatched.length) {
			// A PARTIAL save is the dangerous outcome: some tags landed, some didn't,
			// and the author has no reason to suspect it. Saying "SAVED" here (which is
			// what this used to do, with the detail buried in a console.warn) means a
			// drag you made is quietly gone the next time the file reloads. Held long,
			// like the refusal, because there is a tooltip to read — and it names the
			// count, so "1 of 2" is legible without opening devtools.
			saveRefused = true;
			savePartial = r.unmatched.length;
			saveReasons = [...new Set(r.unmatched.map((u) => u.reason))];
			flashSave(`${r.patched} OF ${r.patched + r.unmatched.length}`, 2600);
			console.warn('[adjust save] not written — Copy these by hand:', r.unmatched);
		} else {
			flashSave('SAVED', 1600);
		}
	}
	// Open (or focus) the presenter console at the current slide — the PRESENT anchor's
	// click. It only ENSURES the console is running: opening it, or re-focusing the window
	// already named for this deck. Runs in the click handler (a user gesture) so the popup
	// isn't blocked.
	function openPresenter() {
		openPresenterWindow(window.location.href, deckKeyFromPath(window.location.pathname));
	}
	// Page-level document title, same cascade idea as the favicon above but emitted
	// as ONE <title> (the browser uses the FIRST <title>, so it can't stack the way
	// the favicon links do): the current slide's own `title` from pages.ts, composed
	// with this deck's `title` prop into "Slide — Deck". See documentTitle.
	$: currentTitle   = pages.find((p) => p.path === currentSlide)?.title;
	$: docTitle       = documentTitle(currentTitle, title);
	// SEO description/image cascade: the current slide's own pages.ts value, else
	// the deck-level default. Emitted (with title/canonical/og/twitter) by <Seo>.
	$: currentDescription = pages.find((p) => p.path === currentSlide)?.description ?? description;
	$: currentImage       = pages.find((p) => p.path === currentSlide)?.image ?? image;
	$: currentImageAlt    = pages.find((p) => p.path === currentSlide)?.imageAlt ?? imageAlt;

	// Recompute the minimap's "you are here" rectangle from the live scroll position.
	// Only meaningful in SCALED when the scaled slide overflows the viewport (else
	// there is nothing to pan, so the map is hidden).
	function updateMap() {
		if (!viewport || !container || mode !== 'SCALED' || clean) { mapVisible = false; return; }
		const vw = viewport.clientWidth,  vh = viewport.clientHeight;
		const sw = container.offsetWidth,  sh = container.offsetHeight;
		mapVisible = sw > vw + 1 || sh > vh + 1;
		if (!mapVisible) return;
		mapRect = {
			left:   clamp01(viewport.scrollLeft / sw),
			top:    clamp01(viewport.scrollTop  / sh),
			width:  clamp01(vw / sw),
			height: clamp01(vh / sh),
		};
	}

	// Park the scroll so the slide starts centred when it overflows (zoom-in). Pairs
	// with `safe center` on .viewport, which otherwise start-aligns an overflowing
	// child (top-left) — reachable, but jarring as an entry point.
	function centerScroll() {
		if (!viewport || !container) return;
		viewport.scrollLeft = Math.max(0, (container.offsetWidth  - viewport.clientWidth)  / 2);
		viewport.scrollTop  = Math.max(0, (container.offsetHeight - viewport.clientHeight) / 2);
	}

	function adjustSize(recenter = false) {
		if (!container) return;
		// Presenter mode hides the canvas and never scales it — a scale transform on
		// .content would also make the fixed <Note> panel a transformed containing
		// block (fixed would then track .content, not the viewport). So: no transform.
		if (present) return;
		// `?shot` is a SCREENSHOT render: the canvas at exactly 1:1, filling the viewport,
		// with no frame, no chrome and no letterbox — so a headless browser sized to the
		// canvas produces a pixel-exact PNG with no cropping. FITTED would scale it by
		// ~0.997 to fit the frame's own border, which is precisely what we don't want here.
		if (shot) return;

		if (mode === 'SCALED') {
			// Exact factor: the frame is the canvas at `factor`, the content scales by
			// the same factor from its top-left so the two stay flush. The .viewport
			// scrolls/pans when this overflows the window.
			container.style.width  = `${Math.round(width  * factor)}px`;
			container.style.height = `${Math.round(height * factor)}px`;
			content.style.transform = `scale(${factor})`;
			content.style.transformOrigin = 'top left';
			viewScale = factor;
			// Expose the fit factor to canvas-space chrome (the ADJUST/SAVE row) so it
			// can counter-scale its screen inset to match the screen-fixed MODE control.
			content.style.setProperty('--view-scale', String(factor));
			if (recenter) centerScroll();
			updateOverlay();
			return;
		}

		// FITTED — fit the canvas to the window by aspect. Size the cross axis from the
		// INNER box (client*, excludes the 1.5px border), NOT the border-box (offset*):
		// the scale below divides by client*, so using offset* would leave the inner
		// box ~(3px * aspect) larger than the scaled content — a thin black gap between
		// the content and the frame on the non-binding axis. client* makes the inner
		// box a true `aspect` rectangle, so the content fills it flush on both axes.
		const windowRatio = window.innerWidth / window.innerHeight;
		if (windowRatio > aspectRatio) {
			container.style.height = 'calc(100vh - 10px)';
			container.style.width  = `${Math.round(container.clientHeight * aspectRatio)}px`;
		} else {
			container.style.width  = 'calc(100vw - 10px)';
			container.style.height = `${Math.round(container.clientWidth / aspectRatio)}px`;
		}
		// Exact fit: scale the content's TRUE border-box down to the container's INNER
		// box by whichever axis binds. Math.min guarantees no overflow on either axis,
		// so the frame border stays visible all around and content sits inside. The box
		// is the full canvas in fill mode; otherwise it carries the legacy slack (width
		// +20 + 2x15 padding = width + 50; height nets back to the canvas height).
		const boxW = fill ? width : width + 50;
		const boxH = height;
		const scale = Math.min(container.clientWidth / boxW, container.clientHeight / boxH);
		content.style.transform = `scale(${scale})`;
		content.style.transformOrigin = 'center center';
		viewScale = scale;
		content.style.setProperty('--view-scale', String(scale));
		updateOverlay();
	}

	// Wrap a re-layout in the body.rendering class (suppresses paint of half-applied
	// styles); recenter only on a mode/factor change, never on a resize mid-pan.
	function apply(recenter: boolean) {
		document.body.classList.add('rendering');
		adjustSize(recenter);
		document.body.classList.remove('rendering');
	}

	onMount(() => {
		if (!browser) return;
		const unsubMode   = displayMode.subscribe(v   => { mode = v;                  if (initialized) apply(true); });
		const unsubFactor = displayFactor.subscribe(v => { factor = clampFactor(v);   if (initialized) apply(true); });
		const onResize = () => adjustSize(false);
		window.addEventListener('resize', onResize);

		// Kiosk boot once per page load: ?kiosk starts, ?kiosk=off stops, else resume
		// a session mid-loop after a full-page nav.
		bootKioskFromUrl(new URL(window.location.href));

		// The PRINT menu's "this slide + notes" grows the paper only for the print; once the
		// dialog closes, the deck goes back to its screen self. `afterprint` fires whether the
		// user printed or cancelled.
		const onAfterPrint = () => { printNotesOverride = false; };
		window.addEventListener('afterprint', onAfterPrint);

		// Follow the OTHER window: when it announces a different slide, page there.
		// Guard on `path !== currentSlide` (our own echo / already-here) so the
		// two-window ping-pong converges. Route through the shared navigate() so a
		// followed hop animates like a clicked one; keep the console's ?present flag.
		// Skipped in an iframe preview (window.top !== self) — see isTopWindow above.
		//
		// `relayRole` is the SECOND gate, and the one that makes this a relationship
		// rather than a broadcast: subscribeCurrentSlide drops any announcement from a
		// window of our own role, so a console follows the audience and the audience
		// follows a console, but two audience tabs (or two consoles) never move each
		// other. A window's role is fixed for its lifetime — ?present can't change
		// without a reload — so capturing it here rather than re-reading per event is
		// exact, not an approximation.
		const stopFollow = (window.self === window.top)
			? subscribeCurrentSlide(deckKey, (path) => {
				if (!path || path === currentSlide) return;
				const target = present ? `./${path}?present` : `./${path}`;
				const targetIndex = pages.findIndex((p) => p.path === path);
				const direction = targetIndex >= 0 && targetIndex < (currentIndex ?? 0) ? 'back' : 'forward';
				const leaving = pages.find((p) => p.path === currentSlide);
				const kind = (direction === 'back' ? leaving?.transitionBack : leaving?.transition) ?? 'slide';
				navigate(target, { viewTransitions, kind, direction });
			}, relayRole)
			: () => {};

		// Apply relayed ANIMATE commands from the presenter console onto this window's
		// live slide animations. Top window only (an iframe preview must not react).
		const stopAnim = (window.self === window.top)
			? subscribeAnimCommand(deckKey, (cmd) => {
				const root = document.querySelector('.content');
				if (!root) return;
				const anims = collectFinite(root);
				if (anims.length) applyState(anims, cmd);
			})
			: () => {};

		// A relayed CONTINUE pulse from the console becomes a `gp:continue` DOM event;
		// NavigationBar routes it to the slide's onContinue hook. Top window only.
		const stopContinue = (window.self === window.top)
			? subscribeContinue(deckKey, () => window.dispatchEvent(new CustomEvent('gp:continue')))
			: () => {};

		// A relayed HIGHLIGHT from the console lights the named Block on this slide
		// (see Spotlight / stores/highlightTarget). Top window only — an iframe preview
		// must not react, exactly like the anim/continue relays above. `setHighlight`
		// clears the store on `null`, so leaving a note line turns the spotlight off.
		const stopHighlight = (window.self === window.top)
			? subscribeHighlight(deckKey, (name) => setHighlight(name))
			: () => {};

		// A relayed TRIGGER pulse from a checked <Note data-trigger> line fires the
		// named local pulse (see stores/triggers) — a <Cursor startOn="name">, today,
		// reacts. Top window only, same guard as the relays above.
		const stopTrigger = (window.self === window.top)
			? subscribeTrigger(deckKey, (name) => fireTrigger(name))
			: () => {};

		// Console presence. In the ?present window this is the CONSOLE, so heartbeat —
		// stamp the shared key now (so an already-open audience flips at once) and keep
		// re-stamping on an interval while we live. In an audience window (top only — an
		// iframe preview must not react, like the relays above) TRACK that beat: seed
		// from the last stored beat, follow new ones, and re-judge staleness on a timer,
		// because a console that CLOSED sends no farewell — only the clock reveals it
		// gone. The verdict lands in `consoleLive`, which <Note> reads to drop its now-
		// redundant below-slide note.
		let stopConsole = () => {};
		if (present) {
			publishConsoleAlive(deckKey);
			const beat = window.setInterval(() => publishConsoleAlive(deckKey), CONSOLE_BEAT_MS);
			stopConsole = () => window.clearInterval(beat);
		} else if (window.self === window.top) {
			let lastBeat = loadConsoleBeat(deckKey);
			const refresh = () => consoleLive.set(consoleIsLive(lastBeat, Date.now(), CONSOLE_TTL_MS));
			refresh();
			const stopBeat = subscribeConsoleAlive(deckKey, (ts) => { lastBeat = ts; refresh(); });
			const poll = window.setInterval(refresh, CONSOLE_BEAT_MS);
			stopConsole = () => { stopBeat(); window.clearInterval(poll); consoleLive.set(false); };
		}

		// NOTE: no ink subscription here. Ink rides a persisted(sync: true) store, so the
		// `storage` event mirrors it between the two deck windows with nothing to wire up —
		// and because it is keyed BY SLIDE, the console's next-slide <iframe> preview shows
		// that slide's ink, which is right rather than a double-draw.

		initialized = true;
		apply(true);
		return () => {
			unsubMode();
			unsubFactor();
			stopFollow();
			stopAnim();
			stopContinue();
			stopHighlight();
			stopTrigger();
			stopConsole(); // stop the heartbeat / presence tracking; clears consoleLive
			setHighlight(null); // don't leave a stale spotlight across a deck swap
			// Ink is NOT cleared here — it is meant to survive. That is the whole point.
			window.removeEventListener('resize', onResize);
			window.removeEventListener('afterprint', onAfterPrint);
		};
	});
</script>

<!-- Seo owns the <title> + SEO/social tags; the favicon link stays here (its
     last-one-wins cascade is separate from the single <title> Seo emits). -->
<Seo
	title={docTitle}
	description={currentDescription}
	image={currentImage}
	imageAlt={currentImageAlt}
	type="website"
/>

<svelte:head>
	{#if currentFavicon}
		<link rel="icon" href={currentFavicon} />
	{/if}
</svelte:head>

<!-- Chrome arm (Alt+.) + mnemonics; PRINT flyout keys when that menu is open. -->
<svelte:window on:keydown={onChromeKeys} />

<!-- .viewport is the screen-fixed pan area. It centres the frame when it fits and
     scrolls (top-left reachable, via `safe center`) when SCALED overflows it. -->
<div class="viewport" class:zoom={!isFitted} class:shot bind:this={viewport} on:scroll={updateOverlay}>
	<div
		class="container {deckClass}"
		class:fit-mode={isFitted}
		class:zoom-mode={!isFitted}
		class:clean={clean}
		class:present={present}
		class:shot
		class:fade-chrome={fadeChrome}
		class:print-notes={wantsNotes}
		style="--canvas-w:{width}px; --canvas-h:{height}px; --aspect:{aspectRatio}; --base-font:{baseFontSize}; --print-scale:{printMetrics.scale}; --print-w:{printMetrics.slideWidthPx}px; --print-h:{printMetrics.slideHeightPx}px; --print-notes-h:{printMetrics.notesHeightPx}px;{contentBackground ? ` --content-bg:${contentBackground};` : ''}{contentFont ? ` --content-font:${contentFont};` : ''}"
		bind:this={container}
	>
		<div class="content" class:fill class:ready={initialized} bind:this={content}>
			{#if initialized}
			<slot />
			<!-- Note-driven spotlight: a canvas-level singleton (like the minimap),
			     inert until a <Note> line or a slide sets the highlightTarget store.
			     Placed after the slot so it paints over the slide's own blocks. -->
			<Spotlight canvasWidth={width} canvasHeight={height} />
			<!-- The speaker's ink, the other canvas-level singleton. After Spotlight, so a
			     stroke lands on top of the cue it is drawn next to. Renders nothing at all
			     until there is ink or the pen is armed — so it is inert (and SSR-inert) on
			     every deck that never offers it. -->
				<Annotate canvasWidth={width} canvasHeight={height} {inkColors} {levelHighlight} />
			<!-- The all-slides grid (press O). Canvas-space, like the ToC — its tiles are
			     live `?clean` iframes of the real slides.

			     Gated in MARKUP rather than hidden in CSS (which is how ?clean retires the
			     other chrome): a tile must not build a slide list or arm a global `o`
			     listener, and there are a dozen tiles alive at once. Not rendering it is
			     also what stops a tile from growing a grid of its own, recursively.

			     AUDIENCE window only (`!present`) — the presenter console gets its OWN
			     mount, outside `.viewport`, alongside <PresenterView> below. It cannot
			     live here for the console: `.viewport` is `position:fixed`, which always
			     opens a stacking context, so no z-index in here could ever outrank
			     PresenterView's bar (a later sibling of `.viewport`, not a descendant). -->
			{#if !clean && !present}
				<OverviewPage
					{pages}
					{width}
					{height}
					currentPath={currentSlide ?? ''}
					deck={deckName}
				/>
			{/if}
			<!-- Deck-level SOURCE panel for slides without ViewSource. MUST live in
			     canvas space (this .content layer), not the window overlay: <Box>
			     is position:absolute at 50%/50% of its containing block — the same
			     placement ViewSource uses. In the overlay it anchored to the window
			     and the 9999px dimming shadow painted half the screen wrong. -->
			{#if browser && $deckSourceFallback && !$pageSourceHasOwner}
				<CodeBox
					code={$deckSourceFallback.code}
					language="html"
					title={$deckSourceFallback.path}
					bind:expanded={deckSourceExpanded}
					readOnly
					edit
					on:edit={() => openPageSourceEdit()}
					class="gp-chrome no-print"
				/>
			{/if}
			<Copyright />
			{/if}
		</div>
	</div>
</div>

<!-- Viewport-fixed chrome that sticks to the WINDOW regardless of pan/zoom. <SlideToolbar> is
     the top-centre PRESENT | ANNOTATE | ADJUST | DISPLAY | ☰ bar (it holds the DISPLAY zoom
     control that used to pin to the top-right corner); the ControlBar is the bottom nav
     mirror. Both are lifted OUT of the scaled slide so they stay put and constant-size. The
     overlay is z-index 50 — above the ink surface (40) — so an armed pen can never bury the
     ANNOTATE toggle. Hidden by ?clean and in the presenter console (which has its own chrome).
     Each bar is also opt-out via `toolBar` / `controlBar` props (default on). -->
{#if initialized && !clean && !present && (toolBar || controlBar)}
<div class="overlay" class:fade-chrome={fadeChrome} style="--base-font:{baseFontSize};" bind:this={chromeOverlay}>
	{#if toolBar}
	<SlideToolbar {width} {height}>

		<!-- KIOSK — empty when the deck does not offer it (zero footprint). Opens the
		     pace dialog; Start / ?kiosk arms the runner. -->
		{#snippet kioskItem()}
			{#if $canKiosk}
				<button
					type="button"
					class="annot-tool"
					title="Kiosk — auto-advance this deck (step, then page, then loop)"
					on:click={() => {
						openKioskDialog();
						if (browser && document.activeElement instanceof HTMLElement) {
							document.activeElement.blur();
						}
					}}
				>
					<span class="tool-ico" aria-hidden="true">
						<!-- play-in-circle -->
						<svg viewBox="0 0 16 16" width="1em" height="1em" fill="none" stroke="currentColor" stroke-width="1.4">
							<circle cx="8" cy="8" r="6" />
							<path d="M6.5 5.5v5l4.5-2.5z" fill="currentColor" stroke="none" />
						</svg>
					</span>
					<span class="tool-label"><span class="tool-mn">K</span>IOSK</span>
				</button>
			{/if}
		{/snippet}

		<!-- PRESENT — the anchor. Ensures the presenter console is running (opens it, or
		     re-focuses the existing one); it is not a mode, so it carries no on/off state.
		     Hidden with the whole overlay inside the console itself (the overlay is gated
		     `!present`). -->
		{#snippet presentBtn()}
			<button
				type="button"
				class="annot-anchor"
				title="PRESENT — open speaker console"
				on:click={openPresenter}
			><span class="tool-mn">P</span>RESENT</button>
		{/snippet}

		<!-- ADJUST — the old ADJUST toggle, moved into the menu and renamed. A sub-toggle
		     that reads ADJUST:off / ADJUST:on in place (pinned width, so the label swap does
		     not resize it), and only when the slide OFFERS layout ($canAdjust). SAVE appears
		     beside it while ADJUST is on. The snippet also carries the divider that precedes
		     the pair, so a deck that doesn't offer ADJUST leaves no dangling separator. -->
		{#snippet adjustGroup()}
			{#if $canAdjust}
				<span class="annot-bar-sep" aria-hidden="true"></span>
				<button
					type="button"
					class="annot-tab adjust-tab"
					class:on={$adjustMode}
					aria-pressed={$adjustMode}
					aria-label={$adjustMode ? 'ADJUST on' : 'ADJUST off'}
					title={$adjustMode
						? 'ADJUST — placing blocks by hand (click to stop)'
						: 'ADJUST — drag and resize blocks at exact pixels'}
					on:click={() => adjustMode.update((v) => !v)}
				>AD<span class="tool-mn">J</span>UST</button>
				<!-- Save writes moved Blocks back to source via the vite-dev endpoint. Shown
				     whenever ADJUST is on, and it fires in BOTH worlds — it isn't greyed out
				     where it can't write. It answers on click instead: the verdict flashes as a
				     badge (SAVED / NONE / 1 OF 2 / NOT ALLOWED) and, on a refusal, a tooltip says
				     why. A control disabled from the start invites the audience to assume the
				     feature is missing; one that refuses when pressed teaches that saving is
				     *forbidden here*. -->
				{#if $adjustMode}
					<span class="save-btn" class:refused={saveRefused}>
						<button
							type="button"
							class="annot-act save-act"
							aria-label="Save layout to source"
							title="SAVE — write the moved blocks back to the source file"
							on:click={onSave}
						>SAVE</button>
						{#if saveLabel !== 'SAVE' || saveRefused}
							<!-- The verdict badge, and (on a refusal) the reason under it. aria-live on
							     the tip so the refusal is announced, not just drawn. One interpolation,
							     not a run of them: text split across lines carries the SOURCE's newlines
							     and indentation into textContent, so "1 tag" would read "1\n\t\t\ttag". -->
							<span class="save-pop">
								{#if saveLabel !== 'SAVE'}
									<span class="save-flash">{saveLabel}</span>
								{/if}
								{#if saveRefused}
									<span class="save-tip" role="status">{saveTip}</span>
								{/if}
							</span>
						{/if}
					</span>
				{/if}
			{/if}
		{/snippet}

		<!-- ☰ menu rows — plain `.annot-tool` buttons (SlideToolbar dresses them).
		     Group order: navigate → export → source. Each row is icon + mnemonic label
		     (+ shortcut / external cue); separators live in SlideToolbar between groups. -->
		{#snippet printBtn()}
			<!-- Nested flyout: hover (or click) opens a submenu to the LEFT of PRINT,
			     so it stays attached to the ☰ panel instead of a second floating menu. -->
			<div
				class="print-flyout"
				class:open={printMenuOpen}
				role="presentation"
				on:mouseenter={() => (printMenuOpen = true)}
				on:mouseleave={() => (printMenuOpen = false)}
			>
				<button
					type="button"
					class="annot-tool"
					aria-haspopup="menu"
					aria-expanded={printMenuOpen}
					title="Print current slide or whole deck (hover for options)"
					on:click|stopPropagation={() => (printMenuOpen = !printMenuOpen)}
				>
					<span class="tool-ico" aria-hidden="true">
						<svg viewBox="0 0 16 16" width="1em" height="1em" fill="none" stroke="currentColor" stroke-width="1.4">
							<path d="M4 6V2h8v4" />
							<path d="M4 11H2.5A1.5 1.5 0 0 1 1 9.5v-2A1.5 1.5 0 0 1 2.5 6h11A1.5 1.5 0 0 1 15 7.5v2A1.5 1.5 0 0 1 13.5 11H12" />
							<rect x="4" y="11" width="8" height="4" rx="0.5" />
						</svg>
					</span>
					<span class="tool-label">P<span class="tool-mn">R</span>INT</span>
					<span class="tool-trail" aria-hidden="true">▸</span>
				</button>
				{#if printMenuOpen}
					<div class="print-sub" role="menu" aria-label="Print options">
						<button type="button" role="menuitem" on:click={() => printThisSlide(false)}>
							<span class="print-sub-label">Current slide</span>
							<kbd class="print-sub-kbd">c</kbd>
						</button>
						<button type="button" role="menuitem" on:click={() => printThisSlide(true)}>
							<span class="print-sub-label">Current + notes</span>
							<kbd class="print-sub-kbd">C</kbd>
						</button>
						<div class="print-menu-sep" role="separator"></div>
						<button type="button" role="menuitem" on:click={() => openHandout('')}>
							<span class="print-sub-label">Whole deck</span>
							<kbd class="print-sub-kbd">w</kbd>
						</button>
						<button type="button" role="menuitem" on:click={() => openHandout('?notes')}>
							<span class="print-sub-label">Whole + notes</span>
							<kbd class="print-sub-kbd">W</kbd>
						</button>
						<div class="print-menu-sep" role="separator"></div>
						<button type="button" role="menuitem" on:click={() => openHandout('?grid')}>
							<span class="print-sub-label">Thumbnail grid</span>
							<kbd class="print-sub-kbd">t</kbd>
						</button>
						<button type="button" role="menuitem" on:click={() => openHandout('?grid&notes')}>
							<span class="print-sub-label">Notes grid</span>
							<kbd class="print-sub-kbd">T</kbd>
						</button>
					</div>
				{/if}
			</div>
		{/snippet}
		<!-- CAPTURE — empty when the deck does not offer it (zero footprint). -->
		{#snippet captureItem()}
			<span class="capture-btn" class:refused={!!captureTip}>
				{#if canCapture}
					<button
						type="button"
						class="annot-tool"
						disabled={capturing}
						title="Download this slide as a PNG at canvas resolution"
						on:click={onCapture}
					>
						<span class="tool-ico" aria-hidden="true">
							<!-- camera -->
							<svg viewBox="0 0 16 16" width="1em" height="1em" fill="none" stroke="currentColor" stroke-width="1.4">
								<path d="M2.5 5.5h2l1-1.5h5l1 1.5H13.5A1.5 1.5 0 0 1 15 7v5.5A1.5 1.5 0 0 1 13.5 14h-11A1.5 1.5 0 0 1 1 12.5V7A1.5 1.5 0 0 1 2.5 5.5z" />
								<circle cx="8" cy="9.5" r="2.2" />
							</svg>
						</span>
						<span class="tool-label">
							{#if captureLabel === 'CAPTURE'}
								<span class="tool-mn">C</span>APTURE
							{:else}
								{captureLabel}
							{/if}
						</span>
					</button>
					{#if captureTip}
						<span class="capture-tip" role="status">{captureTip}</span>
					{/if}
				{/if}
			</span>
		{/snippet}
		<!-- OVERVIEW — same grid as the O key. -->
		{#snippet overviewBtn()}
			<button
				type="button"
				class="annot-tool"
				title="All slides as a grid (O)"
				aria-keyshortcuts="o"
				on:click={() => {
					overviewOpen.set(true);
					// Drop focus so the ☰ :focus-within drop does not stick open over the grid.
					if (browser && document.activeElement instanceof HTMLElement) {
						document.activeElement.blur();
					}
				}}
			>
				<span class="tool-ico" aria-hidden="true">
					<!-- 2×2 grid -->
					<svg viewBox="0 0 16 16" width="1em" height="1em" fill="currentColor">
						<rect x="1.5" y="1.5" width="5.5" height="5.5" rx="0.8" />
						<rect x="9" y="1.5" width="5.5" height="5.5" rx="0.8" />
						<rect x="1.5" y="9" width="5.5" height="5.5" rx="0.8" />
						<rect x="9" y="9" width="5.5" height="5.5" rx="0.8" />
					</svg>
				</span>
				<span class="tool-label"><span class="tool-mn">O</span>VERVIEW</span>
			</button>
		{/snippet}
		<!-- SOURCE / EDIT — deck chrome in dev; ViewSource also offers them in builds. -->
		{#snippet sourceItem()}
			{#if $pageSourceCanView}
				<button
					type="button"
					class="annot-tool"
					title="View this slide's +page.svelte source"
					on:click={() => openPageSource()}
				>
					<span class="tool-ico" aria-hidden="true">
						<!-- code brackets -->
						<svg viewBox="0 0 16 16" width="1em" height="1em" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
							<path d="M5.5 3.5 2 8l3.5 4.5" />
							<path d="M10.5 3.5 14 8l-3.5 4.5" />
						</svg>
					</span>
					<span class="tool-label"><span class="tool-mn">S</span>OURCE</span>
				</button>
			{/if}
			{#if $pageSourceCanEdit}
				<button
					type="button"
					class="annot-tool"
					title="Edit source in a separate window (unscaled)"
					on:click={() => openPageSourceEdit()}
				>
					<span class="tool-ico" aria-hidden="true">
						<!-- pencil -->
						<svg viewBox="0 0 16 16" width="1em" height="1em" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round">
							<path d="M11.5 2.5 13.5 4.5 5.5 12.5H3.5v-2z" />
							<path d="M10 4l2 2" />
						</svg>
					</span>
					<span class="tool-label"><span class="tool-mn">E</span>DIT</span>
					<span class="tool-trail tool-ext" aria-hidden="true" title="Opens in a new window">
						<!-- external-link -->
						<svg viewBox="0 0 16 16" width="1em" height="1em" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
							<path d="M6.5 3.5H3.5v9h9v-3" />
							<path d="M9.5 3.5h3v3" />
							<path d="M12.5 3.5 7 9" />
						</svg>
					</span>
				</button>
			{/if}
		{/snippet}
	</SlideToolbar>
	{/if}

	<!-- ControlBar — the bottom-centre mirror of the tool bar, holding the navigation controls
	     lifted out of the scaled slide: the Table of Contents (its flyout opening upward), the
	     deck's ONE FIRST/PREV/CONTINUE/NEXT/LAST pager (fed the current slide's neighbours), and
	     — portaled in from the live slide's plain (deck-level) AnimationBar — the central ANIMATE
	     scrubber. The ControlBar publishes its own portal target (stores/localChrome.animBarSlot),
	     so nothing needs wiring here; a scoped/driven bar stays in the slide. Opt-out via
	     `controlBar={false}` on <SlideDeck>. -->
	{#if controlBar}
	<ControlBar>
		{#snippet tocItem()}
			<TableOfContent bar {pages} deck={deckName} {article} {articleText} {articleHref} />
		{/snippet}
		{#snippet navGroup()}
			<NavigationBar
				deckLevel
				firstLink={deckNavigation.first ?? ''}
				prevLink={deckNavigation.prev ?? ''}
				nextLink={deckNavigation.next ?? ''}
				lastLink={deckNavigation.last ?? ''}
			/>
		{/snippet}
	</ControlBar>
	{/if}

	{#if mapVisible}
	<SlideMap {width} {height} rect={mapRect} />
	{/if}
</div>
{/if}

<!-- Kiosk chrome: fixed window UI (not scaled with the canvas). Stays available even
     when toolBar/controlBar are off (a bare booth still needs Pause/Stop). Hidden under
     ?clean / ?present. -->
{#if initialized && browser && !clean && !present}
	<KioskDialog />
	<KioskIndicator />
	<KioskRunner
		{pages}
		currentSlide={currentSlide ?? ''}
		prefix="./"
		wpm={kioskWpm}
	/>
{/if}

<!-- Presenter console (this window loaded with ?present). Mounts OVER the hidden
     canvas; the current slide's own <Note> supplies the notes panel. -->
{#if initialized && present}
<PresenterView {pages} {width} {height} />
<!-- The all-slides grid, mounted for the CONSOLE specifically. A sibling of
     PresenterView (not the audience mount above, inside `.viewport`) is required:
     `.viewport` is `position:fixed`, which unconditionally opens its own stacking
     context, so no z-index inside it can ever outrank a LATER root-level sibling
     like PresenterView's bar — the grid rendered invisibly BEHIND the console's
     own chrome the one time this was tried nested in `.content`. Being a plain
     later sibling here, it also needs no `.container.present { visibility: hidden
     }` escape trick: it was never inside that hidden subtree.

     Opening/browsing it never reaches the audience — `overviewOpen` is a fresh
     module instance in THIS window, no cross-window relay exists for it. Only a
     tile CLICK does anything cross-window, by navigating this window (keeping
     `?present`, see OverviewPage's `jump()`), which the audience follows the same
     way PREV/NEXT/TOC already do (SlideDeck's publishCurrentSlide relay). -->
<OverviewPage
	{pages}
	{width}
	{height}
	currentPath={currentSlide ?? ''}
	deck={deckName}
	{present}
/>
{/if}

<style>
	.viewport {
		position: fixed;
		inset: 0;
		/* FITTED never scrolls (the frame always fits); hidden also clips any phantom
		   sub-pixel overflow from the scaled content. SCALED opts into scroll/pan. */
		overflow: hidden;
		display: flex;
		/* `safe` keeps the start edge reachable when the slide overflows (SCALED
		   zoom-in) while still centring it when it fits. */
		justify-content: safe center;
		align-items: safe center;
	}
	.viewport.zoom {
		overflow: auto;
	}
	.container {
		width: var(--canvas-w);
		height: var(--canvas-h);
		/* Hold the JS-set size in the flex viewport (no shrink/grow). */
		flex: none;
		display: flex;
		flex-direction: column;
		background: var(--surface-bg, #181818);
		border: 1.5px solid var(--frame-border, #CCCCCC);
		position: relative;
	}
	.container.fit-mode {
		/* Fit the frame to the window by ASPECT, in pure CSS, so first paint is
		   already the right shape — before onMount/adjustSize() runs. adjustSize()
		   still sets equivalent px inline (and tracks resize); this just owns first
		   paint. Both axes are set EXPLICITLY (not width:auto + aspect-ratio) so the
		   inner content's min-width can't inflate the frame back to canvas width. */
		width:  min(calc(100vw - 10px), calc((100vh - 10px) * var(--aspect)));
		height: min(calc(100vh - 10px), calc((100vw - 10px) / var(--aspect)));
		/* Centre the content child so the exact-fit scale (adjustSize) letterboxes
		   symmetrically about the centre — paired with transformOrigin 'center'. */
		justify-content: center;
		align-items: center;
	}
	.content {
		/* Base font-size lever (see baseFontSize prop): every em-based size in the
		   reused components scales from here in one place. */
		font-size: var(--base-font);
		width: calc(var(--canvas-w) + 20px);
		height: calc(var(--canvas-h) - 30px);
		min-width: calc(var(--canvas-w) - 30px);
		min-height: calc(var(--canvas-h) - 30px);
		overflow: visible;
		padding: 15px;
		margin: 0px;
		display: flex;
		justify-content: center;
		align-items: center;
		color: var(--surface-fg, #C0F1FF);
		background: var(--content-bg, var(--surface-bg, #181818));
		font-family: var(--content-font, 'Noto Sans', 'Cormorant Garamond', serif);
	}
	/* Keep the content OUT OF ADJUST until JS has applied the scale transform (the
	   `ready` class flips on at onMount, right after the first adjustSize()). At its
	   native px size the unscaled box overflows the frame; display:none removes it
	   from layout entirely — adjustSize() only measures the CONTAINER, so this is
	   safe. The container stays visible (sized in CSS), so the gap shows an empty
	   frame, never an overflowing box. */
	.content:not(.ready) {
		display: none;
	}

	/* --- Chrome fade (opt-in via `fadeChrome`) ---------------------------------
	   Every deck control tags its own root `.gp-chrome`; the two hosts that can
	   contain one are .container (NAV, TOC) and .overlay (DISPLAY, minimap), so the rule
	   is written once against each. :global because those roots belong to sibling
	   components with their own scoped styles.

	   Opacity, never visibility/display: a ghosted control keeps its full hit area,
	   so the pointer can find it exactly where it always was. */
	.container.fade-chrome :global(.gp-chrome),
	.overlay.fade-chrome   :global(.gp-chrome) {
		opacity: 0.12;
		transition: opacity 160ms ease;
	}
	/* The overlay chrome (DISPLAY, minimap) rests much more OPAQUE than the on-slide
	   chrome: it lives in the viewport corner, out of the way of slide content, so it
	   can stay readable at a glance instead of hiding until pointed at. It still lifts
	   to full on hover/focus below (that rule outranks this one via :hover). Same
	   selector as the shared 0.12 rule above, placed after it, so source order wins. */
	.overlay.fade-chrome :global(.gp-chrome) {
		opacity: 0.75;
	}
	/* Lit on approach — and STAY lit while open (`.expanded`, the class TOC and
	   SizeMode already flip) or pinned (ADJUST mid-edit). :focus-within carries the
	   keyboard: tabbing to a control reveals it exactly as hovering does. */
	.container.fade-chrome :global(.gp-chrome:hover),
	.container.fade-chrome :global(.gp-chrome:focus-within),
	.container.fade-chrome :global(.gp-chrome.expanded),
	.container.fade-chrome :global(.gp-chrome.pinned),
	.overlay.fade-chrome   :global(.gp-chrome:hover),
	.overlay.fade-chrome   :global(.gp-chrome:focus-within),
	.overlay.fade-chrome   :global(.gp-chrome.expanded),
	.overlay.fade-chrome   :global(.gp-chrome.pinned) {
		opacity: 1;
	}
	/* No hover to reveal with (touch, pen): a ghosted control the reader cannot
	   summon is just a lost control. Show everything. */
	@media (hover: none) {
		.container.fade-chrome :global(.gp-chrome),
		.overlay.fade-chrome   :global(.gp-chrome) {
			opacity: 1;
		}
	}
	/* ── `?shot` — the build-time screenshot render ────────────────────────────────
	   The canvas at exactly 1:1, flush to the viewport's top-left, with no frame border
	   and no letterbox. Point a headless browser at it with a window the size of the
	   canvas and the VIEWPORT IS THE SLIDE — so the PNG needs no cropping and no
	   rescaling, and it is the browser's own rasteriser doing the drawing, which is why
	   this path captures iframes, video and Monaco that the in-app CAPTURE cannot.

	   It is the one mode that deliberately does NOT fit the slide to the window. Fitting
	   is what a human wants; a screenshot must not do it, or every PNG would be scaled by
	   whatever fraction the frame's own 1.5px border happens to cost. */
	.viewport.shot {
		display: block;
		overflow: hidden;
		padding: 0;
		margin: 0;
	}
	.container.shot {
		width: var(--canvas-w);
		height: var(--canvas-h);
		border: none;
		margin: 0;
		transform: none;
	}
	.container.shot :global(.content) {
		transform: none !important;
	}
	/* Strip exactly what the in-app CAPTURE strips — the same `.no-print` / `.gp-chrome`
	   markers, so the two capture paths agree on what a slide IS. If they disagreed, the
	   PNG you get from the button and the PNG you get from the build would differ, and
	   nobody would know which one was right. The ink surface wears neither, so annotations
	   land in both. */
	.container.shot :global(.no-print),
	.container.shot :global(.gp-chrome) {
		display: none !important;
	}

	/* SAVE sits beside the ADJUST icon on the bar; its wrapper is the positioning context for the
	   verdict badge that pops under it. inline-flex so the icon sits inline in the bar row. These
	   are SLOTTED into <SlideToolbar>'s bar, but this is still SlideDeck's scoped CSS — the elements
	   are compiled here, so the scope hash rides with them wherever the DOM puts them. */
	.save-btn {
		position: relative;
		display: inline-flex;
		align-items: center;
	}
	/* Pin CAPTURE's width so its label can swap (CAPTURE → SAVED / NOT ALLOWED) without nudging the
	   dropdown row. SAVE is an icon now, so it needs no such pin. */
	.capture-btn :global(button) {
		min-width: 4.6em;
	}
	/* A refusal has to READ from the back of a room, so the icon/label turns danger red — the same
	   token the demo slide's own prose uses, so chrome and slide are literally one colour. */
	.save-btn.refused :global(.save-act),
	.capture-btn.refused :global(button) {
		color: var(--ctrl-forbidden-fg, #E5484D);
		border-color: var(--ctrl-forbidden-fg, #E5484D);
	}

	/* SAVE's answer, popped under the icon: the verdict badge (SAVED / NONE / 1 OF 2 / NOT ALLOWED),
	   and — on a refusal — the reason below it. Absolute, so it never widens the bar; centred on the
	   icon; never eats the pointer. */
	.save-pop {
		position: absolute;
		top: calc(100% + 6px);
		left: 50%;
		transform: translateX(-50%);
		z-index: 10;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 4px;
		pointer-events: none;
	}
	.save-flash {
		white-space: nowrap;
		padding: 0.15em 0.6em;
		border-radius: 6px;
		font-size: 0.72em;
		font-weight: bold;
		background: var(--tooltip-bg, #000000);
		color: var(--annot-toggle-fg, #F0A33E);
		border: 1px solid var(--annot-bar-edge, rgba(255, 255, 255, 0.2));
	}
	.save-btn.refused .save-flash {
		color: var(--ctrl-forbidden-fg, #E5484D);
		border-color: var(--ctrl-forbidden-fg, #E5484D);
	}
	.save-tip {
		max-width: 22em;
		text-align: center;
		padding: 0.3em 0.7em;
		border-radius: 6px;
		font-size: 0.68em;
		font-weight: bold;
		background: var(--tooltip-bg, #000000);
		color: var(--tooltip-fg, #FFFFFF);
		border: 1px solid var(--ctrl-forbidden-fg, #E5484D);
	}

	/* CAPTURE keeps the old anchored tooltip — it's still a dropdown row, not a bar icon. */
	.capture-btn {
		position: relative;
	}
	.capture-tip {
		position: absolute;
		top: calc(100% + 8px);
		left: 50%;
		transform: translateX(-50%);
		z-index: 10;
		white-space: nowrap;
		pointer-events: none;
		padding: 0.3em 0.7em;
		border-radius: 6px;
		font-size: 0.72em;
		font-weight: bold;
		background: var(--tooltip-bg, #000000);
		color: var(--tooltip-fg, #FFFFFF);
		border: 1px solid var(--ctrl-forbidden-fg, #E5484D);
	}

	/* ── PRINT nested flyout (inside the ☰ dropdown) ───────────────────────────────
	   Sits to the LEFT of the PRINT row so it is a true submenu, not a second floating
	   panel stacked over the hamburger. Hover (or click) on the row keeps it open via
	   mouseenter/leave on `.print-flyout`. */

	.content.fill {
		/* Exact-fit: the box IS the full canvas (padding folded in via border-box),
		   so it fills the frame edge to edge on BOTH axes with no fudge. */
		box-sizing: border-box;
		width: var(--canvas-w);
		height: var(--canvas-h);
		min-width: var(--canvas-w);
		min-height: var(--canvas-h);
	}
	/* With a full-canvas fill box the chrome that normally hangs at bottom:-10 (in
	   the content's own unscaled coords) would spill past the bottom border. Nudge
	   it just inside, so it floats over the slide's bottom corners. */
	.content.fill :global(.nav),
	.content.fill :global(.copyright) {
		bottom: 20px;
	}

	/* Screen-fixed overlay for always-reachable chrome (display-mode control,
	   minimap). pointer-events:none lets clicks fall through to the slide; each
	   control re-enables them for itself. */
	.overlay {
		position: fixed;
		inset: 0;
		z-index: 50;
		pointer-events: none;
		font-size: var(--base-font);
	}
	.overlay > :global(*) {
		pointer-events: auto;
	}

	/* `?clean`: hide the in-canvas chrome so a capture shows only the slide. (The
	   overlay chrome is render-gated on !clean above.) The deck's 1.5px frame is
	   intentionally kept: it marks the canvas edge the capture is measured against. */
	.container.clean :global(.toc),
	.container.clean :global(.copyright),
	.container.clean :global(.nav),
	.container.clean :global(.anim-bar) {
		display: none;
	}

	/* `?present`: hide the whole slide canvas (frame, background, slide body, its
	   chrome) with visibility so it keeps ADJUST — the slide still mounts, so its
	   <Note> exists. The note then flips ITSELF back to visible + fixed as the
	   presenter panel (see Note.presenter). No transform is applied in present mode
	   (adjustSize early-returns), so that fixed note tracks the viewport. */
	.container.present {
		visibility: hidden;
	}

	/* ── PRINT: one slide, one page ──────────────────────────────────────────────────
	   Ctrl+P on a slide prints that slide, and it should print as a SLIDE — the whole
	   canvas, edge to edge, on paper its own shape. The @page rule in <svelte:head> gave
	   the paper that shape; this puts the slide on it.

	   Everything here is `!important` for one reason, and it is not carelessness:
	   adjustSize() writes the frame's width/height and the content's transform as INLINE
	   styles, because on screen they must track the window. A print stylesheet cannot
	   out-specify an inline style — it can only override it — so the deck's screen
	   geometry has to be retracted by name and replaced with the paper's.

	   The document itself has to be unwound too: `.viewport` is `position: fixed` (a
	   window is one screenful, so a fixed pane is right there and useless here), and
	   global.css centres `body` in a flex box for the same reason. On paper both must
	   simply flow, or the sheet comes out empty and the slide comes out somewhere else. */
	@media print {
		/* The document, unwound: on screen `.viewport` is `position: fixed` (a window is one
		   screenful) and global.css centres `body` in a flex box for the same reason. On paper
		   both must simply FLOW, and flow to exactly the height of the frame — because anything
		   taller than the page, by any amount, is not clipped: it becomes another SHEET.

		   Which is what `min-height: 100vh` did here, and it is worth recording. It was meant to
		   centre the slide vertically so that a browser overriding the page size would letterbox
		   evenly. But `vh` in print is the page box, and a body forced to a full page tall, inside
		   an html forced to a full page tall, with a frame centred inside THAT, comes out just over
		   one page — so it printed as three sheets, blank / slide / blank. Chrome's own
		   print-to-PDF happened to absorb it; other engines did not, which is exactly the kind of
		   thing that must not be trusted to one renderer.

		   So: no viewport units on paper. The frame is centred HORIZONTALLY with `margin: 0 auto`
		   (which cannot add height), and vertical position is left to the page. */
		:global(html),
		:global(body) {
			display: block !important;
			width: auto !important;
			height: auto !important;
			min-height: 0 !important;
			margin: 0 !important;
			padding: 0 !important;
			overflow: visible !important;
		}

		.viewport {
			position: static !important;
			overflow: visible !important;
			display: block !important;
			/* No height of its own: a print viewport is the page, and anything it adds beyond the
			   frame below becomes a SHEET. */
			height: auto !important;
			min-height: 0 !important;
		}

		/* The frame at its printed size: the canvas, scaled to the paper. `overflow: hidden`
		   crops the content box's own 50px bleed, exactly as the deck's viewport does.

		   The two alignment lines are the ones that are easy to miss, and they cost a whole
		   afternoon: on screen the frame CENTRES its content child (`.container.fit-mode`),
		   because FITTED scales from the centre and letterboxes symmetrically about it. Print
		   scales from the TOP-LEFT — so the centring has to go with it, or the canvas is laid
		   out at a negative offset, scaled from a corner that is off the page, and the slide
		   prints with its left edge sliced off. The two must always be changed together. */
		.container {
			/* The printed size in PIXELS, straight from handoutCore — not `canvas * scale`
			   recomputed in CSS. Rounding the scale and multiplying back put the canvas a tenth
			   of a pixel outside the paper, which is enough for a printer to call it an overflow
			   and shrink the whole sheet. One number, computed once, used by both. */
			width: var(--print-w) !important;
			height: calc(var(--print-h) + var(--print-notes-h, 0px)) !important;
			min-width: 0 !important;
			min-height: 0 !important;
			margin: 0 auto !important;
			flex: none !important;
			justify-content: flex-start !important;
			align-items: flex-start !important;
			overflow: hidden !important;
			border: none !important;
			box-shadow: none !important;
		}

		/* The canvas at 1:1, scaled from the top-left so it lands flush in the frame — the
		   same move SCALED display makes, with the factor taken from the paper rather than
		   from the window. `.ready` (the JS-applied opacity gate) is irrelevant on paper:
		   printing happens in a browser, so JS has long since run. */
		.container .content {
			/* `flex: none` so the frame — now shorter than the canvas — cannot shrink the slide
			   on its way to fitting it; the scale is what does the fitting. */
			flex: none !important;
			transform: scale(var(--print-scale)) !important;
			transform-origin: top left !important;

			/* A deck is light-on-dark, and a browser does not print background colours unless
			   it is told to ("Background graphics", off by default) — which would hand the
			   reader white paper with white text on it. Inherited, so the whole slide obeys. */
			-webkit-print-color-adjust: exact;
			print-color-adjust: exact;
		}

		/* The deck's own furniture is not the slide. `.no-print` and `.gp-chrome` are the
		   existing markers for exactly this (captureCore's CHROME_SELECTOR strips the same
		   two, for the same reason) — but a control whose own rule sets `display` outranks a
		   single-class marker, so they are retracted here by force rather than by hint. */
		:global(.no-print),
		:global(.gp-chrome) {
			display: none !important;
		}

		/* The screen-fixed chrome layer (DISPLAY control, minimap). It holds nothing that
		   prints, and a `position: fixed` box is meaningless on paper — where there is no
		   viewport for it to be fixed to. */
		.overlay {
			display: none !important;
		}

		/* The copyright watermark — and this one is worth reading, because it is a LANDMINE
		   and it will be stepped on again.

		   Chrome, when laying out for PRINT, measures an absolutely-positioned element inside
		   a `transform: scale()`d ancestor WITHOUT applying the transform. The copyright is
		   anchored to the canvas's right edge, so its unscaled left edge sits at 1674px; the
		   paper is 1280px; Chrome concludes the page overflows and SHRINKS THE WHOLE SHEET to
		   1280/1674 = 0.7645 to make it fit. Every slide in the deck then printed at
		   three-quarter size, with white margins, and nothing in the DOM looked wrong —
		   `scrollWidth` is 1280, and under `Emulation.setEmulatedMedia` the box measures
		   correctly. Only the PDF was wrong. (`overflow: clip` and `contain: paint` on the
		   frame do not help; the phantom overflow is computed before either applies.)

		   So the copyright does not print — which is also simply right, and what the deck
		   already does under `?clean`: the HANDOUT prints no watermark on its sheets either, so
		   a printed slide and that slide inside a handout now agree, to the pixel.

		   The rule for anything new: canvas-space chrome anchored with `right`/`bottom` is
		   fine on screen and poison on paper. Anchor from the left, or don't print it. */
		:global(.copyright) {
			display: none !important;
		}

		/* ── `?notes`: the slide, and its speaker note under it, on the one page ───────────
		   The frame above already grew by --print-notes-h; this fills the band.

		   The note lives INSIDE the slide component, and so inside the scaled canvas — and a
		   transformed element is the containing block for everything absolute within it, so
		   there is no lifting it out. It is therefore left where it is and allowed to paint
		   BELOW the canvas, into the band, exactly as the handout does it. It must stay
		   ABSOLUTE: `.content` is a flex ROW, and a note made `static` becomes a flex sibling of
		   the slide and sits BESIDE it, squeezing the slide to two-thirds of the page.

		   The frame turns white for the band (the slide's own dark surface is painted by
		   `.content`, which covers only the slide), and the note is stripped back from a beige
		   card with its own scrollbar — right for a window — to plain prose that grows to its
		   content, which is the only thing paper can do with it. */
		.container.print-notes {
			background: #fff !important;
		}
		.container.print-notes .content :global(.note) {
			display: block !important;
			position: absolute !important;
			top: calc(100% + 30px) !important;
			left: 0 !important;
			width: 100% !important;
			height: auto !important;
			max-height: none !important;
			min-height: 0 !important;
			overflow: visible !important;
			margin: 0 !important;
			padding: 0 !important;
			border: none !important;
			border-radius: 0 !important;
			background: transparent !important;
			color: #222 !important;
			font-size: 1em !important;
		}
	}
</style>
