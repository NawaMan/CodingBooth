import { get } from 'svelte/store';
import { beforeEach, describe, expect, it, vi } from 'vitest';

/*
  The three stores that predate persisted() — displayMode/displayFactor, adjustMode and
  diagramScroll — pinned BEFORE they move onto the factory, because the move has to be
  behaviour-preserving and "it still seems to work" is not a proof.

  Each store reads localStorage exactly ONCE, at module init. So "what a visitor sees when
  they come back tomorrow" is not reachable by calling a method — it is only reachable by
  seeding storage and then importing the module fresh. `vi.resetModules()` + a dynamic
  import IS the reload; that is why every case below re-imports rather than sharing a store.
*/

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

beforeEach(() => {
	localStorage.clear();
});

describe('displayMode — the mode', () => {
	it('defaults to FITTED on a first visit', async () => {
		const { displayMode } = await freshDisplay();
		expect(get(displayMode)).toBe('FITTED');
	});

	it('reads back a stored SCALED', async () => {
		localStorage.setItem('displayMode', 'SCALED');
		const { displayMode } = await freshDisplay();
		expect(get(displayMode)).toBe('SCALED');
	});

	it('falls back to FITTED when the key holds garbage', async () => {
		localStorage.setItem('displayMode', 'SIDEWAYS');
		const { displayMode } = await freshDisplay();
		expect(get(displayMode)).toBe('FITTED');
	});

	it('mirrors a change out to storage', async () => {
		const { displayMode } = await freshDisplay();
		displayMode.set('SCALED');
		expect(localStorage.getItem('displayMode')).toBe('SCALED');
	});
});

describe('displayMode — the legacy scaleMode migration', () => {
	// The old store was a boolean: `true` meant fit-to-window (now FITTED), `false` meant
	// the native "FIXED" view (now SCALED @ 100%). A visitor who chose FIXED before the
	// rename must not be silently moved back to FITTED.
	it('migrates a legacy scaleMode=false into SCALED', async () => {
		localStorage.setItem('scaleMode', 'false');
		const { displayMode } = await freshDisplay();
		expect(get(displayMode)).toBe('SCALED');
	});

	it('migrates a legacy scaleMode=true into FITTED', async () => {
		localStorage.setItem('scaleMode', 'true');
		const { displayMode } = await freshDisplay();
		expect(get(displayMode)).toBe('FITTED');
	});

	it('lets a real displayMode key outrank the legacy one', async () => {
		localStorage.setItem('scaleMode', 'false'); // would say SCALED
		localStorage.setItem('displayMode', 'FITTED'); // but this is the current answer
		const { displayMode } = await freshDisplay();
		expect(get(displayMode)).toBe('FITTED');
	});

	it('still consults the legacy key when displayMode holds garbage', async () => {
		localStorage.setItem('scaleMode', 'false');
		localStorage.setItem('displayMode', 'SIDEWAYS');
		const { displayMode } = await freshDisplay();
		expect(get(displayMode)).toBe('SCALED');
	});
});

describe('displayMode — the zoom factor', () => {
	it('defaults to 1 (100%)', async () => {
		const { displayFactor } = await freshDisplay();
		expect(get(displayFactor)).toBe(1);
	});

	it('reads back a stored factor', async () => {
		localStorage.setItem('displayFactor', '2.5');
		const { displayFactor } = await freshDisplay();
		expect(get(displayFactor)).toBe(2.5);
	});

	it('clamps a hand-edited factor down to MAX_FACTOR', async () => {
		localStorage.setItem('displayFactor', '4000');
		const { displayFactor, MAX_FACTOR } = await freshDisplay();
		expect(get(displayFactor)).toBe(MAX_FACTOR);
	});

	it('clamps a hand-edited factor up to MIN_FACTOR', async () => {
		localStorage.setItem('displayFactor', '0.0001');
		const { displayFactor, MIN_FACTOR } = await freshDisplay();
		expect(get(displayFactor)).toBe(MIN_FACTOR);
	});

	it('resets a garbage factor to 1 rather than yielding NaN', async () => {
		localStorage.setItem('displayFactor', 'oops');
		const { displayFactor } = await freshDisplay();
		expect(get(displayFactor)).toBe(1);
	});

	it('resets a zero factor to 1 — a 0 zoom is corruption, not a zoom level', async () => {
		// Deliberately NOT clamped up to MIN_FACTOR: a deck that comes back at 10% looks
		// broken, where one that comes back at 100% just looks fresh.
		localStorage.setItem('displayFactor', '0');
		const { displayFactor } = await freshDisplay();
		expect(get(displayFactor)).toBe(1);
	});

	it('resets a negative factor to 1', async () => {
		localStorage.setItem('displayFactor', '-3');
		const { displayFactor } = await freshDisplay();
		expect(get(displayFactor)).toBe(1);
	});

	it('mirrors a change out to storage', async () => {
		const { displayFactor } = await freshDisplay();
		displayFactor.set(2);
		expect(localStorage.getItem('displayFactor')).toBe('2');
	});
});

describe('adjustMode', () => {
	it('starts OFF on a first visit', async () => {
		const { adjustMode } = await freshLayout();
		expect(get(adjustMode)).toBe(false);
	});

	it('remembers being on across a reload', async () => {
		localStorage.setItem('adjustMode', 'true');
		const { adjustMode } = await freshLayout();
		expect(get(adjustMode)).toBe(true);
	});

	it('reads a stored false as off', async () => {
		localStorage.setItem('adjustMode', 'false');
		const { adjustMode } = await freshLayout();
		expect(get(adjustMode)).toBe(false);
	});

	it('treats a garbage key as off — the authoring chrome fails CLOSED', async () => {
		localStorage.setItem('adjustMode', '{"not":"a boolean"}');
		const { adjustMode } = await freshLayout();
		expect(get(adjustMode)).toBe(false);
	});

	it('mirrors a change out to storage as a plain boolean string', async () => {
		const { adjustMode } = await freshLayout();
		adjustMode.set(true);
		expect(localStorage.getItem('adjustMode')).toBe('true');
		adjustMode.set(false);
		expect(localStorage.getItem('adjustMode')).toBe('false');
	});

	it('leaves canAdjust and canSave — which are NOT persisted stores — alone', async () => {
		// canAdjust is resolved from DEV + the sticky ?adjust flag + the slide's own
		// declaration; canSave from the dev server's existence. Neither is a localStorage
		// mirror, and neither moves onto persisted().
		const { canAdjust, canSave } = await freshLayout();
		expect(typeof get(canAdjust)).toBe('boolean');
		expect(typeof get(canSave)).toBe('boolean');
	});
});

describe('diagramScroll', () => {
	it('defaults to -500', async () => {
		const { diagramScroll } = await freshDiagram();
		expect(get(diagramScroll)).toBe(-500);
	});

	it('reads back a stored offset', async () => {
		localStorage.setItem('diagramScroll', '250');
		const { diagramScroll } = await freshDiagram();
		expect(get(diagramScroll)).toBe(250);
	});

	it('writes the default out when the key is absent', async () => {
		await freshDiagram();
		expect(localStorage.getItem('diagramScroll')).toBe('-500');
	});

	it('mirrors a change out to storage', async () => {
		const { diagramScroll } = await freshDiagram();
		diagramScroll.set(120);
		expect(localStorage.getItem('diagramScroll')).toBe('120');
	});

	it('falls back to the default on a corrupt key, and never yields NaN', async () => {
		// THE BUG this migration exists to kill. `parseInt('oops')` is NaN, NaN reaches the
		// store, and a geometry store holding NaN lays the diagram out at `NaNpx`.
		localStorage.setItem('diagramScroll', 'oops');
		const { diagramScroll } = await freshDiagram();
		expect(Number.isNaN(get(diagramScroll))).toBe(false);
		expect(get(diagramScroll)).toBe(-500);
	});
});

describe('the stores do not sync across tabs', () => {
	// persisted() offers cross-tab sync and defaults it ON. These three deliberately opt
	// OUT, because the presenter console is a second window onto the same deck: syncing
	// would mean the speaker zooming in to inspect a slide also zooms the AUDIENCE's
	// screen. Preserving today's independence is the whole point of a behaviour-preserving
	// migration; turning sync on for these is a separate, deliberate decision.
	it('ignores a displayMode written by another tab', async () => {
		const { displayMode } = await freshDisplay();
		window.dispatchEvent(
			new StorageEvent('storage', { key: 'displayMode', newValue: 'SCALED' })
		);
		expect(get(displayMode)).toBe('FITTED');
	});

	it('ignores a adjustMode written by another tab', async () => {
		const { adjustMode } = await freshLayout();
		window.dispatchEvent(new StorageEvent('storage', { key: 'adjustMode', newValue: 'true' }));
		expect(get(adjustMode)).toBe(false);
	});
});
