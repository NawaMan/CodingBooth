import { get } from 'svelte/store';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { persisted, reset } from '../src/lib/stores/persisted';
import { numberCodec, type Codec } from '../src/lib/utils/stateCore';

const KEY = 'geekpresent:test:count';

/** A reload is just a fresh store over the same key — the browser keeps the storage,
    the module state is new. That is exactly what constructing a second store models. */
const reload = (initial: number, codec: Codec<number> = numberCodec()) =>
	persisted<number>(KEY, initial, { codec });

beforeEach(() => {
	localStorage.clear();
	sessionStorage.clear();
});

afterEach(() => {
	vi.restoreAllMocks();
});

describe('persisted — survives a reload', () => {
	it('writes on change and reads back into a fresh store', () => {
		const count = persisted(KEY, 0, { codec: numberCodec() });
		count.set(7);

		expect(localStorage.getItem(KEY)).toBe('7');
		expect(get(reload(0, numberCodec()))).toBe(7);
	});

	it('keeps a persisted ZERO rather than snapping back to the default', () => {
		// The classic bug: a codec that reports 0 as "nothing stored" makes a counter the
		// visitor deliberately zeroed spring back to its initial value on reload.
		const count = persisted(KEY, 5, { codec: numberCodec() });
		count.set(0);

		expect(get(reload(5, numberCodec()))).toBe(0);
	});

	it('starts at the initial value when the key is absent', () => {
		expect(get(persisted(KEY, 3, { codec: numberCodec() }))).toBe(3);
	});
});

describe('persisted — distrusts what it reads', () => {
	it('falls back to initial when the key holds garbage, and never yields NaN', () => {
		// This is stores/diagramScroll.ts's bug, fixed: `parseInt('oops')` is NaN, and a
		// NaN in a geometry store lays the slide out at `NaNpx`.
		localStorage.setItem(KEY, 'oops');

		const count = reload(3, numberCodec());
		expect(get(count)).toBe(3);
		expect(Number.isNaN(get(count) as number)).toBe(false);
	});

	it('clamps a hand-edited key back into range', () => {
		localStorage.setItem(KEY, '4000');
		expect(get(reload(0, numberCodec({ min: 0, max: 99 })))).toBe(99);
	});

	it('survives a key written by an older version with a different shape', () => {
		localStorage.setItem(KEY, '{"was":"an object"}');
		expect(get(reload(1, numberCodec()))).toBe(1);
	});
});

describe('persisted — never takes the slide down', () => {
	it('swallows a setItem that throws (private mode / quota full)', () => {
		const boom = vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
			throw new DOMException('QuotaExceededError');
		});

		const count = persisted(KEY, 0, { codec: numberCodec() });
		// The store must keep working in memory even though nothing can be written.
		expect(() => count.set(9)).not.toThrow();
		expect(get(count)).toBe(9);
		expect(boom).toHaveBeenCalled();
	});

	it('swallows a getItem that throws behind a storage policy', () => {
		vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => {
			throw new DOMException('SecurityError');
		});

		expect(() => persisted(KEY, 4, { codec: numberCodec() })).not.toThrow();
		expect(get(persisted(KEY, 4, { codec: numberCodec() }))).toBe(4);
	});
});

describe('persisted — the other tab', () => {
	const storageEvent = (key: string, newValue: string | null) =>
		window.dispatchEvent(new StorageEvent('storage', { key, newValue }));

	it('adopts a value another tab wrote', () => {
		const count = persisted(KEY, 0, { codec: numberCodec() });
		storageEvent(KEY, '12');
		expect(get(count)).toBe(12);
	});

	it('ignores garbage another tab wrote — the value we have is better than one we know is broken', () => {
		const count = persisted(KEY, 0, { codec: numberCodec() });
		count.set(5);
		storageEvent(KEY, 'nonsense');
		expect(get(count)).toBe(5);
	});

	it('falls back to initial when another tab REMOVES the key, not to null', () => {
		// `newValue === null` is a removal. Setting the store to null would hand every
		// subscriber a value that is not of type T.
		const count = persisted(KEY, 2, { codec: numberCodec() });
		count.set(8);
		storageEvent(KEY, null);
		expect(get(count)).toBe(2);
	});

	it('ignores an event for a different key', () => {
		const count = persisted(KEY, 0, { codec: numberCodec() });
		count.set(5);
		storageEvent('some:other:key', '999');
		expect(get(count)).toBe(5);
	});

	it('does not listen at all when sync is off', () => {
		const count = persisted(KEY, 0, { codec: numberCodec(), sync: false });
		storageEvent(KEY, '12');
		expect(get(count)).toBe(0);
	});
});

describe('persisted — session storage', () => {
	const sessionReload = (initial: number) =>
		persisted<number>(KEY, initial, { codec: numberCodec(), storage: 'session', sync: false });

	it('writes to sessionStorage, not localStorage', () => {
		const count = persisted(KEY, 0, {
			codec: numberCodec(),
			storage: 'session',
			sync: false
		});
		count.set(7);
		expect(sessionStorage.getItem(KEY)).toBe('7');
		expect(localStorage.getItem(KEY)).toBeNull();
		expect(get(sessionReload(0))).toBe(7);
	});

	it('does not adopt a localStorage value under the same key', () => {
		// The kiosk bug: wantsRun lived in localStorage, so a past Start resurrected
		// the runner on every later visit. Session stores must ignore that ghost.
		localStorage.setItem(KEY, '1');
		expect(get(sessionReload(0))).toBe(0);
	});
});

describe('reset', () => {
	it('returns the store to its initial value and persists that', () => {
		const count = persisted(KEY, 0, { codec: numberCodec() });
		count.set(9);

		reset(count, 0);

		expect(get(count)).toBe(0);
		// Documented behaviour: reset does NOT leave the key absent — the store's own
		// subscriber mirrors the reset value straight back out.
		expect(localStorage.getItem(KEY)).toBe('0');
		expect(get(reload(0, numberCodec()))).toBe(0);
	});
});
