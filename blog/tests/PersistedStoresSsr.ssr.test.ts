import { get } from 'svelte/store';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/*
  The persisted stores, on the SERVER — the node project, where `browser` is false.

  This is not a paranoid test. There is no `localStorage` in node, so a store that forgets
  its `browser` guard does not degrade gracefully at prerender: it throws a ReferenceError
  at module-init time and takes the BUILD down. And because the prerender happens once, at
  build time, and the same HTML is served to everyone, a store that DID read storage on the
  server would be baking one machine's preference into every visitor's page.

  So the contract is: on the server every store holds its initial value, and storage is not
  touched at all. We install a spy where `localStorage` would be to prove the second half —
  if a guard is ever dropped, this fails loudly instead of silently working on the machine
  that happens to have run the build.
*/

const storage = {
	getItem: vi.fn(() => null),
	setItem: vi.fn(),
	removeItem: vi.fn(),
	clear: vi.fn()
};

beforeEach(() => {
	vi.clearAllMocks();
	// A localStorage that must never be called. In real SSR the global is simply absent;
	// here its presence turns "would have thrown" into "was called", which is assertable.
	(globalThis as Record<string, unknown>).localStorage = storage;
});

afterEach(() => {
	delete (globalThis as Record<string, unknown>).localStorage;
});

const freshDisplay = async () => {
	vi.resetModules();
	return import('../src/lib/stores/displayMode');
};
const freshLayout = async () => {
	vi.resetModules();
	return import('../src/lib/stores/adjustMode');
};
const freshDiagram = async () => {
	vi.resetModules();
	return import('../src/lib/stores/diagramScroll');
};

describe('the persisted stores prerender at their defaults', () => {
	it('displayMode is FITTED and displayFactor is 1', async () => {
		const { displayMode, displayFactor } = await freshDisplay();
		expect(get(displayMode)).toBe('FITTED');
		expect(get(displayFactor)).toBe(1);
	});

	it('adjustMode is OFF — the authoring chrome never reaches a prerendered page', async () => {
		const { adjustMode } = await freshLayout();
		expect(get(adjustMode)).toBe(false);
	});

	it('diagramScroll is -500, and is a number rather than NaN', async () => {
		const { diagramScroll } = await freshDiagram();
		expect(get(diagramScroll)).toBe(-500);
		expect(Number.isNaN(get(diagramScroll))).toBe(false);
	});
});

describe('the persisted stores never touch storage on the server', () => {
	it('displayMode neither reads nor writes — not even the legacy scaleMode key', async () => {
		// The legacy migration is the easiest one to get wrong, because it reads a SECOND
		// key and so needs its own guard.
		await freshDisplay();
		expect(storage.getItem).not.toHaveBeenCalled();
		expect(storage.setItem).not.toHaveBeenCalled();
	});

	it('adjustMode neither reads nor writes', async () => {
		await freshLayout();
		expect(storage.getItem).not.toHaveBeenCalled();
		expect(storage.setItem).not.toHaveBeenCalled();
	});

	it('diagramScroll neither reads nor writes', async () => {
		await freshDiagram();
		expect(storage.getItem).not.toHaveBeenCalled();
		expect(storage.setItem).not.toHaveBeenCalled();
	});

	it('a set on the server stays in memory and is not mirrored out', async () => {
		const { displayMode } = await freshDisplay();
		displayMode.set('SCALED');
		expect(get(displayMode)).toBe('SCALED');
		expect(storage.setItem).not.toHaveBeenCalled();
	});
});
