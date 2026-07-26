// DOM tests for the DISPLAY zoom menu: Z opens it via displayMenuRequest, and
// ↑/↓ walk the preset rows (Enter activates; Esc closes).
import { render, cleanup, fireEvent, screen, waitFor } from '@testing-library/svelte';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { get } from 'svelte/store';
import SizeMode from '../src/lib/components/SizeMode.svelte';
import { displayMode, displayFactor } from '../src/lib/stores/displayMode';
import { displayMenuRequest, requestDisplayMenu } from '../src/lib/stores/chromeArm';

beforeEach(() => {
	localStorage.clear();
	displayMode.set('FITTED');
	displayFactor.set(1);
	displayMenuRequest.set(0);
});

afterEach(cleanup);

/** Wait until the zoom menu is open (and optionally focused on a choice). */
async function openViaZ(choiceId?: string) {
	requestDisplayMenu();
	await waitFor(() => {
		expect(document.querySelector('.menu')).toBeTruthy();
	});
	if (choiceId) {
		await waitFor(() => {
			expect(document.activeElement?.getAttribute('data-choice')).toBe(choiceId);
		});
	}
}

describe('SizeMode keyboard menu', () => {
	it('opens from requestDisplayMenu (the z mnemonic channel)', async () => {
		render(SizeMode, { props: { inline: true } });
		expect(document.querySelector('.menu')).toBeNull();

		// Focus lands on the current choice (FITTED by default).
		await openViaZ('fitted');
	});

	it('ArrowDown / ArrowUp move focus through the preset rows', async () => {
		render(SizeMode, { props: { inline: true } });
		await openViaZ('fitted');

		await fireEvent.keyDown(window, { key: 'ArrowDown' });
		expect(document.activeElement?.getAttribute('data-choice')).toBe('s-2');

		await fireEvent.keyDown(window, { key: 'ArrowDown' });
		expect(document.activeElement?.getAttribute('data-choice')).toBe('s-1.5');

		await fireEvent.keyDown(window, { key: 'ArrowUp' });
		expect(document.activeElement?.getAttribute('data-choice')).toBe('s-2');
	});

	it('Enter on a focused row applies that zoom and closes', async () => {
		render(SizeMode, { props: { inline: true } });
		await openViaZ('fitted');

		await fireEvent.keyDown(window, { key: 'ArrowDown' }); // 200%
		const row = document.activeElement as HTMLElement;
		expect(row.getAttribute('data-choice')).toBe('s-2');
		await fireEvent.click(row); // same as Enter on a focused button

		expect(get(displayMode)).toBe('SCALED');
		expect(get(displayFactor)).toBe(2);
		expect(document.querySelector('.menu')).toBeNull();
	});

	it('Escape closes the menu without changing mode', async () => {
		render(SizeMode, { props: { inline: true } });
		await openViaZ();
		expect(document.querySelector('.menu')).toBeTruthy();

		await fireEvent.keyDown(window, { key: 'Escape' });
		await waitFor(() => {
			expect(document.querySelector('.menu')).toBeNull();
		});
		expect(get(displayMode)).toBe('FITTED');
	});

	it('a second z request toggles the menu closed', async () => {
		render(SizeMode, { props: { inline: true } });
		await openViaZ();
		expect(document.querySelector('.menu')).toBeTruthy();

		requestDisplayMenu();
		await waitFor(() => {
			expect(document.querySelector('.menu')).toBeNull();
		});
	});

	it('click on FITTED (Z) still opens the menu', async () => {
		render(SizeMode, { props: { inline: true } });
		await fireEvent.click(screen.getByRole('button', { name: /FITTED/i }));
		await waitFor(() => {
			expect(document.querySelector('.menu')).toBeTruthy();
		});
	});

	it('c focuses the CUSTOM % field so a percent can be typed', async () => {
		render(SizeMode, { props: { inline: true } });
		await openViaZ('fitted');

		await fireEvent.keyDown(window, { key: 'c' });
		const input = screen.getByLabelText('Custom zoom percent') as HTMLInputElement;
		expect(document.activeElement).toBe(input);

		// Digits land in the field (typing target owns keys once focused).
		await fireEvent.input(input, { target: { value: '125' } });
		expect(input.value).toBe('125');
	});
});
