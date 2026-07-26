import { render, fireEvent } from '@testing-library/svelte';
import { tick } from 'svelte';
import { get } from 'svelte/store';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import ViewSource from '$lib/components/ViewSource.svelte';
import { canSave } from '$lib/stores/adjustMode';
import { pageSourceOpen, openPageSourceEdit } from '$lib/stores/pageSource';
import * as sourceEditWindow from '$lib/stores/sourceEditWindow';

// SOURCE keeps the in-slide CodeBox. EDIT (menu or CodeBox title) opens the
// unscaled `/_source-edit` popup.

const mount = async (source = '<script>let x = 1;</script>') => {
	const { container } = render(ViewSource, {
		props: { source, path: 'src/routes/slides/stub.html/+page.svelte' }
	});
	await tick();
	return container;
};

beforeEach(() => {
	canSave.set(true);
	pageSourceOpen.set(false);
	vi.spyOn(sourceEditWindow, 'openSourceEditor').mockReturnValue(null);
});
afterEach(() => {
	canSave.set(true);
	pageSourceOpen.set(false);
	vi.restoreAllMocks();
});

describe('ViewSource SOURCE panel', () => {
	it('opens the in-slide CodeBox when pageSourceOpen is set', async () => {
		const container = await mount();
		pageSourceOpen.set(true);
		await tick();

		expect(get(pageSourceOpen)).toBe(true);
		// Panel is present (title path); EDIT is on the CodeBox title bar.
		expect(container.textContent).toContain('src/routes/slides/stub.html/+page.svelte');
		expect(container.querySelector('.code-edit')).toBeTruthy();
		// SOURCE does not open the popup by itself.
		expect(sourceEditWindow.openSourceEditor).not.toHaveBeenCalled();
	});

	it('CodeBox EDIT opens the unscaled editor window', async () => {
		const container = await mount();
		pageSourceOpen.set(true);
		await tick();

		await fireEvent.click(container.querySelector('.code-edit')!);
		await tick();

		expect(sourceEditWindow.openSourceEditor).toHaveBeenCalledTimes(1);
		const arg = vi.mocked(sourceEditWindow.openSourceEditor).mock.calls[0][0];
		expect(arg.path).toBe('src/routes/slides/stub.html/+page.svelte');
		expect(arg.source).toContain('let x = 1');
		expect(arg.canSave).toBe(true);
	});
});

describe('ViewSource ☰ → EDIT', () => {
	it('openPageSourceEdit calls the registered opener', async () => {
		await mount();
		openPageSourceEdit();
		await tick();

		expect(sourceEditWindow.openSourceEditor).toHaveBeenCalledTimes(1);
		const arg = vi.mocked(sourceEditWindow.openSourceEditor).mock.calls[0][0];
		expect(arg.canSave).toBe(true);
	});

	it('passes canSave false when the host cannot write', async () => {
		canSave.set(false);
		await mount();
		openPageSourceEdit();
		await tick();

		const arg = vi.mocked(sourceEditWindow.openSourceEditor).mock.calls[0][0];
		expect(arg.canSave).toBe(false);
	});
});
