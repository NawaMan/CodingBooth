import { render } from '@testing-library/svelte';
import { tick } from 'svelte';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import NoteVisibilityHost from './NoteVisibilityHost.svelte';
import { presenterMode, consoleLive } from '../src/lib/stores/presenter';
import { displayMode } from '../src/lib/stores/displayMode';

// The below-slide speaker note is shown only in SCALED display mode; once a live
// ?present console is carrying the notes (consoleLive), that below-slide copy is
// redundant and must drop — but the presenter panel (presenterMode) and every other
// home are untouched.
const noteShown = (root: ParentNode) => !!root.querySelector('.note');

beforeEach(() => {
	presenterMode.set(false);
	consoleLive.set(false);
	displayMode.set('FITTED');
});
afterEach(() => {
	presenterMode.set(false);
	consoleLive.set(false);
	displayMode.set('FITTED');
});

describe('Note — below-slide visibility vs a live console', () => {
	it('shows below the slide in SCALED mode with no console open', async () => {
		displayMode.set('SCALED');
		const { container } = render(NoteVisibilityHost);
		await tick();
		expect(noteShown(container)).toBe(true);
	});

	it('drops the below-slide note in SCALED mode once a console is live', async () => {
		displayMode.set('SCALED');
		consoleLive.set(true);
		const { container } = render(NoteVisibilityHost);
		await tick();
		expect(noteShown(container)).toBe(false);
	});

	it('re-shows the below-slide note if the console goes away (consoleLive back to false)', async () => {
		displayMode.set('SCALED');
		consoleLive.set(true);
		const { container } = render(NoteVisibilityHost);
		await tick();
		expect(noteShown(container)).toBe(false);

		consoleLive.set(false);
		await tick();
		expect(noteShown(container)).toBe(true);
	});

	it('is hidden in FITTED mode regardless of the console', async () => {
		displayMode.set('FITTED');
		consoleLive.set(false);
		const { container } = render(NoteVisibilityHost);
		await tick();
		expect(noteShown(container)).toBe(false);
	});

	it('the presenter panel is unaffected — presenterMode still shows the note even with a console live', async () => {
		// In the console window itself: presenterMode true AND (its own) consoleLive
		// could be set; the note must still render as the panel.
		presenterMode.set(true);
		consoleLive.set(true);
		displayMode.set('FITTED');
		const { container } = render(NoteVisibilityHost);
		await tick();
		expect(noteShown(container)).toBe(true);
		expect(container.querySelector('.note')?.classList.contains('presenter')).toBe(true);
	});
});
