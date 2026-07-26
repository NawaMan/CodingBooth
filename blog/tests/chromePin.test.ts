import { get } from 'svelte/store';
import { beforeEach, describe, expect, it, vi } from 'vitest';

/*
  toolBarPinned / controlBarPinned — independent latches that keep each chrome bar fully
  visible instead of auto-hiding to a peek strip. Same reload-seeding discipline as the
  other persisted stores: the store reads localStorage once at module init, so "what a
  visitor sees when they come back" is only reachable by seeding storage and re-importing.
*/

const fresh = async () => {
	vi.resetModules();
	return import('../src/lib/stores/chromePin');
};

beforeEach(() => {
	localStorage.clear();
});

describe('toolBarPinned / controlBarPinned', () => {
	it('defaults to auto-hide (false) on a first visit', async () => {
		const { toolBarPinned, controlBarPinned } = await fresh();
		expect(get(toolBarPinned)).toBe(false);
		expect(get(controlBarPinned)).toBe(false);
	});

	it('reads back each bar independently', async () => {
		localStorage.setItem('toolBarPinned', 'true');
		localStorage.setItem('controlBarPinned', 'false');
		const { toolBarPinned, controlBarPinned } = await fresh();
		expect(get(toolBarPinned)).toBe(true);
		expect(get(controlBarPinned)).toBe(false);
	});

	it('falls back to auto-hide when a key holds garbage', async () => {
		// booleanCodec refuses anything that is not the two strings it writes — a corrupt
		// key must fail CLOSED (auto-hide), not arm chrome nobody asked for.
		localStorage.setItem('toolBarPinned', '{"not":"a boolean"}');
		const { toolBarPinned } = await fresh();
		expect(get(toolBarPinned)).toBe(false);
	});

	it('mirrors each bar out to its own storage key', async () => {
		const { toolBarPinned, controlBarPinned } = await fresh();
		toolBarPinned.set(true);
		expect(localStorage.getItem('toolBarPinned')).toBe('true');
		expect(localStorage.getItem('controlBarPinned')).toBe('false');

		controlBarPinned.set(true);
		expect(localStorage.getItem('controlBarPinned')).toBe('true');
		// The other bar is untouched.
		expect(localStorage.getItem('toolBarPinned')).toBe('true');
	});

	it('seeds both bars from a legacy chromePinned=true when the new keys are absent', async () => {
		// Pre-split preference: one flag for both. A visitor who had chrome pinned must not
		// find both bars tucked after the upgrade.
		localStorage.setItem('chromePinned', 'true');
		const { toolBarPinned, controlBarPinned } = await fresh();
		expect(get(toolBarPinned)).toBe(true);
		expect(get(controlBarPinned)).toBe(true);
	});

	it('lets a real per-bar key outrank the legacy one', async () => {
		localStorage.setItem('chromePinned', 'true');
		localStorage.setItem('toolBarPinned', 'false');
		const { toolBarPinned, controlBarPinned } = await fresh();
		expect(get(toolBarPinned)).toBe(false);
		// Bottom bar still has no key of its own, so it inherits the legacy pin.
		expect(get(controlBarPinned)).toBe(true);
	});
});
