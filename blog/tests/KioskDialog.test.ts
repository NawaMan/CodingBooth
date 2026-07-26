import { render, cleanup, fireEvent } from '@testing-library/svelte';
import { get } from 'svelte/store';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import KioskDialog from '$lib/components/KioskDialog.svelte';
import {
	kioskDialogOpen,
	kioskStatus,
	kioskPaces,
	openKioskDialog,
	stopKiosk,
	kioskWantsRun
} from '$lib/stores/kiosk';

describe('KioskDialog', () => {
	beforeEach(() => {
		stopKiosk();
		kioskDialogOpen.set(false);
	});

	afterEach(() => {
		cleanup();
		stopKiosk();
		kioskDialogOpen.set(false);
	});

	it('is absent until opened', () => {
		const { container } = render(KioskDialog);
		expect(container.querySelector('.kiosk-dialog')).toBeNull();
	});

	it('shows step/page fields and starts on OK', async () => {
		openKioskDialog();
		const { container, getByRole } = render(KioskDialog);
		expect(container.querySelector('.kiosk-dialog')).not.toBeNull();
		expect(container.querySelectorAll('input[type="number"]').length).toBe(2);

		await fireEvent.click(getByRole('button', { name: 'Start' }));
		expect(get(kioskStatus)).toBe('running');
		expect(get(kioskWantsRun)).toBe(true);
		expect(get(kioskDialogOpen)).toBe(false);
		const paces = get(kioskPaces);
		expect(paces.stepMs).toBeGreaterThan(0);
		expect(paces.pageMs).toBeGreaterThanOrEqual(paces.stepMs);
	});

	it('Cancel closes without starting', async () => {
		openKioskDialog();
		const { getByRole } = render(KioskDialog);
		await fireEvent.click(getByRole('button', { name: 'Cancel' }));
		expect(get(kioskStatus)).toBe('off');
		expect(get(kioskDialogOpen)).toBe(false);
	});

	it('Escape cancels and Enter starts', async () => {
		openKioskDialog();
		render(KioskDialog);
		expect(get(kioskDialogOpen)).toBe(true);

		await fireEvent.keyDown(window, { key: 'Escape' });
		expect(get(kioskDialogOpen)).toBe(false);
		expect(get(kioskStatus)).toBe('off');

		openKioskDialog();
		await fireEvent.keyDown(window, { key: 'Enter' });
		expect(get(kioskStatus)).toBe('running');
		expect(get(kioskDialogOpen)).toBe(false);
	});
});
