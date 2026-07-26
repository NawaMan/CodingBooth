import { get } from 'svelte/store';
import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest';
import {
	pageSourceAvailable,
	pageSourceCanView,
	pageSourceCanEdit,
	pageSourceHasOwner,
	pageSourceOpen,
	deckSourceFallback,
	registerPageSource,
	unregisterPageSource,
	openPageSource,
	openPageSourceEdit,
	closePageSource
} from '$lib/stores/pageSource';
import { canSave } from '$lib/stores/adjustMode';

describe('pageSource store', () => {
	beforeEach(() => {
		// Built-site default: no disk — SOURCE/EDIT only via a mounted ViewSource.
		canSave.set(false);
		pageSourceOpen.set(false);
		deckSourceFallback.set(null);
	});

	afterEach(() => {
		canSave.set(true); // restore vitest/dev default
		closePageSource();
	});

	it('offers nothing until something registers (and canSave is off)', () => {
		const a = Symbol('a');
		registerPageSource(a);
		unregisterPageSource(a);
		expect(get(pageSourceCanView)).toBe(false);
		expect(get(pageSourceCanEdit)).toBe(false);
		expect(get(pageSourceAvailable)).toBe(false);
		expect(get(pageSourceHasOwner)).toBe(false);
	});

	it('in dev: SOURCE and EDIT are deck-wide without ViewSource', () => {
		canSave.set(true);
		expect(get(pageSourceCanView)).toBe(true);
		expect(get(pageSourceCanEdit)).toBe(true);
		expect(get(pageSourceHasOwner)).toBe(false);
	});

	it('ViewSource registration offers SOURCE (and EDIT for demos) even when not canSave', () => {
		const owner = Symbol('vs');
		registerPageSource(owner);
		expect(get(pageSourceCanView)).toBe(true);
		expect(get(pageSourceCanEdit)).toBe(true); // demo path: EDIT → NOT ALLOWED on SAVE
		expect(get(pageSourceHasOwner)).toBe(true);
		unregisterPageSource(owner);
		expect(get(pageSourceHasOwner)).toBe(false);
		expect(get(pageSourceCanView)).toBe(false);
	});

	it('stays available while any owner remains under SPA mount overlap', () => {
		const leaving = Symbol('old');
		const arriving = Symbol('new');
		registerPageSource(leaving);
		registerPageSource(arriving); // next slide mounts before old destroys
		unregisterPageSource(leaving);
		expect(get(pageSourceAvailable)).toBe(true);
		unregisterPageSource(arriving);
		expect(get(pageSourceHasOwner)).toBe(false);
	});

	it('openPageSource opens only when something is registered (canSave off)', async () => {
		pageSourceOpen.set(false);
		await openPageSource();
		expect(get(pageSourceOpen)).toBe(false);

		const owner = Symbol('vs');
		registerPageSource(owner);
		await openPageSource();
		expect(get(pageSourceOpen)).toBe(true);

		unregisterPageSource(owner);
		expect(get(pageSourceOpen)).toBe(false); // last owner leaves → closes
	});

	it('unregister is a no-op for an unknown owner', () => {
		const owner = Symbol('real');
		registerPageSource(owner);
		unregisterPageSource(Symbol('ghost'));
		expect(get(pageSourceAvailable)).toBe(true);
		unregisterPageSource(owner);
	});

	it('openPageSourceEdit invokes the registered opener', async () => {
		const calls: number[] = [];
		const owner = Symbol('vs');
		registerPageSource(owner, () => calls.push(1));
		await openPageSourceEdit();
		expect(calls).toEqual([1]);
		unregisterPageSource(owner);
		await openPageSourceEdit(); // no opener, canSave off → no-op
		expect(calls).toEqual([1]);
	});

	it('dev fallback openPageSource fills deckSourceFallback from source-load', async () => {
		canSave.set(true);
		const fetchMock = vi.fn().mockResolvedValue({
			ok: true,
			json: async () => ({
				file: 'src/routes/slides/project-structure.html/+page.svelte',
				content: '<p>hello</p>'
			})
		});
		vi.stubGlobal('fetch', fetchMock);
		vi.stubGlobal('location', { pathname: '/slides/project-structure.html' });

		await openPageSource();

		expect(fetchMock).toHaveBeenCalled();
		expect(get(pageSourceOpen)).toBe(true);
		expect(get(deckSourceFallback)).toEqual({
			code: '<p>hello</p>',
			path: 'src/routes/slides/project-structure.html/+page.svelte',
			route: '/slides/project-structure.html'
		});

		closePageSource();
		expect(get(deckSourceFallback)).toBeNull();
		vi.unstubAllGlobals();
	});
});
