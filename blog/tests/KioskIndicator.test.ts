import { render, cleanup, fireEvent } from '@testing-library/svelte';
import { get } from 'svelte/store';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import KioskIndicator from '$lib/components/KioskIndicator.svelte';
import {
	kioskStatus,
	kioskHoverFrozen,
	startKiosk,
	stopKiosk,
	kioskDialogOpen,
	kioskPaceOverride,
	kioskPanelPinned,
	setKioskNoteItems,
	kioskNoteIndex,
	advanceKioskNote,
	clearKioskNotes
} from '$lib/stores/kiosk';

describe('KioskIndicator — combined transport + notes panel', () => {
	beforeEach(() => {
		stopKiosk();
		kioskDialogOpen.set(false);
		kioskPaceOverride.set({});
		kioskPanelPinned.set(false);
		clearKioskNotes();
	});

	afterEach(() => {
		cleanup();
		stopKiosk();
		clearKioskNotes();
		kioskPaceOverride.set({});
		kioskPanelPinned.set(false);
	});

	it('is hidden when kiosk is off', () => {
		const { container } = render(KioskIndicator);
		expect(container.querySelector('.kiosk-panel')).toBeNull();
	});

	it('shows a compact bar while running (no notes) and can pause / stop', async () => {
		startKiosk();
		const { container, getByLabelText } = render(KioskIndicator);
		const panel = container.querySelector('.kiosk-panel');
		expect(panel).not.toBeNull();
		expect(panel?.classList.contains('has-note')).toBe(false);
		expect(container.querySelector('.kiosk-note-body')).toBeNull();

		await fireEvent.click(getByLabelText('Pause'));
		expect(get(kioskStatus)).toBe('paused');

		await fireEvent.click(getByLabelText('Resume'));
		expect(get(kioskStatus)).toBe('running');

		await fireEvent.click(getByLabelText('Stop kiosk'));
		expect(get(kioskStatus)).toBe('off');
	});

	it('kioskPanelPinned forces the panel fully visible', async () => {
		startKiosk();
		const { container } = render(KioskIndicator);
		const panel = container.querySelector('.kiosk-panel');
		expect(panel?.classList.contains('pinned')).toBe(false);

		kioskPanelPinned.set(true);
		await Promise.resolve();
		expect(panel?.classList.contains('pinned')).toBe(true);

		kioskPanelPinned.set(false);
		await Promise.resolve();
		expect(panel?.classList.contains('pinned')).toBe(false);
	});

	it('hover freezes the clock without changing the play/pause mode', async () => {
		startKiosk();
		const { container, getByLabelText } = render(KioskIndicator);
		const panel = container.querySelector('.kiosk-panel') as HTMLElement;
		expect(get(kioskStatus)).toBe('running');

		await fireEvent.mouseEnter(panel);
		expect(get(kioskHoverFrozen)).toBe(true);
		expect(get(kioskStatus)).toBe('running'); // mode untouched — still "play"
		expect(getByLabelText('Pause')).toBeTruthy(); // icon/label agree: still running

		await fireEvent.mouseLeave(panel);
		expect(get(kioskHoverFrozen)).toBe(false);
		expect(get(kioskStatus)).toBe('running');
	});

	it('hovering an already-paused kiosk leaves the mode paused, hover or not', async () => {
		startKiosk();
		const { container, getByLabelText } = render(KioskIndicator);
		const panel = container.querySelector('.kiosk-panel') as HTMLElement;

		await fireEvent.click(getByLabelText('Pause'));
		expect(get(kioskStatus)).toBe('paused');

		await fireEvent.mouseEnter(panel);
		expect(get(kioskStatus)).toBe('paused'); // still explicitly paused
		expect(getByLabelText('Resume')).toBeTruthy();

		await fireEvent.mouseLeave(panel);
		expect(get(kioskStatus)).toBe('paused'); // hover never resumes an explicit pause
	});

	it('an explicit Pause/Resume click mid-hover still works, independent of the freeze', async () => {
		startKiosk();
		const { container, getByLabelText } = render(KioskIndicator);
		const panel = container.querySelector('.kiosk-panel') as HTMLElement;

		await fireEvent.mouseEnter(panel); // freezes the clock, mode still "running"
		expect(get(kioskHoverFrozen)).toBe(true);

		await fireEvent.click(getByLabelText('Pause')); // speaker explicitly pauses mid-hover
		expect(get(kioskStatus)).toBe('paused');

		await fireEvent.mouseLeave(panel);
		expect(get(kioskHoverFrozen)).toBe(false);
		expect(get(kioskStatus)).toBe('paused'); // the explicit pause persists past the hover
	});

	it('settings opens the dialog', async () => {
		startKiosk();
		const { getByLabelText } = render(KioskIndicator);
		await fireEvent.click(getByLabelText('Kiosk settings'));
		expect(get(kioskDialogOpen)).toBe(true);
	});

	it('folds the current note line into the same panel with n/N progress', async () => {
		kioskPaceOverride.set({ useNotes: true });
		startKiosk();
		setKioskNoteItems(['First bullet', 'Second bullet', 'Third']);
		const { container, findByText } = render(KioskIndicator);

		const panel = container.querySelector('.kiosk-panel');
		expect(panel?.classList.contains('has-note')).toBe(true);
		expect(container.querySelector('.kiosk-note-body')?.textContent?.trim()).toBe('First bullet');
		expect(container.querySelector('.note-count')?.textContent?.trim()).toBe('1 / 3');

		// Advance as the runner would — body and count track the index.
		expect(advanceKioskNote()).toBe(true);
		expect(get(kioskNoteIndex)).toBe(1);
		// Svelte store update → re-render
		await findByText('Second bullet');
		expect(container.querySelector('.note-count')?.textContent?.trim()).toBe('2 / 3');
	});
});
