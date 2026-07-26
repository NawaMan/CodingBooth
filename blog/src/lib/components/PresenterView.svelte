<!--
  PresenterView — the speaker console chrome, mounted by SlideDeck only in a
  window loaded with ?present. It sits OVER the (hidden) slide canvas and shows:

    - the current slide's speaker note as the left panel (from the slide's own
      <Note>, which detects presenter mode and pins itself there — not rendered here),
    - a right column with scaled <iframe> previews of the CURRENT and NEXT slides
      (via ?clean, the chrome-hidden capture mode) — always accurate, since every
      slide is a real prerendered document,
    - a bottom bar: PREV/NEXT (+ FIRST/LAST) nav, an OVERVIEW button (the all-slides
      grid, same component the audience deck offers), a TOC jump menu, an ANIMATE
      control that drives the audience window's animation, a clock and an
      elapsed-since-open timer.

  The audience window pages from its own NavigationBar; the console has no such bar
  (SlideDeck gates it under `!present`), so this component's keydown drives BOTH the
  console's menus and its paging (see presenterKeyCore): T / C / A toggle the TOC /
  reset-checks / reset-ink menus, Esc closes them, →/← page the deck, Space relays a
  CONTINUE pulse (advances a build, never pages), and Shift+Space walks back. Paging
  reuses the bottom bar's go()/doContinue(), so the audience follows exactly as a
  button click would — over the same localStorage nav / gp:continue channels.

  OVERVIEW is deliberately NOT one of those keydown-driven paging actions: it opens
  <OverviewPage> (mounted alongside this component by SlideDeck once `present` is
  also allowed through its gate), whose own `o` / Escape handling and `overviewOpen`
  store are local to THIS window — so browsing the grid never reaches the audience.
  Only picking a tile does, by navigating this window (keeping `?present`, see
  OverviewPage's `jump()`), which the audience follows the same way PREV/NEXT/TOC do.
-->
<script lang="ts">
	import CtrlBtn from './CtrlBtn.svelte';
	import PresenterAnim from './PresenterAnim.svelte';
	import { browser } from '$app/environment';
	import { page } from '$app/stores';
	import { onMount, onDestroy } from 'svelte';
	import { getViewTransitions } from '$lib/presentation';
	import { getPageNavigation } from '$lib/utils/navigate';
	import { navigate } from '$lib/utils/deckNav';
	import {
		deckKeyFromPath, publishAnimCommand, publishContinue,
		presenterTimerStart, resetPresenterTimer, loadPresenterPause, savePresenterPause,
		loadPresenterSplit, savePresenterSplit, clearSlideChecks, clearDeckChecks
	} from '$lib/stores/presenter';
	import { canAnnotate, strokes, resetSlideInk, resetAllInk } from '$lib/stores/annotation';
	import { presenterKeyIntent } from '$lib/chrome/presenterKeyCore';
	import { overviewOpen } from '$lib/stores/overviewOpen';
	import type { Page } from '$lib/utils/navigate';
	import type { AnimState } from '$lib/utils/slideAnim';
	import { base } from '$app/paths';
	import { searchDocs } from '$lib/utils/searchCore';
	import { deckSearchDocs } from '$lib/utils/searchIndex';
	import { stepTocSelection } from '$lib/chrome/presenterTocCore';

	/** This deck's slide list (for nav, the TOC, and the current/next lookup). */
	export let pages: Array<Page> = [];
	/** Canvas size, so the preview iframes render at native size then scale down. */
	export let width = 1920;
	export let height = 1080;

	const viewTransitions = getViewTransitions();

	// Robust current path: strip trailing slash(es) then take the last segment, so
	// it matches pages[].path (e.g. "intro.html") in dev and the flat-file build.
	$: currentPath = $page.url.pathname.replace(/\/+$/, '').split('/').pop() || '';
	$: currentIndex = pages.findIndex((p) => p.path === currentPath);
	$: currentPage = pages[currentIndex];
	$: nav = getPageNavigation(pages, currentPath, './');
	$: nextPage = currentIndex >= 0 ? pages[currentIndex + 1] : undefined;
	// Previews with ?clean (chrome hidden). Relative to the presenter document URL,
	// so they resolve to the sibling slides regardless of deck prefix.
	$: currentSrc = currentPage ? `./${currentPage.path}?clean` : '';
	$: nextSrc = nextPage ? `./${nextPage.path}?clean` : '';

	$: deckKey = browser ? deckKeyFromPath($page.url.pathname) : '/';
	// The deck's bare folder name (e.g. "slides") — SlideDeck derives it the same
	// way — used to key the same build-time search index the audience TOC reads.
	$: deckName = browser
		? ($page.url.pathname.replace(base, '').split('/').filter(Boolean)[0] ?? '')
		: '';

	function kindFor(direction: 'forward' | 'back'): string {
		return (direction === 'back' ? currentPage?.transitionBack : currentPage?.transition) ?? 'slide';
	}
	// Console nav keeps the ?present flag so paging stays in the console; the
	// audience window follows via the localStorage channel (SlideDeck).
	function go(href: string | undefined, direction: 'forward' | 'back') {
		if (!href) return;
		navigate(href + '?present', { viewTransitions, kind: kindFor(direction), direction });
	}
	function jump(path: string) {
		tocOpen = false;
		navigate(`./${path}?present`, { viewTransitions, kind: kindFor('forward'), direction: 'forward' });
	}
	// Relay an animation command to the audience window.
	function relayAnim(cmd: AnimState) {
		publishAnimCommand(deckKey, cmd);
	}
	// CONTINUE is an in-slide step, not a page move — pulse the audience window,
	// which fires its slide's onContinue (see SlideDeck / NavigationBar).
	function doContinue() {
		publishContinue(deckKey);
	}

	// Scale each native-size preview iframe to FIT its measured box by whichever axis
	// binds (min of the two ratios), so both previews stay fully visible in the split
	// column without scrolling — the same exact-fit math the deck's FITTED mode uses.
	let curW = 0, curH = 0;
	let nextW = 0, nextH = 0;
	$: curScale = curW > 0 && curH > 0 ? Math.min(curW / width, curH / height) : 0;
	$: nextScale = nextW > 0 && nextH > 0 ? Math.min(nextW / width, nextH / height) : 0;

	// TOC jump menu (opens upward from the bar).
	let tocOpen = false;
	let tocRef: HTMLElement;

	// TOC search + keyboard browsing — a search box plus ↑/↓/Enter, reusing the
	// pure search/selection cores (searchCore, presenterTocCore) rather than
	// re-deriving the logic; only the markup differs (this menu opens upward
	// from the bar and shows each slide's number, matching PresenterView's own
	// popover style).
	let tocQuery = '';
	let tocSelected = -1;
	let tocCursorQuery = '';
	interface TocRow {
		path: string;
		title: string;
		number?: number;
		snippet?: string;
	}
	// This menu already lists hidden appendices (unlike the audience TOC/
	// OVERVIEW, which filter them out) — search must find them too, numbered
	// exactly as the rows below already are (position in the raw `pages`).
	$: tocDocs = deckSearchDocs(deckName, pages);
	$: tocHits = searchDocs(tocDocs, tocQuery);
	$: tocSearching = tocQuery.trim().length > 0;
	$: tocRows = (
		tocSearching
			? tocHits.map((h) => ({ path: h.path, title: h.title, number: h.number, snippet: h.snippet }))
			: pages.map((p, i) => ({ path: p.path, title: p.title, number: i + 1 }))
	) as TocRow[];
	// The cursor starts on the current slide when browsing unfiltered, and
	// nowhere once a query narrows the list — so ↓ lands on the top hit.
	$: tocOrigin = tocSearching ? -1 : currentIndex;
	// Any edit to the query invalidates the cursor: the rows underneath it changed.
	$: if (tocQuery !== tocCursorQuery) {
		tocCursorQuery = tocQuery;
		tocSelected = -1;
	}
	// Closing the menu (Esc, T again, a click outside, or a jump) always clears
	// the search — the next open starts fresh, exactly like the audience TOC.
	$: if (!tocOpen) {
		tocQuery = '';
		tocSelected = -1;
	}
	function moveTocSelection(delta: number) {
		tocSelected = stepTocSelection(tocSelected < 0 ? tocOrigin : tocSelected, delta, tocRows.length);
	}
	// Enter follows the cursor; straight after typing (cursor unplaced) it takes
	// the top hit.
	function commitTocSelection() {
		const at = tocSelected < 0 && tocSearching ? 0 : tocSelected;
		const row = tocRows[at];
		if (row) jump(row.path);
	}
	// ↑/↓/Enter/Esc while the caret is in the search box: stopPropagation so the
	// window-level handler (onKeydown / presenterKeyIntent) never doubles up on
	// them — this box owns them outright once it has focus.
	function handleTocSearchKeydown(e: KeyboardEvent) {
		e.stopPropagation();
		if (e.key === 'Escape') {
			e.preventDefault();
			if (tocQuery) tocQuery = '';
			else tocOpen = false;
			return;
		}
		if (e.key === 'ArrowDown') { e.preventDefault(); moveTocSelection(1); return; }
		if (e.key === 'ArrowUp')   { e.preventDefault(); moveTocSelection(-1); return; }
		if (e.key === 'Enter')     { e.preventDefault(); commitTocSelection(); }
	}
	// Type-to-search: put the caret in the box the moment the menu opens.
	function focusTocInput(node: HTMLInputElement) {
		node.focus();
	}
	// Keep the keyboard cursor's row in view as ↑/↓ walk past the fold.
	function scrollTocRowIntoView(node: HTMLElement, active: boolean) {
		const reveal = (on: boolean) => {
			if (on && typeof node.scrollIntoView === 'function') node.scrollIntoView({ block: 'nearest' });
		};
		reveal(active);
		return { update: reveal };
	}

	// Note check-off reset menu.
	let checksOpen = false;
	let checksRef: HTMLElement;
	// Clear the current slide's ticks (localStorage), then uncheck the visible lines.
	function resetPageChecks() {
		checksOpen = false;
		clearSlideChecks(deckKey, currentPath);
		if (browser) window.dispatchEvent(new CustomEvent('gp:checks-clear'));
	}
	// Clear EVERY slide's ticks for this deck (start over), then uncheck the visible ones.
	function resetDeckChecks() {
		checksOpen = false;
		clearDeckChecks(deckKey);
		if (browser) window.dispatchEvent(new CustomEvent('gp:checks-clear'));
	}

	// Ink reset menu. The console has no canvas of its own, so it cannot draw — but it CAN
	// clear, and that is exactly the control a speaker wants here: they see stale marks on
	// the CURRENT preview and want them gone without hunting for the pen on the other screen.
	// Both windows follow, because the ink is a persisted(sync: true) store and localStorage
	// is the channel — no relay to keep in step.
	let inkOpen = false;
	let inkRef: HTMLElement;
	function resetSlideInkHere() {
		inkOpen = false;
		resetSlideInk();
	}
	function resetAllInkHere() {
		inkOpen = false;
		resetAllInk();
	}

	function onDocClick(e: MouseEvent) {
		if (tocRef && !tocRef.contains(e.target as Node)) tocOpen = false;
		if (checksRef && !checksRef.contains(e.target as Node)) checksOpen = false;
		if (inkRef && !inkRef.contains(e.target as Node)) inkOpen = false;
		if (timerRef && !timerRef.contains(e.target as Node)) timerMenuOpen = false;
	}
	// Console keyboard mnemonics: T / C / A toggle the TOC / reset-checks / reset-ink
	// menus a speaker would otherwise have to reach for the mouse to open, and Esc
	// closes whatever is open. The letters act on the SAME state the buttons do, and
	// only ever OPEN a menu — the destructive reset stays a deliberate second click.
	function closeMenus() {
		tocOpen = false;
		checksOpen = false;
		inkOpen = false;
		timerMenuOpen = false;
	}
	// OVERVIEW opens the all-slides grid (<OverviewPage>, mounted alongside this
	// component once SlideDeck's gate lets it through for `present`). Closing the
	// console's own popovers first is cosmetic only — the grid's z-index already
	// sits above them — but it keeps state tidy for when the grid closes again.
	function openOverview() {
		closeMenus();
		overviewOpen.set(true);
	}
	function onKeydown(e: KeyboardEvent) {
		switch (presenterKeyIntent(e, $canAnnotate, tocOpen)) {
			case 'close':
				closeMenus();
				break;
			case 'toc': {
				e.preventDefault();
				const open = !tocOpen; // toggle: the same key closes it again
				closeMenus();
				tocOpen = open;
				break;
			}
			case 'checks': {
				e.preventDefault();
				const open = !checksOpen;
				closeMenus();
				checksOpen = open;
				break;
			}
			case 'ink': {
				e.preventDefault();
				const open = !inkOpen;
				closeMenus();
				inkOpen = open;
				break;
			}
			// Paging from the console — the same go()/doContinue() the bottom-bar
			// buttons call, so the audience follows over the localStorage channel
			// exactly as a click would. →/← page; Space relays a CONTINUE pulse that
			// steps an armed build without paging; Shift+Space walks back.
			case 'next':
				e.preventDefault();
				go(nav.next, 'forward');
				break;
			case 'prev':
				e.preventDefault();
				go(nav.prev, 'back');
				break;
			case 'continue':
				e.preventDefault();
				doContinue();
				break;
			case 'tocUp':
				e.preventDefault();
				moveTocSelection(-1);
				break;
			case 'tocDown':
				e.preventDefault();
				moveTocSelection(1);
				break;
			case 'tocSelect':
				e.preventDefault();
				commitTocSelection();
				break;
		}
	}

	// Clock + elapsed timer (client-only; this component mounts only in browser).
	// timerStart = start epoch; timerPausedAt = frozen epoch while paused (null =
	// running). Both are durable (persisted per deck), so reloads/navigation resume
	// the same value AND the same paused/running state.
	let now = '';
	let elapsed = '00:00';
	let timerStart = 0;
	let timerPausedAt: number | null = null;
	let timer: ReturnType<typeof setInterval> | undefined;
	$: paused = timerPausedAt != null;

	function fmt(totalSec: number): string {
		const s = Math.max(0, Math.floor(totalSec));
		const hh = Math.floor(s / 3600);
		const mm = Math.floor((s % 3600) / 60);
		const ss = s % 60;
		const pad = (n: number) => String(n).padStart(2, '0');
		return hh > 0 ? `${hh}:${pad(mm)}:${pad(ss)}` : `${pad(mm)}:${pad(ss)}`;
	}
	// Elapsed reads from timerPausedAt when paused (frozen), else live wall clock.
	function elapsedSec() {
		const ref = timerPausedAt ?? Date.now();
		return (ref - timerStart) / 1000;
	}
	function tick() {
		now = new Date().toLocaleTimeString(); // wall clock keeps ticking even when paused
		elapsed = fmt(elapsedSec());
	}
	function togglePause() {
		const nowMs = Date.now();
		if (timerPausedAt == null) {
			timerPausedAt = nowMs; // pause: freeze here
		} else {
			timerStart += nowMs - timerPausedAt; // resume: shift start so elapsed is continuous
			resetPresenterTimer(deckKey, timerStart);
			timerPausedAt = null;
		}
		savePresenterPause(deckKey, timerPausedAt);
		tick();
	}
	// Timer set/reset popover (opens from the elapsed clock).
	let timerRef: HTMLElement;
	let timerMenuOpen = false;
	let timerInput = '';
	function toggleTimerMenu() {
		timerMenuOpen = !timerMenuOpen;
		if (timerMenuOpen) timerInput = elapsed; // prefill with the current value
	}
	// Parse "hh:mm:ss" / "mm:ss" / a bare number (minutes) into seconds; null if bad.
	function parseDuration(s: string): number | null {
		const parts = s.trim().split(':');
		if (parts.length < 1 || parts.length > 3) return null;
		const nums = parts.map((p) => Number(p));
		if (nums.some((n) => !Number.isFinite(n) || n < 0)) return null;
		if (nums.length === 1) return nums[0] * 60; // a bare number = minutes
		if (nums.length === 2) return nums[0] * 60 + nums[1]; // mm:ss
		return nums[0] * 3600 + nums[1] * 60 + nums[2]; // hh:mm:ss
	}
	function setTimer() {
		const secs = parseDuration(timerInput);
		if (secs == null) return;
		// Set the elapsed READING to `secs` by back-dating the start (relative to the
		// pause epoch if paused, so it stays frozen at the set value). Pause state kept.
		const ref = timerPausedAt ?? Date.now();
		timerStart = resetPresenterTimer(deckKey, ref - secs * 1000);
		tick();
		timerMenuOpen = false;
	}
	function resetTimer() {
		// Explicit reset moves the start to now AND clears any pause — reloads and
		// navigation otherwise resume from the persisted value/state.
		timerStart = resetPresenterTimer(deckKey);
		timerPausedAt = null;
		savePresenterPause(deckKey, null);
		tick();
		timerMenuOpen = false;
	}

	// Draggable divider between the previews and the notes panel. Sets the shared
	// --gp-split var (both sides read it) in px; a drag persists a 0..1 fraction so
	// it survives reloads/navigation.
	let splitter: HTMLElement;
	let draggingSplit = false;
	// autoSplit: no user preference yet, so the divider auto-fits the preview width.
	// A drag (or a persisted value) turns it off and pins an explicit position.
	let autoSplit = true;
	let splitReady = false;
	const clampPx = (px: number) => {
		const w = window.innerWidth || 1;
		return Math.max(0.2 * w, Math.min(0.8 * w, px));
	};
	function applySplitPx(px: number) {
		document.body.style.setProperty('--gp-split', `${Math.round(clampPx(px))}px`);
	}
	// Default divider: flush to the right edge of the (height-driven) preview boxes, so
	// the previews fill the left region with no empty gutter. Natural preview width =
	// box height x canvas aspect; the divider sits a half-gap past it.
	function fitSplitToPreviews() {
		if (!curH) return;
		const cs = getComputedStyle(document.body);
		const inset = parseFloat(cs.getPropertyValue('--gp-inset')) || 20;
		const gap = parseFloat(cs.getPropertyValue('--gp-gap')) || 16;
		applySplitPx(inset + curH * (width / height) + gap / 2);
	}
	// Re-fit when the preview height changes (window-height resize) while in auto mode.
	// Width-only resizes need no refit — the px position already equals the preview
	// width. splitReady gates until onMount has chosen auto vs. persisted.
	$: if (splitReady && autoSplit && curH) fitSplitToPreviews();

	function onSplitDown(e: PointerEvent) {
		draggingSplit = true;
		splitter.setPointerCapture(e.pointerId);
		e.preventDefault();
	}
	function onSplitMove(e: PointerEvent) {
		if (!draggingSplit) return;
		applySplitPx(e.clientX);
	}
	function onSplitUp(e: PointerEvent) {
		if (!draggingSplit) return;
		draggingSplit = false;
		autoSplit = false; // an explicit choice — stop auto-fitting
		splitter.releasePointerCapture?.(e.pointerId);
		savePresenterSplit(clampPx(e.clientX) / (window.innerWidth || 1));
	}

	onMount(() => {
		document.body.classList.add('gp-present');
		// Durable timer: resume from the persisted start AND pause state (survives
		// Ctrl+R + slide paging, which fully reloads the console).
		timerStart = presenterTimerStart(deckKey);
		timerPausedAt = loadPresenterPause(deckKey);
		tick();
		timer = setInterval(tick, 1000);
		// Divider: a persisted drag wins; otherwise auto-fit to the preview width
		// (the reactive above runs fitSplitToPreviews once curH is measured).
		const f = loadPresenterSplit();
		if (f != null) { autoSplit = false; applySplitPx(f * window.innerWidth); }
		splitReady = true;
		document.addEventListener('click', onDocClick);
		window.addEventListener('keydown', onKeydown);
	});
	onDestroy(() => {
		if (timer) clearInterval(timer);
		if (typeof document !== 'undefined') {
			document.body.classList.remove('gp-present');
			document.body.style.removeProperty('--gp-split');
			document.removeEventListener('click', onDocClick);
		}
		if (typeof window !== 'undefined') window.removeEventListener('keydown', onKeydown);
	});
</script>

<!-- Left column: CURRENT (top) + NEXT (bottom) previews. The notes panel (right)
     is the slide's own <Note>. -->
<div class="preview-col no-print">
	<div class="preview">
		<div class="preview-label">CURRENT</div>
		<div class="preview-box" style="aspect-ratio: {width} / {height};" bind:clientWidth={curW} bind:clientHeight={curH}>
			{#if currentSrc}
				<iframe
					class="preview-frame" title="Current slide" src={currentSrc} tabindex="-1"
					style="width:{width}px; height:{height}px; transform: translate(-50%, -50%) scale({curScale});"
				></iframe>
			{/if}
		</div>
	</div>
	<div class="preview">
		<div class="preview-label">NEXT ▸ {nextPage ? nextPage.title : '— end of deck —'}</div>
		<div class="preview-box" style="aspect-ratio: {width} / {height};" bind:clientWidth={nextW} bind:clientHeight={nextH}>
			{#if nextSrc}
				<iframe
					class="preview-frame" title="Next slide" src={nextSrc} tabindex="-1"
					style="width:{width}px; height:{height}px; transform: translate(-50%, -50%) scale({nextScale});"
				></iframe>
			{:else}
				<div class="preview-end">End of deck</div>
			{/if}
		</div>
	</div>
</div>

<!-- Draggable divider on the split line — resizes previews vs. notes (--gp-split). -->
<div
	class="splitter no-print"
	class:dragging={draggingSplit}
	role="separator"
	aria-orientation="vertical"
	aria-label="Resize previews and notes"
	title="Drag to resize"
	bind:this={splitter}
	on:pointerdown={onSplitDown}
	on:pointermove={onSplitMove}
	on:pointerup={onSplitUp}
></div>

<!-- Bottom bar: nav + OVERVIEW + ToC + ANIMATE on the left, meters on the right. -->
<div class="bar no-print">
	<div class="controls">
		<div class="tools">
		<span class="ov-btn" title="All slides — pick one without the audience seeing you browse (O)">
			<CtrlBtn text="OVERVIEW" mnemonic="O" isSelected={$overviewOpen} on:click={openOverview} />
		</span>
		<div class="toc" class:open={tocOpen} bind:this={tocRef} title="Table of contents (T)">
			<CtrlBtn text={tocOpen ? 'ToC ▾' : 'ToC ▴'} mnemonic="T" isSelected={tocOpen} on:click={() => (tocOpen = !tocOpen)} />
			{#if tocOpen}
			<div class="toc-menu">
				<input
					class="search"
					type="search"
					placeholder="Search slides…"
					aria-label="Search slides"
					bind:value={tocQuery}
					on:keydown={handleTocSearchKeydown}
					use:focusTocInput
				/>
				<div class="toc-scroll">
					{#if tocSearching && tocRows.length === 0}
					<p class="no-matches">No slides match "{tocQuery.trim()}".</p>
					{:else}
					<ol>
						{#each tocRows as row, i}
							<li>
								<button
									type="button"
									class:current={row.path === currentPath}
									class:selected={i === tocSelected}
									on:click={() => jump(row.path)}
									use:scrollTocRowIntoView={i === tocSelected}
								>
									<span class="n">{row.number ?? ''}</span>
									<span class="t">{row.title}</span>
									{#if row.snippet}<span class="snip">{row.snippet}</span>{/if}
								</button>
							</li>
						{/each}
					</ol>
					{/if}
				</div>
			</div>
			{/if}
		</div>

		<div class="toc checks" class:open={checksOpen} bind:this={checksRef} title="Reset checks (C)">
			<!-- hoverText mirrors text exactly so the label never changes width under the pointer
			     (CtrlBtn SWAPS the two on hover): this bar is a fixed row a speaker aims at without
			     looking. The C in "Checks" is the underlined mnemonic; the menu names both actions. -->
			<CtrlBtn
				text={checksOpen ? '☑ Checks ▾' : '☑ Checks ▴'}
				hoverText={checksOpen ? '☑ Checks ▾' : '☑ Checks ▴'}
				mnemonic="C"
				isSelected={checksOpen}
				on:click={() => (checksOpen = !checksOpen)}
			/>
			{#if checksOpen}
			<div class="toc-menu checks-menu">
				<button type="button" on:click={resetPageChecks}>Reset this page</button>
				<button type="button" on:click={resetDeckChecks}>Start over (whole deck)</button>
			</div>
			{/if}
		</div>

		<!-- Reset the speaker's ink. Shown only where the pen is offered, and it reports how
		     much ink is on the current slide so "reset" is never a shot in the dark. -->
		{#if $canAnnotate}
		<div class="toc checks" class:open={inkOpen} bind:this={inkRef} title="Reset annotations (A)">
			<!-- hoverText mirrors text exactly so the label never changes width under the pointer
			     (CtrlBtn SWAPS the two on hover), keeping this fixed control row steady. The A in
			     "Annotate" is the underlined mnemonic; the menu it opens names both actions in full. -->
			<CtrlBtn
				text={inkOpen ? '✎ Annotate ▾' : '✎ Annotate ▴'}
				hoverText={inkOpen ? '✎ Annotate ▾' : '✎ Annotate ▴'}
				mnemonic="A"
				isSelected={inkOpen}
				on:click={() => (inkOpen = !inkOpen)}
			/>
			{#if inkOpen}
			<div class="toc-menu checks-menu">
				<button type="button" on:click={resetSlideInkHere} disabled={$strokes.length === 0}>
					Reset this slide{$strokes.length ? ` (${$strokes.length})` : ''}
				</button>
				<button type="button" on:click={resetAllInkHere}>Reset ALL annotations</button>
			</div>
			{/if}
		</div>
		{/if}
		</div>
		<div class="nav">
			<CtrlBtn text="FIRST" on:click={() => go(nav.first, 'back')} isDisabled={!nav.first} />
			<CtrlBtn text="◀ PREV" on:click={() => go(nav.prev, 'back')} isDisabled={!nav.prev} />
			<CtrlBtn text="CONTINUE" on:click={doContinue} />
			<CtrlBtn text="NEXT ▶" on:click={() => go(nav.next, 'forward')} isDisabled={!nav.next} />
			<CtrlBtn text="LAST" on:click={() => go(nav.last, 'forward')} isDisabled={!nav.last} />
		</div>

		<PresenterAnim onCommand={relayAnim} />
	</div>

	<div class="meters">
		<div class="pos">
			{currentPage ? currentPage.title : ''}
			<span class="count">{currentIndex >= 0 ? currentIndex + 1 : '?'} / {pages.length}</span>
		</div>
		<div class="clocks">
			<span class="clock">🕑 {now}</span>
			<div class="timer" class:open={timerMenuOpen} bind:this={timerRef}>
				<button type="button" class="pause-btn" class:paused on:click={togglePause} title={paused ? 'Resume timer' : 'Pause timer'} aria-label={paused ? 'Resume timer' : 'Pause timer'}>
					{#if paused}
						<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8 5v14l11-7z" /></svg>
					{:else}
						<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z" /></svg>
					{/if}
				</button>
				<button type="button" class="elapsed" class:paused on:click={toggleTimerMenu} title="Set / reset timer">⏱ {elapsed}</button>
				{#if timerMenuOpen}
				<div class="timer-menu">
					<input
						type="text"
						inputmode="numeric"
						placeholder="mm:ss"
						aria-label="Set elapsed time"
						bind:value={timerInput}
						on:keydown={(e) => { if (e.key === 'Enter') setTimer(); }}
					/>
					<button type="button" class="tm-set" on:click={setTimer}>Set</button>
					<button type="button" class="tm-reset" on:click={resetTimer}>Reset</button>
				</div>
				{/if}
			</div>
		</div>
	</div>
</div>

<style>
	/* The presenter window background — the slide canvas itself is hidden by
	   SlideDeck (visibility:hidden), so this sits behind the panels + note.
	   These vars are the ONE layout contract shared with Note.svelte's
	   .note.presenter (it inherits them, being a descendant of <body>): the notes
	   panel, the previews, and the bar all measure from --gp-split so they tile
	   edge-to-edge with a consistent gap and never overlap. */
	:global(body.gp-present) {
		background: #101216;
		--gp-inset: 20px;   /* margin from the window edges */
		--gp-gap: 16px;     /* gap between the note panel and the preview column */
		--gp-bar-h: 130px;  /* bottom control bar height */
		--gp-split: 50vw;   /* vertical divider between note (left) and previews (right) */
	}

	.preview-col {
		position: fixed;
		top: var(--gp-inset, 20px);
		bottom: calc(var(--gp-bar-h, 130px) + var(--gp-inset, 20px));
		/* Previews on the LEFT: from the inset to a half-gap left of the split; the
		   notes panel starts a half-gap right of it, so the two butt with exactly
		   --gp-gap between them. */
		left: var(--gp-inset, 20px);
		right: calc(100vw - var(--gp-split, 50vw) + var(--gp-gap, 16px) / 2);
		display: flex;
		flex-direction: column;
		gap: var(--gp-gap, 16px);
		overflow: hidden;
		z-index: 60;
	}
	/* Two equal halves — each preview takes half the column height so both are
	   always fully visible (the iframe fits-to-box, so no scroll). */
	.preview {
		display: flex;
		flex-direction: column;
		gap: 6px;
		flex: 1 1 0;
		min-height: 0;
		/* Right-align the label + box so both sit against the split (butting the
		   notes panel), matching the box's align-self:flex-end. */
		align-items: flex-end;
	}
	.preview-label {
		flex: none;
		color: #9fb4c6;
		font-size: 1rem;
		font-weight: 700;
		letter-spacing: 0.02em;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.preview-box {
		position: relative;
		flex: 1;
		min-height: 0;
		/* Content-sized: height fills the half-column (flex:1), width follows the
		   slide aspect (inline aspect-ratio), right-aligned so the slide itself butts
		   the notes panel (now on the right) — no side letterbox. max-width guards a
		   very narrow column. */
		align-self: flex-end;
		width: auto;
		max-width: 100%;
		overflow: hidden;
		border: 1.5px solid #3a4450;
		border-radius: 8px;
		background: #000;
	}
	.preview-frame {
		position: absolute;
		top: 50%;
		left: 50%;
		border: 0;
		transform-origin: center center;
		pointer-events: none; /* a preview, not interactive */
	}

	/* Draggable divider centred on --gp-split, spanning the panel area (above the
	   bottom bar). A wide invisible hit strip with a thin visible line that brightens
	   on hover/drag. */
	.splitter {
		position: fixed;
		top: var(--gp-inset, 20px);
		bottom: calc(var(--gp-bar-h, 130px) + var(--gp-inset, 20px));
		left: var(--gp-split, 50vw);
		width: 14px;
		transform: translateX(-50%);
		cursor: col-resize;
		z-index: 65;
		touch-action: none; /* we own the horizontal drag */
		display: flex;
		justify-content: center;
	}
	.splitter::before {
		content: '';
		width: 2px;
		height: 100%;
		border-radius: 2px;
		background: #2b333d;
		transition: background 0.12s;
	}
	.splitter:hover::before,
	.splitter.dragging::before {
		background: #2980b9;
	}
	.preview-end {
		position: absolute;
		inset: 0;
		display: flex;
		align-items: center;
		justify-content: center;
		color: #6b7885;
		font-size: 1.2rem;
	}

	.bar {
		position: fixed;
		left: 0;
		right: 0;
		bottom: 0;
		height: var(--gp-bar-h, 130px);
		box-sizing: border-box;
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 24px;
		padding: 12px 28px;
		background: #181c22;
		border-top: 1.5px solid #2b333d;
		color: #e6eef5;
		z-index: 70;
	}
	.controls {
		display: flex;
		align-items: center;
		gap: 18px;
		flex-wrap: wrap;
		/* Take the leftover width and wrap the buttons INTERNALLY when the bar is
		   narrow, rather than squeezing the meters column (which then breaks the clock
		   onto two lines). min-width:0 lets it actually shrink below content width. */
		flex: 1 1 auto;
		min-width: 0;
	}
	.nav {
		display: flex;
		align-items: center;
		gap: 6px;
		font-size: 1.5rem; /* CtrlBtn is em-based; set the lever here */
	}
	/* OVERVIEW / ToC / Checks / Annotate — same gap as .nav, so the two button rows
	   read as one consistent bar instead of the top row looking looser. */
	.tools {
		display: flex;
		align-items: center;
		gap: 6px;
	}

	/* OVERVIEW — same sizing lever as .toc/.nav so the CtrlBtn matches theirs. */
	.ov-btn {
		font-size: 1.5rem;
	}

	/* TOC jump menu — button in the bar, list opens UPWARD. */
	.toc {
		position: relative;
		font-size: 1.5rem; /* size the CtrlBtn like the nav */
	}
	.toc-menu {
		position: absolute;
		bottom: calc(100% + 8px);
		left: 0;
		min-width: 22em;
		max-height: 60vh;
		display: flex;
		flex-direction: column;
		overflow: hidden;
		background: #eef1f4;
		color: #14181d;
		border: 1.5px solid #3a4450;
		border-radius: 6px;
		box-shadow: 0 -8px 24px rgba(0, 0, 0, 0.4);
		font-size: 0.62em; /* back down from the 1.5rem lever to a readable list */
	}
	/* Only the list scrolls — the search box (like the audience TOC's) stays
	   reachable however long the results run. */
	.toc-menu .toc-scroll {
		overflow-y: auto;
		min-height: 0;
	}
	.toc-menu ol {
		margin: 0;
		padding: 4px 0;
		list-style: none;
	}
	.toc-menu li button {
		display: flex;
		gap: 0.8em;
		width: 100%;
		padding: 0.3em 0.9em;
		border: 0;
		background: transparent;
		color: inherit;
		font: inherit;
		text-align: left;
		cursor: pointer;
	}
	.toc-menu li button:hover {
		background: #dbe2e8;
	}
	.toc-menu li button.current {
		background: #2980b9;
		color: #fff;
	}
	.toc-menu li button .n {
		flex: none;
		width: 1.8em;
		text-align: right;
		opacity: 0.6;
	}
	.toc-menu li button .t {
		flex: 1 1 auto;
		min-width: 0;
	}
	.toc-menu li button .snip {
		flex: none;
		max-width: 12em;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		opacity: 0.6;
	}
	/* The ↑/↓ keyboard cursor — an inset outline so it reads over both a plain
	   row and the current-slide tint, same trick the audience TOC uses. */
	.toc-menu li button.selected {
		outline: 2px solid #2980b9;
		outline-offset: -2px;
	}
	.toc-menu .search {
		display: block;
		width: 100%;
		box-sizing: border-box;
		margin: 4px;
		padding: 0.3em 0.5em;
		font: inherit;
		color: #14181d;
		background: #fff;
		border: 1.5px solid #b3bcc6;
		border-radius: 4px;
	}
	.toc-menu .no-matches {
		margin: 0.5em 0.9em;
		opacity: 0.7;
	}

	/* Checks reset menu — a short column of actions (reuses .toc-menu's popover). */
	.checks-menu {
		display: flex;
		flex-direction: column;
		padding: 4px;
		gap: 2px;
		min-width: 15em;
	}
	.checks-menu button {
		width: 100%;
		padding: 0.5em 0.8em;
		border: 0;
		background: transparent;
		color: inherit;
		font: inherit;
		text-align: left;
		cursor: pointer;
		border-radius: 4px;
	}
	.checks-menu button:hover {
		background: #dbe2e8;
	}

	.meters {
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		gap: 8px;
		/* Hold the meters' natural width — never shrink so the clock keeps one line. */
		flex: none;
	}
	.pos {
		font-size: 1.1rem;
		font-weight: 700;
		color: #cdd9e3;
		max-width: 40vw;
		text-align: right;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.pos .count {
		margin-left: 10px;
		color: #8a99a8;
		font-weight: 500;
	}
	.clocks {
		display: flex;
		align-items: center;
		gap: 16px;
		font-variant-numeric: tabular-nums;
		/* Keep the wall clock and the timer on one row — never wrap the pair. */
		flex-wrap: nowrap;
		white-space: nowrap;
	}
	.clock {
		font-size: 1.5rem;
		color: #eaf2f9;
		/* Keep the whole "🕑 10:30:45 AM" together — no break before the AM/PM. */
		white-space: nowrap;
	}
	.timer {
		position: relative;
		display: inline-flex;
		align-items: center;
		gap: 8px;
	}
	.pause-btn {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 34px;
		height: 34px;
		padding: 0;
		cursor: pointer;
		color: #cdd9e3;
		background: #20262e;
		border: 1.5px solid #2b333d;
		border-radius: 6px;
	}
	.pause-btn:hover { color: #fff; background: #2980b9; }
	.pause-btn.paused { color: #f0b23e; border-color: #6b5326; }
	.pause-btn svg { display: block; width: 20px; height: 20px; fill: currentColor; }
	.elapsed {
		font: inherit;
		font-size: 1.5rem;
		cursor: pointer;
		color: #7ee0a8;
		background: transparent;
		border: 1.5px solid #2b333d;
		border-radius: 6px;
		padding: 2px 12px;
		white-space: nowrap; /* keep "⏱ 00:00" on one line */
	}
	.elapsed:hover,
	.timer.open .elapsed {
		border-color: #7ee0a8;
	}
	/* Paused: amber to signal the elapsed clock is frozen. */
	.elapsed.paused {
		color: #f0b23e;
	}
	/* Set/reset popover — opens upward from the elapsed clock. */
	.timer-menu {
		position: absolute;
		bottom: calc(100% + 8px);
		right: 0;
		display: flex;
		align-items: center;
		gap: 6px;
		padding: 8px;
		background: #eef1f4;
		border: 1.5px solid #3a4450;
		border-radius: 6px;
		box-shadow: 0 -8px 24px rgba(0, 0, 0, 0.4);
	}
	.timer-menu input {
		width: 5.5em;
		font: inherit;
		font-size: 1rem;
		padding: 3px 6px;
		border: 1px solid #b3bcc6;
		border-radius: 4px;
		color: #14181d;
		background: #fff;
	}
	.timer-menu button {
		font: inherit;
		font-size: 0.95rem;
		font-weight: 700;
		cursor: pointer;
		padding: 4px 12px;
		border-radius: 4px;
		border: 0;
	}
	.timer-menu .tm-set {
		background: #2980b9;
		color: #fff;
	}
	.timer-menu .tm-reset {
		background: #d7dee5;
		color: #14181d;
	}
	.timer-menu button:hover {
		filter: brightness(1.08);
	}
</style>
