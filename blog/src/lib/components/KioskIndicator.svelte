<!--
  Kiosk chrome — one floating panel: title bar = transport + (when notes are on)
  the current line; body shows that line large and scrollable.

  Replaces a separate corner chip + notes window. Draggable by the grip / empty
  title area (not by the buttons or the note body). Explicit Pause / Stop, PLUS a
  temporary hover-freeze: mousing over the panel freezes the dwell countdown so it
  doesn't page out from under you while you're reading it or reaching for a button —
  WITHOUT flipping the play/pause mode itself (kioskHoverFrozen, not kioskStatus; see
  onHoverEnter/onHoverLeave and KioskRunner's effectiveStatus). Moving off resumes the
  countdown exactly where it was; the mode was never touched, so there's nothing to
  restore — a kiosk already explicitly paused just stays paused, hover or not.
-->
<script lang="ts">
	import { browser } from '$app/environment';
	import {
		kioskStatus,
		kioskDwellFraction,
		kioskPhaseLabel,
		kioskPaces,
		kioskNoteItems,
		kioskNoteIndex,
		kioskNotesPos,
		kioskPanelPinned,
		kioskHoverFrozen,
		toggleKioskPause,
		stopKiosk,
		openKioskDialog
	} from '$lib/stores/kiosk';
	import { noteProgressLabel } from '$lib/kiosk/kioskCore';

	const R = 10;
	const C = 2 * Math.PI * R;
	const DEFAULT_LEFT = 12;
	const DEFAULT_BOTTOM = 16;
	const PANEL_W = 440;

	$: frac = Math.max(0, Math.min(1, $kioskDwellFraction || 0));
	$: dash = `${frac * C} ${C}`;
	$: paused = $kioskStatus === 'paused';
	$: phase = $kioskPhaseLabel || (paused ? 'paused' : 'kiosk');

	$: items = $kioskNoteItems;
	$: index = $kioskNoteIndex;
	$: total = items.length;
	$: showNotes = $kioskPaces.useNotes && total > 0;
	$: current =
		showNotes && total > 0 ? items[Math.min(index, total - 1)] ?? '' : '';
	$: noteProg = showNotes ? noteProgressLabel(Math.min(index, Math.max(0, total - 1)), total) : '';
	$: live = browser && $kioskStatus !== 'off';

	let panelEl: HTMLElement | null = null;
	let dragging = false;
	let dragDx = 0;
	let dragDy = 0;

	$: pos = $kioskNotesPos;
	$: stylePos = pos
		? `left:${pos.left}px;top:${pos.top}px;bottom:auto;right:auto;`
		: `left:${DEFAULT_LEFT}px;bottom:${DEFAULT_BOTTOM}px;top:auto;right:auto;`;

	function onPointerDown(e: PointerEvent) {
		if (!panelEl || e.button !== 0) return;
		const target = e.target as HTMLElement | null;
		// Drag from grip / title chrome only — not buttons, not the note body.
		if (target?.closest?.('button')) return;
		if (!target?.closest?.('.kiosk-bar')) return;
		if (target?.closest?.('.kiosk-note-body')) return;
		const rect = panelEl.getBoundingClientRect();
		dragging = true;
		dragDx = e.clientX - rect.left;
		dragDy = e.clientY - rect.top;
		try {
			panelEl.setPointerCapture?.(e.pointerId);
		} catch {
			/* ignore */
		}
		e.preventDefault();
	}

	function onPointerMove(e: PointerEvent) {
		if (!dragging || !panelEl) return;
		const w = panelEl.offsetWidth || PANEL_W;
		const h = panelEl.offsetHeight || 48;
		const maxL = Math.max(0, window.innerWidth - w - 8);
		const maxT = Math.max(0, window.innerHeight - h - 8);
		const left = Math.min(maxL, Math.max(8, e.clientX - dragDx));
		const top = Math.min(maxT, Math.max(8, e.clientY - dragDy));
		kioskNotesPos.set({ left, top });
	}

	function onPointerUp(e: PointerEvent) {
		if (!dragging || !panelEl) return;
		dragging = false;
		try {
			panelEl.releasePointerCapture?.(e.pointerId);
		} catch {
			/* ignore */
		}
	}

	// Temporary hover-freeze (see the file header). Purely a clock signal for
	// KioskRunner — never touches kioskStatus, so the button/icon/aria-label above
	// keep reporting the real, explicit mode regardless of hover.
	function onHoverEnter() {
		kioskHoverFrozen.set(true);
	}

	function onHoverLeave() {
		kioskHoverFrozen.set(false);
	}
</script>

{#if live}
	<div
		class="kiosk-panel no-print gp-chrome"
		class:paused
		class:dragging
		class:pinned={$kioskPanelPinned}
		class:has-note={!!current}
		role="status"
		aria-live="polite"
		aria-label={paused
			? 'Kiosk paused'
			: current
				? `Kiosk running, note ${noteProg}: ${current}`
				: `Kiosk running (${phase})`}
		bind:this={panelEl}
		style={stylePos}
		on:pointerdown={onPointerDown}
		on:pointermove={onPointerMove}
		on:pointerup={onPointerUp}
		on:pointercancel={onPointerUp}
		on:mouseenter={onHoverEnter}
		on:mouseleave={onHoverLeave}
	>
		<!-- Title bar = former kiosk chip -->
		<div class="kiosk-bar">
			<span class="grip" aria-hidden="true" title="Drag to move">⠿</span>

			<button
				type="button"
				class="ring-btn"
				title={paused ? 'Resume kiosk (Alt+. U)' : 'Pause kiosk (Alt+. U)'}
				aria-label={paused ? 'Resume' : 'Pause'}
				on:click|stopPropagation={toggleKioskPause}
			>
				<svg class="ring" viewBox="0 0 28 28" width="26" height="26" aria-hidden="true">
					<circle class="track" cx="14" cy="14" r={R} fill="none" stroke-width="2.5" />
					<circle
						class="prog"
						cx="14"
						cy="14"
						r={R}
						fill="none"
						stroke-width="2.5"
						stroke-dasharray={dash}
						stroke-linecap="round"
						transform="rotate(-90 14 14)"
					/>
				</svg>
				<span class="glyph" aria-hidden="true">{paused ? '▶' : '❚❚'}</span>
			</button>

			<span class="meta">
				<span class="tag">KIOSK</span>
				<span class="phase">{phase}</span>
			</span>

			{#if noteProg}
				<span class="note-count" title="Note progress">{noteProg}</span>
			{/if}

			<span class="spacer" aria-hidden="true"></span>

			<button
				type="button"
				class="icon-btn"
				title="Kiosk settings"
				aria-label="Kiosk settings"
				on:click|stopPropagation={() => openKioskDialog()}
			>⚙</button>

			<button
				type="button"
				class="icon-btn stop"
				title="Stop kiosk"
				aria-label="Stop kiosk"
				on:click|stopPropagation={stopKiosk}
			>×</button>
		</div>

		{#if current}
			<div class="kiosk-note-body">
				{current}
			</div>
		{/if}
	</div>
{/if}

<style>
	.kiosk-panel {
		position: fixed;
		z-index: 60;
		width: min(440px, calc(100vw - 24px));
		display: flex;
		flex-direction: column;
		border-radius: 12px;
		border: 1px solid var(--kiosk-edge, rgba(255, 255, 255, 0.28));
		background: var(--kiosk-panel-bg, rgba(20, 22, 26, 0.96));
		color: var(--kiosk-fg, #d7dde5);
		box-shadow: 0 4px 18px rgba(0, 0, 0, 0.45);
		font-family: ui-sans-serif, system-ui, Segoe UI, Helvetica, Arial, sans-serif;
		opacity: var(--kiosk-idle, 0.6);
		transition: opacity 160ms ease;
		overflow: hidden;
		user-select: none;
		pointer-events: auto;
	}

	.kiosk-panel:hover,
	.kiosk-panel:focus-within,
	.kiosk-panel.paused,
	.kiosk-panel.dragging,
	.kiosk-panel.pinned {
		opacity: 1;
	}

	.kiosk-panel.paused {
		border-color: var(--kiosk-accent, #3fa9f5);
	}

	.kiosk-panel.dragging {
		cursor: grabbing;
	}

	/* Compact bar when there is no note body */
	.kiosk-panel:not(.has-note) {
		width: auto;
		min-width: 0;
		border-radius: 999px;
	}

	.kiosk-panel:not(.has-note) .kiosk-bar {
		border-bottom: 0;
		padding-right: 0.4rem;
	}

	.kiosk-bar {
		display: flex;
		align-items: center;
		gap: 0.35rem;
		padding: 0.3rem 0.45rem 0.3rem 0.4rem;
		border-bottom: 1px solid var(--kiosk-edge, rgba(255, 255, 255, 0.14));
		cursor: grab;
		flex-shrink: 0;
		touch-action: none;
		font-size: 11px;
		letter-spacing: 0.04em;
	}

	.kiosk-panel.dragging .kiosk-bar {
		cursor: grabbing;
	}

	.grip {
		opacity: 0.55;
		font-size: 0.95rem;
		line-height: 1;
		padding: 0 0.1rem;
		flex-shrink: 0;
	}

	.ring-btn {
		position: relative;
		width: 26px;
		height: 26px;
		padding: 0;
		border: 0;
		background: transparent;
		color: inherit;
		cursor: pointer;
		flex-shrink: 0;
	}

	.ring .track {
		stroke: var(--kiosk-track, rgba(255, 255, 255, 0.15));
	}

	.ring .prog {
		stroke: var(--kiosk-accent, #3fa9f5);
		transition: stroke-dasharray 80ms linear;
	}

	.glyph {
		position: absolute;
		inset: 0;
		display: grid;
		place-items: center;
		font-size: 9px;
		line-height: 1;
		opacity: 0.9;
	}

	.meta {
		display: flex;
		flex-direction: column;
		line-height: 1.15;
		min-width: 2.6rem;
		padding-right: 0.1rem;
		flex-shrink: 0;
	}

	.tag {
		font-weight: 700;
		font-size: 10px;
		opacity: 0.9;
	}

	.phase {
		font-size: 9px;
		text-transform: uppercase;
		opacity: 0.65;
		max-width: 7rem;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.note-count {
		font-weight: 700;
		font-size: 0.85rem;
		font-variant-numeric: tabular-nums;
		color: var(--kiosk-accent, #3fa9f5);
		letter-spacing: 0.02em;
		padding: 0 0.25rem;
		flex-shrink: 0;
	}

	.spacer {
		flex: 1;
		min-width: 0.5rem;
	}

	.icon-btn {
		width: 1.6rem;
		height: 1.6rem;
		padding: 0;
		border: 0;
		border-radius: 999px;
		background: transparent;
		color: inherit;
		cursor: pointer;
		opacity: 0.75;
		font-size: 14px;
		line-height: 1;
		flex-shrink: 0;
	}

	.icon-btn:hover {
		opacity: 1;
		background: rgba(255, 255, 255, 0.08);
	}

	.icon-btn.stop {
		color: var(--kiosk-danger, #e5484d);
		font-size: 1.15rem;
		font-weight: 500;
	}

	.kiosk-note-body {
		padding: 0.75rem 1rem 0.9rem;
		overflow-y: auto;
		overscroll-behavior: contain;
		max-height: min(32vh, 220px);
		font-size: 1.15rem;
		line-height: 1.45;
		font-weight: 500;
		white-space: pre-wrap;
		user-select: text;
		cursor: auto;
	}
</style>
