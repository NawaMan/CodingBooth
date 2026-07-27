<!--
  Kiosk setup dialog — step pace, page pace, optional notes-for-timing, OK / Cancel.

  Opened from the ☰ menu (or when reconfiguring). Does not start the runner until
  OK; Cancel leaves the previous session state alone (if already running, it keeps
  running with the old paces).
-->
<script lang="ts">
	import { browser } from '$app/environment';
	import {
		kioskDialogOpen,
		kioskPaces,
		kioskStatus,
		closeKioskDialog,
		confirmKiosk,
		stopKiosk
	} from '$lib/stores/kiosk';
	import {
		DEFAULT_PAGE_MS,
		DEFAULT_STEP_MS,
		msToSeconds,
		secondsToMs
	} from '$lib/kiosk/kioskCore';

	let stepSec = 2;
	let pageSec = 6;
	let useNotes = false;

	// Seed fields when the dialog opens (not on every pace store tick mid-edit).
	$: if (browser && $kioskDialogOpen) {
		stepSec = msToSeconds($kioskPaces.stepMs);
		pageSec = msToSeconds($kioskPaces.pageMs);
		useNotes = $kioskPaces.useNotes;
	}

	function onOk() {
		confirmKiosk({
			stepMs: secondsToMs(stepSec, DEFAULT_STEP_MS),
			pageMs: secondsToMs(pageSec, DEFAULT_PAGE_MS),
			useNotes
		});
	}

	function onCancel() {
		closeKioskDialog();
	}

	function onStop() {
		stopKiosk();
	}

	/**
	 * Esc cancels, Enter starts/OK — even when focus is in a number field (the fields
	 * are paces, not multi-line text). Must listen on `window` in capture: a div
	 * on:keydown only fires when that node is focused, and the scrim never is.
	 */
	function onKey(e: KeyboardEvent) {
		if (!$kioskDialogOpen) return;
		if (e.key === 'Escape') {
			e.preventDefault();
			e.stopPropagation();
			onCancel();
		} else if (e.key === 'Enter' && !e.shiftKey && !e.ctrlKey && !e.metaKey && !e.altKey) {
			e.preventDefault();
			e.stopPropagation();
			onOk();
		}
	}

	// Focus the panel when it opens so assistive tech lands on the dialog, and so
	// a stray Tab starts inside it rather than behind the scrim.
	let dialogEl: HTMLDivElement | undefined;
	$: if (browser && $kioskDialogOpen && dialogEl) {
		// tick-free: next microtask after the node exists
		queueMicrotask(() => dialogEl?.focus());
	}
</script>

<svelte:window on:keydown={onKey} />

{#if browser && $kioskDialogOpen}
	<!-- svelte-ignore a11y_no_static_element_interactions — backdrop dismiss -->
	<div
		class="kiosk-scrim no-print gp-chrome"
		role="presentation"
		on:click|self={onCancel}
	>
		<div
			class="kiosk-dialog"
			role="dialog"
			aria-modal="true"
			aria-labelledby="kiosk-dialog-title"
			tabindex="-1"
			bind:this={dialogEl}
		>
			<h2 id="kiosk-dialog-title">Kiosk / auto-advance</h2>
			<p class="lead">
				Steps reveal first (like Space), then the slide pages and loops.
				Pause and Stop stay on the small indicator — keys do not exit.
			</p>

			<label class="field">
				<span class="lbl">Step pace</span>
				<span class="ctl">
					<input type="number" min="0.25" max="120" step="0.5" bind:value={stepSec} />
					<span class="unit">seconds</span>
				</span>
				<span class="hint">Between build reveals on one slide</span>
			</label>

			<label class="field">
				<span class="lbl">Page pace</span>
				<span class="ctl">
					<input type="number" min="0.25" max="120" step="0.5" bind:value={pageSec} />
					<span class="unit">seconds</span>
				</span>
				<span class="hint">After the build (and animations) finish</span>
			</label>

			<label class="check">
				<input type="checkbox" bind:checked={useNotes} />
				<span>
					Show speaker notes (one line at a time)
					<span class="hint">
						Each &lt;Note&gt; child is a step (drag the panel; n/N progress).
						Long lines hold longer (~150 wpm); then the deck pages.
					</span>
				</span>
			</label>

			<div class="actions">
				{#if $kioskStatus !== 'off'}
					<button type="button" class="ghost danger" on:click={onStop}>Stop</button>
				{/if}
				<span class="spacer"></span>
				<button type="button" class="ghost" on:click={onCancel}>Cancel</button>
				<button type="button" class="primary" on:click={onOk}>
					{$kioskStatus === 'off' ? 'Start' : 'OK'}
				</button>
			</div>
		</div>
	</div>
{/if}

<style>
	.kiosk-scrim {
		position: fixed;
		inset: 0;
		z-index: 80;
		display: flex;
		align-items: center;
		justify-content: center;
		background: var(--kiosk-scrim, rgba(0, 0, 0, 0.55));
		font-size: calc(var(--base-font, 16px) * 0.95);
	}

	.kiosk-dialog {
		width: min(26rem, calc(100vw - 2rem));
		max-height: min(90vh, 40rem);
		overflow-y: auto;
		padding: 1.25rem 1.35rem 1.1rem;
		border-radius: 10px;
		border: 1px solid var(--kiosk-edge, rgba(255, 255, 255, 0.18));
		background: var(--kiosk-panel-bg, rgba(22, 24, 28, 0.97));
		color: var(--kiosk-fg, #d7dde5);
		box-shadow: 0 12px 40px rgba(0, 0, 0, 0.45);
	}

	h2 {
		margin: 0 0 0.35rem;
		font-size: 1.15rem;
		font-weight: 650;
		letter-spacing: 0.02em;
	}

	.lead {
		margin: 0 0 1rem;
		font-size: 0.85rem;
		line-height: 1.4;
		opacity: 0.78;
	}

	.field {
		display: grid;
		grid-template-columns: 7.5rem 1fr;
		grid-template-rows: auto auto;
		column-gap: 0.75rem;
		row-gap: 0.15rem;
		margin-bottom: 0.75rem;
		align-items: center;
	}

	.lbl {
		grid-row: 1;
		font-size: 0.9rem;
		font-weight: 600;
	}

	.ctl {
		grid-row: 1;
		display: flex;
		align-items: center;
		gap: 0.4rem;
	}

	.ctl input {
		width: 5.5rem;
		padding: 0.35rem 0.45rem;
		border-radius: 6px;
		border: 1px solid var(--kiosk-edge, rgba(255, 255, 255, 0.2));
		background: rgba(0, 0, 0, 0.35);
		color: inherit;
		font: inherit;
	}

	.unit {
		font-size: 0.8rem;
		opacity: 0.7;
	}

	.hint {
		grid-column: 2;
		font-size: 0.75rem;
		opacity: 0.6;
		line-height: 1.3;
	}

	.check {
		display: flex;
		gap: 0.55rem;
		align-items: flex-start;
		margin: 0.25rem 0 1rem;
		font-size: 0.9rem;
		cursor: pointer;
	}

	.check input {
		margin-top: 0.2rem;
	}

	.check .hint {
		display: block;
		margin-top: 0.15rem;
	}

	.actions {
		display: flex;
		align-items: center;
		gap: 0.5rem;
	}

	.spacer {
		flex: 1;
	}

	button {
		font: inherit;
		font-size: 0.9rem;
		font-weight: 600;
		padding: 0.4rem 0.85rem;
		border-radius: 6px;
		border: 1px solid transparent;
		cursor: pointer;
	}

	.primary {
		background: var(--kiosk-accent, #3fa9f5);
		color: var(--kiosk-on-accent, #0a1620);
		border-color: var(--kiosk-accent, #3fa9f5);
	}

	.ghost {
		background: transparent;
		color: inherit;
		border-color: var(--kiosk-edge, rgba(255, 255, 255, 0.22));
	}

	.ghost.danger {
		color: var(--kiosk-danger, #e5484d);
		border-color: color-mix(in srgb, var(--kiosk-danger, #e5484d) 50%, transparent);
	}

	button:hover {
		filter: brightness(1.08);
	}
</style>
