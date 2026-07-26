<!--
  KioskRunner — the auto-advance clock.

  While status is `running`, ticks every ~100ms and:

    1. Waits for finite CSS animations on the slide content to finish.
    2. Waits for media holds (Video playthroughs) — progress tracks the tape.
    3. Reveals the next build step (activeSteps.next — Space semantics).
    4. When "Show speaker notes" is on: dwells on each note line in order
       (step pace, stretched by ~wpm for long lines), advancing the caption.
    5. Pages (and loops to the first visible slide at the end of the deck).
       Leaving a media hold pages *immediately* — no second full pageMs after
       the clip already spent its runtime.

  Pause freezes the dwell timer. Stop ends the session.
-->
<script lang="ts">
	import { browser } from '$app/environment';
	import { onDestroy } from 'svelte';
	import { get } from 'svelte/store';
	import type { Page } from '$lib/utils/navigate';
	import { visiblePages } from '$lib/utils/navigate';
	import { navigate } from '$lib/utils/deckNav';
	import { getViewTransitions } from '$lib/presentation';
	import { activeSteps } from '$lib/stores/activeSteps';
	import { kioskMediaBusy, kioskMediaProgress } from '$lib/stores/kioskMediaHold';
	import { collectFinite, isPlaying, sampleFraction } from '$lib/utils/slideAnim';
	import {
		kioskStatus,
		kioskHoverFrozen,
		kioskPaces,
		kioskDwellFraction,
		kioskPhaseLabel,
		kioskNoteItems,
		kioskNoteIndex,
		advanceKioskNote
	} from '$lib/stores/kiosk';
	import {
		dwellProgress,
		kioskAction,
		noteItemDwellMs,
		noteProgressLabel
	} from '$lib/kiosk/kioskCore';

	export let pages: Page[] = [];
	export let currentSlide: string = '';
	export let prefix: string = './';
	export let wpm: number = 150;

	const viewTransitions = getViewTransitions();

	let timer: ReturnType<typeof setInterval> | null = null;
	let dwellStartedAt = 0;
	let dwellTotal = 0;
	let pausedElapsed = 0;
	let lastAction: string = '';
	let lastSlide = '';
	/** Avoid re-arming the same note index with a fresh dwell every tick. */
	let lastNoteKey = '';

	function contentRoot(): Element | null {
		return document.querySelector('.content');
	}

	function animBusy(): boolean {
		const root = contentRoot();
		if (!root) return false;
		const anims = collectFinite(root);
		if (!anims.length) return false;
		// Busy means something is actually advancing on the clock — not merely "the
		// playhead hasn't reached the end." A group parked at a frame (a Terminal held
		// at its ▶ button, an un-scrubbed animation) is *waiting*, not busy; treating it
		// as busy freezes the loop on a human gate that will never trip itself. A parked
		// Terminal that registered a build gets driven instead, via the `reveal` branch.
		return isPlaying(anims) && sampleFraction(anims) < 0.999;
	}

	function targetForPage(): string | null {
		const deck = visiblePages(pages);
		if (!deck.length) return null;
		const idx = deck.findIndex((p) => p.path === currentSlide);
		if (idx < 0) return prefix + deck[0].path;
		if (idx < deck.length - 1) return prefix + deck[idx + 1].path;
		return prefix + deck[0].path;
	}

	function goNextPage() {
		const href = targetForPage();
		if (!href) return;
		const leaving = pages.find((p) => p.path === currentSlide);
		const kind = leaving?.transition ?? 'slide';
		navigate(href, { viewTransitions, kind, direction: 'forward' });
	}

	function resetDwell(totalMs: number, phase: string) {
		dwellStartedAt = performance.now();
		dwellTotal = totalMs;
		pausedElapsed = 0;
		lastAction = phase;
		kioskPhaseLabel.set(phase);
		kioskDwellFraction.set(0);
	}

	function tick() {
		// Hover-freeze stops the clock the same way Pause does, WITHOUT touching
		// kioskStatus — see kioskHoverFrozen's doc comment in stores/kiosk.ts.
		if (get(kioskStatus) !== 'running' || get(kioskHoverFrozen)) return;

		if (currentSlide !== lastSlide) {
			lastSlide = currentSlide;
			lastAction = '';
			lastNoteKey = '';
			dwellStartedAt = 0;
			dwellTotal = 0;
			pausedElapsed = 0;
			kioskDwellFraction.set(0);
		}

		const paces = get(kioskPaces);
		const steps = get(activeSteps);
		const items = get(kioskNoteItems);
		const noteIdx = get(kioskNoteIndex);
		const hasNoteItem = paces.useNotes && items.length > 0 && noteIdx < items.length;
		const mediaBusy = get(kioskMediaBusy);
		const animIsBusy = animBusy();

		const action = kioskAction({
			animBusy: animIsBusy,
			mediaBusy,
			hasNextStep: !!steps?.hasNext,
			hasNoteItem
		});

		if (action === 'wait') {
			// Media hold: progress tracks the video, not a fake dwell clock.
			// CSS anim wait: no ring (unchanged).
			if (mediaBusy && !animIsBusy) {
				if (lastAction !== 'media') {
					dwellStartedAt = performance.now();
					dwellTotal = 0;
					pausedElapsed = 0;
					lastAction = 'media';
					kioskPhaseLabel.set('video');
				}
				kioskDwellFraction.set(get(kioskMediaProgress));
				return;
			}
			if (lastAction !== 'wait') resetDwell(0, 'wait');
			kioskDwellFraction.set(0);
			return;
		}

		if (action === 'reveal') {
			const needMs = paces.stepMs;
			if (lastAction !== 'reveal' || dwellTotal !== needMs) resetDwell(needMs, 'reveal');
			const elapsed = performance.now() - dwellStartedAt;
			kioskDwellFraction.set(dwellProgress(elapsed, dwellTotal));
			if (elapsed < dwellTotal) return;
			const s = get(activeSteps);
			if (s?.hasNext) s.next();
			resetDwell(paces.stepMs, 'reveal');
			return;
		}

		if (action === 'note') {
			const line = items[noteIdx] ?? '';
			const needMs = noteItemDwellMs(line, paces.stepMs, wpm);
			const noteKey = `${currentSlide}:${noteIdx}:${line.slice(0, 40)}`;
			const phase = `note ${noteProgressLabel(noteIdx, items.length)}`;
			if (lastAction !== phase || lastNoteKey !== noteKey || dwellTotal !== needMs) {
				lastNoteKey = noteKey;
				resetDwell(needMs, phase);
			}
			const elapsed = performance.now() - dwellStartedAt;
			kioskDwellFraction.set(dwellProgress(elapsed, dwellTotal));
			if (elapsed < dwellTotal) return;

			// Finished this line — next line, or page after the last.
			const more = advanceKioskNote();
			if (more) {
				lastNoteKey = '';
				// next tick will arm the new note
				return;
			}
			// Last note done → page immediately (notes already carried the content dwell).
			resetDwell(paces.pageMs, 'page');
			goNextPage();
			return;
		}

		// page (no notes, or notes off)
		// After a video hold the runtime already *was* the dwell — page now, no
		// second full pageMs of dead air on the last frame.
		if (lastAction === 'media') {
			resetDwell(0, 'page');
			goNextPage();
			return;
		}
		const needMs = paces.pageMs;
		if (lastAction !== 'page' || dwellTotal !== needMs) resetDwell(needMs, 'page');
		const elapsed = performance.now() - dwellStartedAt;
		kioskDwellFraction.set(dwellProgress(elapsed, dwellTotal));
		if (elapsed < dwellTotal) return;
		resetDwell(needMs, 'page');
		goNextPage();
	}

	function stopTimer() {
		if (timer != null) {
			clearInterval(timer);
			timer = null;
		}
	}

	function syncTimer(status: string) {
		if (!browser) return;
		if (status === 'running') {
			if (timer == null) {
				if (pausedElapsed > 0 && dwellTotal > 0) {
					dwellStartedAt = performance.now() - pausedElapsed;
					pausedElapsed = 0;
				} else if (!dwellStartedAt) {
					dwellStartedAt = performance.now();
				}
				timer = setInterval(tick, 100);
				tick();
			}
		} else if (status === 'paused') {
			if (timer != null && dwellStartedAt) {
				pausedElapsed = Math.max(0, performance.now() - dwellStartedAt);
			}
			stopTimer();
		} else {
			stopTimer();
			dwellStartedAt = 0;
			dwellTotal = 0;
			pausedElapsed = 0;
			lastAction = '';
			lastSlide = '';
			lastNoteKey = '';
		}
	}

	// Hover-freeze is treated exactly like an explicit pause for the CLOCK (same
	// elapsed-preserving syncTimer branch, so unfreezing never skips the frozen
	// interval forward) while leaving kioskStatus — and so the play/pause icon —
	// untouched. `status === 'off'` still wins outright.
	$: effectiveStatus =
		$kioskStatus === 'off' ? 'off' : $kioskStatus === 'paused' || $kioskHoverFrozen ? 'paused' : 'running';
	$: if (browser) syncTimer(effectiveStatus);
	$: if (browser && $kioskStatus === 'running' && currentSlide) {
		void currentSlide;
	}

	onDestroy(stopTimer);
</script>
