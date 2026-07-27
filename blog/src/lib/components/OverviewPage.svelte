<!--
  OverviewPage — the all-slides grid. The "press O" move: see the whole deck at once,
  click a slide to jump there — or drive it purely from the keyboard: ←/→/↑/↓ move a
  roving focus between tiles, Home/End jump to the first/last, PageUp/PageDown move a
  screenful at a time, Space jumps focus to the CURRENT slide, and Enter is the only
  key that actually navigates. Every other key just moves which tile is FOCUSED — a
  local, this-window-only change (same guarantee the presenter console's grid already
  gives the mouse: browsing is invisible, a commit is not). The arrows are claimed at
  the grid itself (`on:keydown` + `stopPropagation`, in the bubble phase, from whichever
  tile is focused) — the same trick Tabs' roving strip uses to take them back from
  NavigationBar's `window`-level pager before it ever sees them, so a speaker can
  browse the WHOLE deck with the keyboard alone without paging the live slide away.

  A filter box in the head narrows the grid by title, file name, or page number
  (substring, case-insensitive — pure `filterOverviewTiles`). It does NOT autofocus
  on open: the grid keeps first claim on the arrows. Tab moves in/out of the box
  (from a tile → search, from search → the focused tile); Escape clears a query
  before it closes the overlay.

  Phase 1 also offers EDIT DECK (dev only): add a slide (scaffold + pages.ts) or
  unlist one. Static hosts show the control and refuse with NOT ALLOWED — same
  bargain as ADJUST SAVE. See specs/DECK-EDIT-1.md.

  The tiles are LIVE: each is the real prerendered slide in an <iframe> at `?clean`
  (chrome off), rendered at native canvas size and CSS-scaled to fit its box — the
  same mechanism the presenter console already uses for its CURRENT/NEXT previews.
  Deliberately not screenshots: the only capture path in the repo writes to a
  gitignored /static/og, no deck sets a per-slide `image:`, and a thumbnail goes
  stale the moment its slide is edited. A live tile costs a document; a captured
  one costs a build step, a fresh clone showing an empty grid, and a lie.

  Embedding a slide is safe because SlideDeck gates every cross-window relay
  behind `isTopWindow` — a tile follows nobody and publishes nothing.

  Mounting is LAZY and one-way: a tile shows a cheap title card until it scrolls
  near the viewport, then keeps its iframe. So opening a 65-slide deck boots the
  dozen documents you can see, not 65.

  Lives in CANVAS space (absolute over the 1920x1080 content layer, like the ToC)
  rather than being window-fixed: the deck's scale transform lives on .content, and
  a `position: fixed` child of a transformed element anchors to that element, not
  the window. Canvas space also means the grid inherits the deck's theme tokens.
-->
<script lang="ts">

	import { browser }   from '$app/environment';
	import { onMount, onDestroy, tick } from 'svelte';

	import { navigate } from '$lib/utils/deckNav';
	import { overviewOpen } from '$lib/stores/overviewOpen';
	import {
		canEditDeck,
		overviewEditMode,
		addPage,
		removePage
	} from '$lib/stores/pageEdit';
	import {
		slugifyStem,
		normalizeSlidePath,
		type PageTemplate
	} from '$lib/deckEdit/pageEditCore';
	import { getViewTransitions } from '$lib/presentation';
	import {
		overviewPageTiles,
		filterOverviewTiles,
		tileScale,
		overviewPageKeyIntent,
		mountedTiles,
		currentTileDirection,
		type CurrentTileDirection,
		gridColumnCount,
		gridRowsPerPage,
		moveFocus,
		overviewGridKeyIntent,
		isTypingTarget
	} from '$lib/utils/overviewPageCore';
	import type { Page } from '$lib/utils/navigate';

	export let pages: Array<Page> = [];
	/** The deck's canvas size — tiles render the slide at this size and scale it down. */
	export let width  = 1920;
	export let height = 1080;
	/** The slide we're standing on (SlideDeck's `currentSlide`), so its tile is marked
	    and mounted straight away rather than filling in a beat later. */
	export let currentPath = '';
	/** Deck folder name under src/routes (e.g. "slides") — required for EDIT writes. */
	export let deck = '';
	/** True when mounted in the presenter console (?present). Only changes what a
	    tile CLICK does: `jump()` keeps `?present` on the navigation target so the
	    pick lands back in the console, the same way PresenterView's own go()/jump()
	    do — everything else (opening the grid, browsing, closing it) behaves
	    identically to the audience window and never touches it. */
	export let present = false;

	const viewTransitions = getViewTransitions();

	// Open state lives in a shared store so other buttons can drive it too, not just
	// the `o` key: the OVERVIEW item in the audience tool flyout, and the OVERVIEW
	// button in the presenter console's bar (PresenterView). See stores/overviewOpen.

	// Filter: title / file name / page number (string substring). Empty → full grid.
	// Does not autofocus — Tab moves in/out so arrows still own the grid on open.
	let query = '';
	let searchRef: HTMLInputElement | undefined;
	$: allTiles = overviewPageTiles(pages, currentPath);
	$: tiles = filterOverviewTiles(allTiles, query);
	$: searching = query.trim().length > 0;
	$: currentNumber = allTiles.find((t) => t.isCurrent)?.number ?? 0;

	// Which tiles have been seen near the viewport. `seen` is the raw observation;
	// `mounted` folds in the current slide (always live). Reassigned, not mutated,
	// so Svelte sees the change.
	let seen: Set<number> = new Set();

	// No IntersectionObserver (old browser) → mount every tile instead. Degrade to
	// EAGER, never to blank: a card that can never resolve into its slide is worse
	// than the cost lazy mounting was there to avoid. Same bargain WebSite strikes.
	let eagerAll = false;

	$: mounted = eagerAll
		? new Set(tiles.map((t) => t.number))
		: mountedTiles(seen, currentNumber);

	// Each tile's measured box, keyed by tile number. Kept OUT of the tile objects:
	// `tiles` is derived, so a recompute would throw away anything written onto it.
	let boxW: number[] = [];
	let boxH: number[] = [];

	// One shared observer over the scroll container. rootMargin gives a tile a
	// screenful of warning, so it is already rendered by the time it is looked at.
	let gridRef: HTMLElement | undefined;
	let observer: IntersectionObserver | undefined;
	// Tiles register here as they mount. The action can run BEFORE the observer
	// exists (a child's action fires before the parent's bind:this is assigned), so
	// the node list is the source of truth and the observer picks it up when it starts.
	const tileNodes = new Map<number, HTMLElement>();

	// Where the CURRENT tile sits relative to the grid's visible (scrolled) area —
	// drives the CURRENT control's arrow. See currentTileDirection (overviewPageCore)
	// for the comparison; this just supplies the two rects from the live DOM.
	let currentDirection: CurrentTileDirection = 'unknown';
	function updateCurrentDirection() {
		if (!browser || !gridRef) {
			currentDirection = 'unknown';
			return;
		}
		const node = tileNodes.get(currentNumber);
		currentDirection = currentTileDirection(gridRef.getBoundingClientRect(), node ? node.getBoundingClientRect() : null);
	}
	// Recomputed on scroll (rAF-throttled — a scroll event fires far more often
	// than the answer can change) and on resize (the viewport, and so the
	// definition of "visible", moved). Both are cheap: two getBoundingClientRect
	// calls, no layout thrash.
	let scrollRaf: number | undefined;
	function onGridScroll() {
		if (scrollRaf != null) return;
		scrollRaf = requestAnimationFrame(() => {
			scrollRaf = undefined;
			updateCurrentDirection();
		});
	}
	/** CURRENT: center the tile you're standing on, wherever it has scrolled to. */
	function scrollToCurrent() {
		tileNodes.get(currentNumber)?.scrollIntoView({ block: 'center', behavior: 'smooth' });
	}

	// ── Keyboard browsing (roving focus) ────────────────────────────────────────
	// Arrow keys move which tile is FOCUSED; only Enter actually navigates (jump()
	// below). Moving focus, scrolling, Home/End, PageUp/PageDown, Space-to-current —
	// none of it touches anywhere but this window, the same way hovering a tile
	// with the mouse never did: browsing is invisible, a commit is not.
	//
	// `focusedNumber` is the tile's DECK number (label), not a dense index — with a
	// filter active the visible set is sparse (e.g. tiles 2 and 12), so moves go
	// through a dense index into `tiles` and map back to the real number.
	let focusedNumber = 0;

	function focusTile(n: number) {
		tileNodes.get(n)?.focus();
	}

	/** Pick a tile number that is currently visible — preferred, else first match. */
	function visibleFocusTarget(preferred = focusedNumber): number {
		if (preferred > 0 && tiles.some((t) => t.number === preferred)) return preferred;
		if (currentNumber > 0 && tiles.some((t) => t.number === currentNumber)) return currentNumber;
		return tiles[0]?.number ?? 0;
	}

	function focusSearch() {
		searchRef?.focus();
		searchRef?.select?.();
	}

	/** Tab in/out of the filter box. From a tile → search; from search → tile. */
	function onSearchKeydown(e: KeyboardEvent) {
		// Swallow every keystroke so NavigationBar's window pager never sees arrows
		// typed in the box (same bargain as the TOC search field).
		e.stopPropagation();
		if (e.key === 'Tab') {
			e.preventDefault();
			const n = visibleFocusTarget();
			if (n > 0) {
				focusedNumber = n;
				// Defer so the input finishes its own blur before the tile takes focus.
				tick().then(() => focusTile(n));
			}
			return;
		}
		if (e.key === 'Escape') {
			e.preventDefault();
			if (searching) {
				query = '';
				return;
			}
			if (showAddForm) {
				cancelAddForm();
				return;
			}
			if ($overviewEditMode) {
				leaveEdit();
				return;
			}
			close();
		}
	}

	/** The grid's live column count — a responsive `auto-fill` layout, not a fixed
	    number, so ↑/↓ and PageUp/PageDown read it back from actual tile positions
	    rather than assuming one. See gridColumnCount (overviewPageCore). */
	function liveColumns(): number {
		return gridColumnCount(tiles.map((t) => tileNodes.get(t.number)?.getBoundingClientRect().top ?? 0));
	}

	/** How many rows currently fit the grid's visible height — PageUp/PageDown's
	    step size. Measures row height from the first two VISIBLE rows (filter-aware). */
	function liveRowsPerPage(columns: number): number {
		if (!gridRef || tiles.length === 0) return 1;
		const rowOneTop = tileNodes.get(tiles[0].number)?.getBoundingClientRect().top;
		const second = tiles[columns];
		const rowTwoTop = second
			? tileNodes.get(second.number)?.getBoundingClientRect().top
			: undefined;
		const rowHeight = rowOneTop != null && rowTwoTop != null ? rowTwoTop - rowOneTop : 0;
		return gridRowsPerPage(gridRef.getBoundingClientRect().height, rowHeight);
	}

	function onGridKeydown(e: KeyboardEvent) {
		// Tab leaves the roving group for the filter box (and back via onSearchKeydown).
		if (e.key === 'Tab') {
			e.preventDefault();
			e.stopPropagation();
			focusSearch();
			return;
		}
		const intent = overviewGridKeyIntent(e);
		if (intent === 'ignore' || tiles.length === 0) return;
		// Claimed HERE, in the bubble phase, at the focused tile — the same trick
		// Tabs' roving strip uses (see its keydown handler) to take the arrows back
		// from NavigationBar's window-level pager before the event ever reaches it,
		// order-independent of which listener happened to mount first.
		e.preventDefault();
		e.stopPropagation();
		if (intent === 'commit') {
			const tile = tiles.find((t) => t.number === focusedNumber) ?? tiles[0];
			if (tile) jump(tile.path, tile.number);
			return;
		}
		if (intent === 'toCurrent') {
			if (currentNumber > 0 && tiles.some((t) => t.number === currentNumber)) {
				focusedNumber = currentNumber;
				focusTile(focusedNumber);
			}
			return;
		}
		// Dense index among the *visible* tiles, then map back to deck number.
		const dense = tiles.findIndex((t) => t.number === focusedNumber);
		const from = dense >= 0 ? dense + 1 : 1;
		const columns = liveColumns();
		const nextDense = moveFocus(from, tiles.length, columns, liveRowsPerPage(columns), intent);
		focusedNumber = tiles[nextDense - 1]?.number ?? 0;
		focusTile(focusedNumber);
	}

	// ── EDIT DECK state ──────────────────────────────────────────────────────────
	let showAddForm = false;
	let addTitle = '';
	let addPath = '';
	let addTemplate: PageTemplate = 'content';
	/** "" = append; otherwise path of the slide to insert after. */
	let addAfter = '';
	let pathTouched = false;
	let busy = false;
	let statusMsg = '';
	let statusKind: 'info' | 'error' | 'ok' = 'info';
	/** After a successful add, offer (or take) a jump to the new slide. */
	let pendingOpenPath = '';
	/** Form default: open the new slide after it is created. */
	let openAfterAdd = true;
	/** Flash label on the EDIT button (NOT ALLOWED). */
	let editFlash = '';
	let editFlashTip = '';
	let editFlashTimer: ReturnType<typeof setTimeout> | undefined;

	$: if (!pathTouched && addTitle) {
		addPath = `${slugifyStem(addTitle)}.html`;
	}

	function observeTile(node: HTMLElement, number: number) {
		node.dataset.tile = String(number);
		tileNodes.set(number, node);
		observer?.observe(node);
		return {
			destroy() {
				tileNodes.delete(number);
				observer?.unobserve(node);
			}
		};
	}

	function startObserver() {
		if (!browser || typeof IntersectionObserver === 'undefined' || observer) return;
		observer = new IntersectionObserver(
			(entries) => {
				let changed = false;
				for (const e of entries) {
					if (!e.isIntersecting) continue;
					const n = Number((e.target as HTMLElement).dataset.tile);
					if (Number.isFinite(n) && !seen.has(n)) {
						seen.add(n);
						changed = true;
					}
					// Mounting is one-way — stop watching a tile once it is live.
					observer?.unobserve(e.target);
				}
				if (changed) seen = new Set(seen);
			},
			{ root: gridRef ?? null, rootMargin: '400px 0px' }
		);
		for (const node of tileNodes.values()) observer.observe(node);
	}

	function close() {
		showAddForm = false;
		overviewEditMode.set(false);
		statusMsg = '';
		pendingOpenPath = '';
		query = '';
		overviewOpen.set(false);
	}

	function leaveEdit() {
		showAddForm = false;
		statusMsg = '';
		pendingOpenPath = '';
		overviewEditMode.set(false);
	}

	function flashNotAllowed() {
		editFlash = 'NOT ALLOWED';
		editFlashTip = 'Edit deck only works in vite dev — a static host has no source tree.';
		if (editFlashTimer) clearTimeout(editFlashTimer);
		editFlashTimer = setTimeout(() => {
			editFlash = '';
			editFlashTip = '';
		}, 2600);
	}

	function toggleEdit() {
		if (!$canEditDeck) {
			flashNotAllowed();
			return;
		}
		if ($overviewEditMode) leaveEdit();
		else {
			overviewEditMode.set(true);
			statusMsg = '';
		}
	}

	function openAddForm(afterPath: string = '') {
		if (!$canEditDeck) {
			flashNotAllowed();
			return;
		}
		if (!$overviewEditMode) overviewEditMode.set(true);
		addTitle = '';
		addPath = 'slide.html';
		addTemplate = 'content';
		addAfter = afterPath;
		pathTouched = false;
		openAfterAdd = true;
		pendingOpenPath = '';
		showAddForm = true;
		statusMsg = '';
	}

	function cancelAddForm() {
		showAddForm = false;
		statusMsg = '';
	}

	async function submitAdd() {
		if (!$canEditDeck) {
			flashNotAllowed();
			return;
		}
		if (!deck) {
			statusKind = 'error';
			statusMsg = 'No deck name — cannot write pages.ts.';
			return;
		}
		const path = normalizeSlidePath(addPath);
		if (!path) {
			statusKind = 'error';
			statusMsg = 'Path must look like my-slide.html (lowercase, hyphens).';
			return;
		}
		const title = addTitle.trim();
		if (!title) {
			statusKind = 'error';
			statusMsg = 'Title is required.';
			return;
		}
		const goOpen = openAfterAdd;
		busy = true;
		statusKind = 'info';
		statusMsg = 'Adding…';
		const res = await addPage({
			deck,
			path,
			title,
			template: addTemplate,
			after: addAfter || null
		});
		busy = false;
		if (res.error) {
			statusKind = 'error';
			statusMsg = res.error;
			return;
		}
		showAddForm = false;
		if (goOpen) {
			// Files are on disk; Vite/SvelteKit will pick up the route. Jump so the author
			// lands on what they just created instead of hunting for it in the grid.
			jump(path, currentNumber + 1);
			return;
		}
		statusKind = 'ok';
		statusMsg = `Added ${path}`;
		pendingOpenPath = path;
	}

	function openPending() {
		if (!pendingOpenPath) return;
		const path = pendingOpenPath;
		pendingOpenPath = '';
		jump(path, currentNumber + 1);
	}

	async function confirmRemove(tilePath: string, tileTitle: string) {
		if (!$canEditDeck) {
			flashNotAllowed();
			return;
		}
		if (!deck) {
			statusKind = 'error';
			statusMsg = 'No deck name — cannot write pages.ts.';
			return;
		}
		const ok = browser
			? window.confirm(
					`Remove “${tileTitle}” (${tilePath}) from the deck?\n\n` +
						`This unlists it from pages.ts only — the slide folder stays on disk.`
				)
			: false;
		if (!ok) return;
		busy = true;
		statusKind = 'info';
		statusMsg = 'Removing…';
		const res = await removePage({ deck, path: tilePath });
		busy = false;
		if (res.error) {
			statusKind = 'error';
			statusMsg = res.error;
			return;
		}
		statusKind = 'ok';
		statusMsg = `Removed ${tilePath} from the deck — waiting for reload…`;
	}

	function jump(path: string, number: number) {
		// In EDIT mode a primary click still jumps — chrome (×, +) stops propagation.
		overviewOpen.set(false);
		overviewEditMode.set(false);
		showAddForm = false;
		const direction = currentNumber > 0 && number < currentNumber ? 'back' : 'forward';
		// In the presenter console, keep `?present` so the pick lands back in the
		// console. The AUDIENCE window is never touched by opening/browsing this grid
		// (this store lives only in this window) — it follows only now, once this
		// navigation actually happens, over the same localStorage relay PREV/NEXT/TOC
		// already use (SlideDeck's publishCurrentSlide / subscribeCurrentSlide).
		navigate(`./${path}${present ? '?present' : ''}`, { viewTransitions, kind: 'slide', direction });
	}

	// `o` opens the grid, Escape closes it (or steps out of form → edit → filter → close).
	// While open, `e` toggles EDIT deck mode (mnemonic on the EDIT button).
	function handleGlobalKeydown(event: KeyboardEvent) {
		// Layered Esc while the grid is open: form → leave EDIT → clear filter → close.
		if (
			event.key === 'Escape' &&
			$overviewOpen &&
			!event.ctrlKey &&
			!event.metaKey &&
			!event.altKey
		) {
			if (showAddForm) {
				event.preventDefault();
				cancelAddForm();
				return;
			}
			if ($overviewEditMode) {
				event.preventDefault();
				leaveEdit();
				return;
			}
			if (searching) {
				event.preventDefault();
				query = '';
				return;
			}
		}
		// E = EDIT deck (only while the grid is open, never while typing in the add form).
		if (
			$overviewOpen &&
			!event.ctrlKey &&
			!event.metaKey &&
			!event.altKey &&
			!event.defaultPrevented &&
			(event.key === 'e' || event.key === 'E')
		) {
			const t = event.target as HTMLElement | null;
			const tag = t?.tagName ?? '';
			if (t?.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(tag)) return;
			event.preventDefault();
			toggleEdit();
			return;
		}
		const intent = overviewPageKeyIntent(event, $overviewOpen);
		if (intent === 'ignore') return;
		event.preventDefault();
		if (intent === 'close') {
			close();
		} else {
			overviewOpen.set(true);
		}
	}

	onMount(() => {
		if (!browser) return;
		window.addEventListener('keydown', handleGlobalKeydown);
		window.addEventListener('resize', updateCurrentDirection);
		if (typeof IntersectionObserver === 'undefined') eagerAll = true;
	});
	onDestroy(() => {
		if (browser) {
			window.removeEventListener('keydown', handleGlobalKeydown);
			window.removeEventListener('resize', updateCurrentDirection);
			if (scrollRaf != null) cancelAnimationFrame(scrollRaf);
		}
		observer?.disconnect();
		observer = undefined;
		if (editFlashTimer) clearTimeout(editFlashTimer);
	});

	// Closing the grid always drops EDIT so the next open is browse mode, and
	// clears the roving focus so the next open re-initializes it fresh (onto
	// the then-current slide, not wherever browsing last left off).
	$: if (browser && !$overviewOpen) {
		overviewEditMode.set(false);
		showAddForm = false;
		focusedNumber = 0;
		query = '';
	}

	// When the filter drops the focused tile out of the visible set, only update
	// the *logical* roving index — never call focusTile here. Planting DOM focus
	// while the speaker types in the filter box is what yanked the caret out on
	// every rearrange.
	$: if (browser && $overviewOpen && tiles.length > 0) {
		if (!focusedNumber || !tiles.some((t) => t.number === focusedNumber)) {
			focusedNumber = visibleFocusTarget(0);
		}
	}

	// The observer can only exist once the grid is in the DOM; tear it down on close
	// so a shut grid holds no callbacks.
	$: if (browser) {
		if ($overviewOpen && gridRef) startObserver();
		if (!$overviewOpen && observer) {
			observer.disconnect();
			observer = undefined;
		}
	}

	/** True when the caret is in the filter box or the add-slide form — DOM focus
	    must stay put; only the logical tile index may move under a filter. */
	function shouldPlantTileFocus(): boolean {
		if (!browser) return false;
		const active = document.activeElement as HTMLElement | null;
		if (!active) return true;
		if (isTypingTarget(active)) return false;
		if (searchRef && (active === searchRef || searchRef.contains(active))) return false;
		if (active.closest?.('.add-form-wrap')) return false;
		return true;
	}

	// Where the current tile sits: on open (after the grid's tiles are actually in
	// the DOM — `tick()` waits for that), and again whenever `currentNumber` moves
	// (deck navigation while the grid happens to stay mounted, e.g. an EDIT-mode add).
	// Seeds keyboard focus onto a real tile ONLY when the speaker is not already
	// typing in the filter / form — see shouldPlantTileFocus.
	$: if (browser && $overviewOpen && gridRef) {
		currentNumber;
		tick().then(() => {
			updateCurrentDirection();
			if (!focusedNumber || !tiles.some((t) => t.number === focusedNumber)) {
				focusedNumber = visibleFocusTarget(currentNumber);
			}
			if (focusedNumber && shouldPlantTileFocus()) focusTile(focusedNumber);
		});
	}
</script>

<!-- OverviewPage has no button of its OWN in the audience window — no third thing sitting in
     the corner competing with the ToC for the eye. It opens with `O` (the shortcut a speaker
     who wants slide 40 already reaches for) and, for the mouse, from the OVERVIEW item in
     ANNOTATE's tool flyout (audience) or the OVERVIEW button in the bottom bar (presenter
     console) — both drive the same `overviewOpen` store. Esc (or a click outside) closes it.

     In the PRESENTER CONSOLE, this component is mounted as a plain sibling of PresenterView
     (see SlideDeck), not nested in the hidden slide canvas — so `present` only needs to swap
     `position: absolute` (canvas-space) for `position: fixed` (covers the real window) and
     raise the z-index above the console's own bar/splitter/previews (70/65/60), putting the
     grid on top of the whole console UI when open. -->
{#if $overviewOpen}
	<!-- The scrim covers the whole canvas (or, in the console, the whole window).
	     Clicking it (but not the grid) closes, the same "click outside dismisses" the ToC has. -->
	<div
		class="scrim no-print"
		class:editing={$overviewEditMode}
		class:present={present}
		role="presentation"
		on:click|self={close}
		style="--canvas-w:{width}px; --canvas-h:{height}px;"
	>
		<div class="head">
			<span class="head-title">{$overviewEditMode ? 'EDIT DECK' : 'OVERVIEW PAGE'}</span>
			<span class="head-count">
				{#if searching}
					{tiles.length} of {allTiles.length}
				{:else}
					{allTiles.length} slides
				{/if}
			</span>
			<!-- Deliberately not autofocus: the grid keeps first claim on the arrows
			     on open; Tab moves in/out of this box. -->
			<input
				class="search"
				type="search"
				placeholder="Filter title, file, #…"
				aria-label="Filter overview by title, file name, or page number"
				bind:this={searchRef}
				bind:value={query}
				on:keydown={onSearchKeydown}
				on:click|stopPropagation
			/>
			{#if statusMsg || pendingOpenPath}
				<span class="head-status" class:err={statusKind === 'error'} class:ok={statusKind === 'ok'}>
					{statusMsg}
					{#if pendingOpenPath}
						<button
							type="button"
							class="status-open"
							on:click|stopPropagation={openPending}
						>Open</button>
					{/if}
				</span>
			{/if}
			<span class="head-actions">
				{#if currentNumber > 0}
					<!-- CURRENT: jump the scroll position to the tile you're standing on. The
					     arrow only appears once that tile has scrolled fully off one edge (see
					     currentTileDirection) — it names the direction, the click does the rest. -->
					<button
						type="button"
						class="current-btn"
						class:pending={currentDirection === 'above' || currentDirection === 'below'}
						on:click|stopPropagation={scrollToCurrent}
						title="Scroll to the slide you're on"
					>
						{#if currentDirection === 'above'}<span class="current-arrow" aria-hidden="true">▲</span
							>{:else if currentDirection === 'below'}<span class="current-arrow" aria-hidden="true">▼</span
							>{/if}CURRENT
					</button>
				{/if}
				{#if $overviewEditMode}
					<button
						type="button"
						class="edit-btn add-head-btn"
						disabled={busy}
						on:click|stopPropagation={() => openAddForm('')}
						title="Add a slide at the end of the deck"
					>ADD</button>
				{/if}
				<button
					type="button"
					class="edit-btn"
					class:on={$overviewEditMode}
					class:flash={!!editFlash}
					on:click|stopPropagation={toggleEdit}
					title={editFlashTip || ($canEditDeck
						? ($overviewEditMode ? 'Leave edit mode (E)' : 'Add or remove slides (E)')
						: 'Edit deck only works in vite dev')}
					aria-pressed={$overviewEditMode}
					aria-keyshortcuts="e"
				>
					{editFlash || ($overviewEditMode ? 'DONE' : 'EDIT')}
					{#if !editFlash}
						<kbd class="edit-kbd">E</kbd>
					{/if}
				</button>
				<span class="head-hint">
					{#if $overviewEditMode}
						ADD · + between · × unlist · <kbd>E</kbd> done · <kbd>Esc</kbd>
					{:else}
						arrows move · <kbd>Tab</kbd> filter · <kbd>↵</kbd> select · <kbd>Space</kbd> current · <kbd>Esc</kbd>
					{/if}
				</span>
			</span>
		</div>

		{#if showAddForm}
			<!-- svelte-ignore a11y_no_static_element_interactions — stopPropagation so
			     clicking the form does not close the scrim; keyboard path is Esc / buttons. -->
			<div class="add-form-wrap" on:click|stopPropagation on:keydown|stopPropagation>
			<form
				class="add-form"
				on:submit|preventDefault={submitAdd}
			>
				<div class="add-form-title">Add slide</div>
				<label>
					<span>Title</span>
					<input
						type="text"
						bind:value={addTitle}
						placeholder="My new slide"
						disabled={busy}
					/>
				</label>
				<label>
					<span>Path</span>
					<input
						type="text"
						value={addPath}
						on:input={(e) => {
							pathTouched = true;
							addPath = e.currentTarget.value;
						}}
						placeholder="my-new-slide.html"
						disabled={busy}
						spellcheck="false"
					/>
				</label>
				<label>
					<span>Template</span>
					<select bind:value={addTemplate} disabled={busy}>
						<option value="content">ContentPage</option>
						<option value="title">TitlePage</option>
					</select>
				</label>
				<label>
					<span>After</span>
					<select bind:value={addAfter} disabled={busy}>
						<option value="">(end of deck)</option>
						{#each allTiles as t}
							<option value={t.path}>{t.number}. {t.title}</option>
						{/each}
					</select>
				</label>
				<label class="add-form-check">
					<input type="checkbox" bind:checked={openAfterAdd} disabled={busy} />
					<span>Open after adding</span>
				</label>
				<div class="add-form-actions">
					<button type="button" class="form-btn ghost" on:click={cancelAddForm} disabled={busy}>
						Cancel
					</button>
					<button type="submit" class="form-btn" disabled={busy}>Add</button>
				</div>
			</form>
			</div>
		{/if}

		{#if searching && tiles.length === 0}
			<p class="no-matches" role="status">No slides match “{query.trim()}”.</p>
		{:else}
		<!-- svelte-ignore a11y_no_static_element_interactions — the keydown listener
		     coordinates roving focus among the real interactive elements (the tile
		     <button>s); it never turns the div itself into a control. -->
		<div class="grid" class:editing={$overviewEditMode} bind:this={gridRef} on:scroll={onGridScroll} on:keydown={onGridKeydown}>
			{#each tiles as tile (tile.path)}
				<div class="tile-wrap">
					<button
						type="button"
						class="tile"
						class:current={tile.isCurrent}
						use:observeTile={tile.number}
						on:click={() => jump(tile.path, tile.number)}
						aria-current={tile.isCurrent ? 'page' : undefined}
					>
						<!-- The box is measured; the slide inside it is rendered at native size
						     and scaled to fit, so a tile is a true miniature of the real slide. -->
						<span
							class="shot"
							style="aspect-ratio: {width} / {height};"
							bind:clientWidth={boxW[tile.number]}
							bind:clientHeight={boxH[tile.number]}
						>
							{#if mounted.has(tile.number)}
								<iframe
									class="frame"
									title={tile.title}
									src={tile.src}
									tabindex="-1"
									loading="lazy"
									style="width:{width}px; height:{height}px; transform: translate(-50%, -50%) scale({tileScale(
										boxW[tile.number] ?? 0,
										boxH[tile.number] ?? 0,
										width,
										height
									)});"
								></iframe>
							{:else}
								<!-- The cheap card a tile wears until it is worth a document. -->
								<span class="card">{tile.title}</span>
							{/if}
						</span>
						<span class="label">
							<span class="num">{tile.number}</span>
							<span class="name">{tile.title}</span>
						</span>
						{#if $overviewEditMode}
							<span class="path-line">{tile.path}</span>
						{/if}
					</button>
					{#if $overviewEditMode}
						<button
							type="button"
							class="tile-remove"
							title="Remove from deck (unlist)"
							aria-label="Remove {tile.title} from deck"
							disabled={busy}
							on:click|stopPropagation={() => confirmRemove(tile.path, tile.title)}
						>
							×
						</button>
						<!-- Insert gutter: sits in the gap AFTER this tile (between pages). -->
						<button
							type="button"
							class="gutter-add"
							title="Add slide after this one"
							aria-label="Add slide after {tile.title}"
							disabled={busy}
							on:click|stopPropagation={() => openAddForm(tile.path)}
						>
							+
						</button>
					{/if}
				</div>
			{/each}
		</div>
		{/if}
	</div>
{/if}

<style>
	.scrim {
		/* functional */
		position: absolute;
		inset: 0;
		/* Above the slide, the ToC (40) and the ink — but below the screen-fixed
		   overlay (50), so DISPLAY and the minimap stay reachable with it open. */
		z-index: 45;
		display: flex;
		flex-direction: column;

		/* cosmetic */
		background: var(--overview-page-scrim-bg, #0C0F13F2);
		padding: 2em 2.2em;
		gap: 1.2em;
	}
	/* Presenter console: this component is mounted as a plain sibling of
	   PresenterView (see SlideDeck), not nested inside the hidden slide canvas, so
	   there is no `visibility: hidden` ancestor to escape — just `position: fixed`
	   so `inset: 0` sizes off the real window instead of the canvas-space box, and
	   a z-index above the console's own bar/splitter/previews (70/65/60), so the
	   grid is the topmost thing when open, covering the whole console window. */
	.scrim.present {
		position: fixed;
		z-index: 100;
	}


	.head {
		/* functional */
		display: flex;
		align-items: baseline;
		gap: 1em;
		flex: none;

		/* cosmetic */
		color: var(--overview-page-head-fg, #E6EDF3);
		font-size: 1.1em;
	}
	.head-title {
		/* cosmetic */
		font-weight: bold;
		letter-spacing: 0.08em;
	}
	.head-count,
	.head-hint {
		/* cosmetic */
		color: var(--overview-page-dim-fg, #8A99A8);
		font-size: 0.8em;
	}
	.search {
		/* functional */
		flex: 0 1 16em;
		min-width: 8em;
		/* cosmetic */
		font: inherit;
		font-size: 0.85em;
		color: var(--overview-page-head-fg, #E6EDF3);
		background: var(--overview-page-tile-bg, #14181D);
		border: 1.5px solid var(--overview-page-tile-border, #2B3440);
		border-radius: 4px;
		padding: 0.3em 0.65em;
	}
	.search::placeholder {
		color: var(--overview-page-dim-fg, #8A99A8);
	}
	.search:focus {
		outline: none;
		border-color: var(--overview-page-tile-hover-border, #2980B9);
	}
	.no-matches {
		/* functional */
		flex: 1;
		margin: 0;
		/* cosmetic */
		color: var(--overview-page-dim-fg, #8A99A8);
		font-size: 1.05em;
		text-align: center;
		align-self: center;
	}
	.head-status {
		/* functional */
		font-size: 0.75em;
		/* cosmetic */
		color: var(--overview-page-dim-fg, #8A99A8);
	}
	.head-status.err {
		color: #e74c3c;
	}
	.head-status.ok {
		color: var(--overview-page-current-border, #00B356);
	}
	.status-open {
		/* functional */
		cursor: pointer;
		margin-left: 0.5em;
		/* cosmetic */
		font: inherit;
		font-weight: bold;
		letter-spacing: 0.04em;
		color: #fff;
		background: var(--overview-page-tile-hover-border, #2980B9);
		border: none;
		border-radius: 3px;
		padding: 0.15em 0.55em;
	}
	.head-actions {
		/* functional */
		margin-left: auto;
		display: flex;
		align-items: center;
		gap: 0.85em;
	}
	.add-head-btn {
		/* cosmetic — primary action while editing */
		background: var(--overview-page-tile-hover-border, #2980B9);
		border-color: var(--overview-page-tile-hover-border, #2980B9);
		color: #fff;
	}
	.add-head-btn:disabled {
		opacity: 0.5;
		cursor: not-allowed;
	}
	.edit-kbd {
		/* functional */
		margin-left: 0.4em;
		/* cosmetic */
		font: inherit;
		font-size: 0.85em;
		font-weight: 600;
		opacity: 0.75;
		border: 1px solid currentColor;
		border-radius: 3px;
		padding: 0 0.3em;
		line-height: 1.25;
	}
	.edit-btn {
		/* functional */
		cursor: pointer;
		/* cosmetic */
		font: inherit;
		font-size: 0.75em;
		font-weight: bold;
		letter-spacing: 0.06em;
		color: var(--overview-page-head-fg, #E6EDF3);
		background: transparent;
		border: 1.5px solid var(--overview-page-tile-border, #2B3440);
		border-radius: 4px;
		padding: 0.25em 0.7em;
	}
	.edit-btn:hover,
	.edit-btn:focus-visible {
		border-color: var(--overview-page-tile-hover-border, #2980B9);
	}
	.edit-btn.on {
		/* cosmetic */
		background: var(--overview-page-tile-hover-border, #2980B9);
		border-color: var(--overview-page-tile-hover-border, #2980B9);
		color: #fff;
	}
	.edit-btn.flash {
		/* cosmetic — same refusal language as ADJUST SAVE */
		background: #8B2E2E;
		border-color: #c0392b;
		color: #fff;
	}
	/* CURRENT — same chrome-button look as EDIT, so the two read as one family of
	   head controls. `.pending` (the current tile has scrolled off an edge) borrows
	   the same accent as a tile's own `.current` ring, so the cue reads consistently
	   whether you're looking at the button or the thing it points at. */
	.current-btn {
		/* functional */
		cursor: pointer;
		/* cosmetic */
		font: inherit;
		font-size: 0.75em;
		font-weight: bold;
		letter-spacing: 0.06em;
		color: var(--overview-page-head-fg, #E6EDF3);
		background: transparent;
		border: 1.5px solid var(--overview-page-tile-border, #2B3440);
		border-radius: 4px;
		padding: 0.25em 0.7em;
	}
	.current-btn:hover,
	.current-btn:focus-visible {
		border-color: var(--overview-page-tile-hover-border, #2980B9);
	}
	.current-btn.pending {
		border-color: var(--overview-page-current-border, #00B356);
		color: var(--overview-page-current-border, #00B356);
	}
	.current-arrow {
		/* functional */
		display: inline-block;
		margin-right: 0.3em;
		/* cosmetic — a small bounce toward the edge it's pointing at, so it reads as
		   a nudge rather than a static glyph. Respects reduced motion below. */
		animation: current-arrow-bounce 1s ease-in-out infinite;
	}
	@keyframes current-arrow-bounce {
		0%, 100% { transform: translateY(0); }
		50%      { transform: translateY(-2px); }
	}
	@media (prefers-reduced-motion: reduce) {
		.current-arrow {
			animation: none;
		}
	}

	kbd {
		/* cosmetic */
		border: 1px solid var(--overview-page-tile-border, #2B3440);
		border-radius: 3px;
		padding: 0 0.35em;
	}

	.add-form-wrap {
		/* functional */
		flex: none;
	}
	.add-form {
		/* functional */
		display: grid;
		grid-template-columns: repeat(4, minmax(0, 1fr));
		gap: 0.75em 1em;
		align-items: end;
		/* cosmetic */
		background: var(--overview-page-tile-bg, #14181D);
		border: 1.5px solid var(--overview-page-tile-border, #2B3440);
		border-radius: 6px;
		padding: 1em 1.2em;
		color: var(--overview-page-head-fg, #E6EDF3);
		font-size: 0.85em;
	}
	.add-form-title {
		/* functional */
		grid-column: 1 / -1;
		/* cosmetic */
		font-weight: bold;
		letter-spacing: 0.06em;
		font-size: 0.95em;
	}
	.add-form label {
		/* functional */
		display: flex;
		flex-direction: column;
		gap: 0.3em;
	}
	.add-form label span {
		/* cosmetic */
		color: var(--overview-page-dim-fg, #8A99A8);
		font-size: 0.85em;
	}
	.add-form input,
	.add-form select {
		/* functional */
		font: inherit;
		/* cosmetic */
		color: var(--overview-page-head-fg, #E6EDF3);
		background: #0C0F13;
		border: 1px solid var(--overview-page-tile-border, #2B3440);
		border-radius: 3px;
		padding: 0.35em 0.5em;
	}
	.add-form-check {
		/* functional */
		grid-column: 1 / -1;
		flex-direction: row !important;
		align-items: center;
		gap: 0.5em !important;
		/* cosmetic */
		color: var(--overview-page-dim-fg, #8A99A8);
		font-size: 0.9em;
	}
	.add-form-check input {
		/* functional */
		width: 1em;
		height: 1em;
	}
	.add-form-actions {
		/* functional */
		grid-column: 1 / -1;
		display: flex;
		justify-content: flex-end;
		gap: 0.6em;
	}
	.form-btn {
		/* functional */
		cursor: pointer;
		/* cosmetic */
		font: inherit;
		font-weight: bold;
		letter-spacing: 0.04em;
		color: #fff;
		background: var(--overview-page-tile-hover-border, #2980B9);
		border: none;
		border-radius: 4px;
		padding: 0.4em 1em;
	}
	.form-btn.ghost {
		/* cosmetic */
		background: transparent;
		color: var(--overview-page-dim-fg, #8A99A8);
		border: 1px solid var(--overview-page-tile-border, #2B3440);
	}
	.form-btn:disabled {
		opacity: 0.5;
		cursor: not-allowed;
	}

	.grid {
		/* functional */
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(360px, 1fr));
		gap: 1.4em;
		/* The grid is the only thing that scrolls; min-height:0 lets this flex child
		   shrink below its content height so it actually can. */
		min-height: 0;
		overflow-y: auto;
		padding-right: 0.4em;
	}
	/* Room on the right for the between-page + gutters that sit in the column gap. */
	.grid.editing {
		/* functional */
		column-gap: 1.8em;
		padding-right: 1.2em;
	}

	.tile-wrap {
		/* functional */
		position: relative;
		display: flex;
		flex-direction: column;
	}

	.tile {
		/* functional */
		display: flex;
		flex-direction: column;
		gap: 0.5em;
		padding: 0;
		cursor: pointer;
		text-align: left;

		/* cosmetic */
		background: none;
		border: none;
		font: inherit;
		color: inherit;
	}

	.shot {
		/* functional */
		display: block;
		position: relative;
		overflow: hidden;
		width: 100%;

		/* cosmetic */
		background: var(--overview-page-tile-bg, #14181D);
		border: 1.5px solid var(--overview-page-tile-border, #2B3440);
		border-radius: 4px;
	}
	.tile:hover .shot,
	.tile:focus-visible .shot {
		/* cosmetic */
		border-color: var(--overview-page-tile-hover-border, #2980B9);
	}
	.tile.current .shot {
		/* cosmetic */
		border-color: var(--overview-page-current-border, #00B356);
		box-shadow: 0 0 0 2px var(--overview-page-current-border, #00B356);
	}

	.frame {
		/* functional */
		position: absolute;
		top: 50%;
		left: 50%;
		transform-origin: center center;
		border: 0;
		/* A tile is a preview, not a document you interact with — the click belongs
		   to the button underneath, which is what jumps. */
		pointer-events: none;
	}

	.card {
		/* functional */
		position: absolute;
		inset: 0;
		display: flex;
		align-items: center;
		justify-content: center;

		/* cosmetic */
		padding: 0.8em;
		text-align: center;
		color: var(--overview-page-dim-fg, #8A99A8);
		font-size: 0.9em;
	}

	.label {
		/* functional */
		display: flex;
		align-items: baseline;
		gap: 0.5em;
		flex: none;

		/* cosmetic */
		font-size: 0.8em;
		color: var(--overview-page-head-fg, #E6EDF3);
	}
	.num {
		/* cosmetic */
		color: var(--overview-page-dim-fg, #8A99A8);
		font-variant-numeric: tabular-nums;
	}
	.name {
		/* functional */
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.path-line {
		/* functional */
		font-size: 0.7em;
		/* cosmetic */
		color: var(--overview-page-dim-fg, #8A99A8);
		font-family: ui-monospace, monospace;
	}
	.tile.current .num,
	.tile.current .name {
		/* cosmetic */
		color: var(--overview-page-current-border, #00B356);
	}

	.tile-remove {
		/* functional */
		position: absolute;
		top: 0.35em;
		right: 0.35em;
		z-index: 2;
		cursor: pointer;
		/* cosmetic */
		width: 1.7em;
		height: 1.7em;
		border-radius: 4px;
		border: 1.5px solid var(--overview-page-tile-border, #2B3440);
		background: var(--overview-page-tile-bg, #14181D);
		color: var(--overview-page-head-fg, #E6EDF3);
		font: inherit;
		font-size: 1.1em;
		line-height: 1;
		display: flex;
		align-items: center;
		justify-content: center;
		padding: 0;
	}
	.tile-remove:hover {
		border-color: #c0392b;
		color: #e74c3c;
	}

	/* Between-page insert: a small + in the column gap after each tile. */
	.gutter-add {
		/* functional */
		position: absolute;
		/* Sit in the gap between this tile and the next (half outside the wrap). */
		right: -1.05em;
		top: 28%;
		z-index: 3;
		cursor: pointer;
		/* cosmetic */
		width: 1.5em;
		height: 1.5em;
		border-radius: 50%;
		border: 1.5px solid var(--overview-page-tile-border, #2B3440);
		background: var(--overview-page-tile-bg, #14181D);
		color: var(--overview-page-dim-fg, #8A99A8);
		font: inherit;
		font-size: 1em;
		line-height: 1;
		display: flex;
		align-items: center;
		justify-content: center;
		padding: 0;
		opacity: 0.55;
		transition: opacity 120ms ease, border-color 120ms ease, color 120ms ease;
	}
	.tile-wrap:hover .gutter-add,
	.gutter-add:hover,
	.gutter-add:focus-visible {
		opacity: 1;
		border-color: var(--overview-page-tile-hover-border, #2980B9);
		color: var(--overview-page-tile-hover-border, #2980B9);
	}
	.gutter-add:disabled {
		opacity: 0.3;
		cursor: not-allowed;
	}
</style>
