import { describe, expect, it } from 'vitest';
import {
	consoleIsLive, CONSOLE_BEAT_MS, CONSOLE_TTL_MS
} from '../src/lib/utils/consoleLiveCore';

// A fixed "now" so the test never touches the wall clock.
const NOW = 1_000_000;

describe('consoleIsLive', () => {
	it('a fresh beat is live', () => {
		expect(consoleIsLive(NOW, NOW, CONSOLE_TTL_MS)).toBe(true);
		expect(consoleIsLive(NOW - 1_000, NOW, CONSOLE_TTL_MS)).toBe(true);
	});

	it('a beat just inside the ttl is live, just outside is stale', () => {
		expect(consoleIsLive(NOW - (CONSOLE_TTL_MS - 1), NOW, CONSOLE_TTL_MS)).toBe(true);
		expect(consoleIsLive(NOW - CONSOLE_TTL_MS, NOW, CONSOLE_TTL_MS)).toBe(false);
		expect(consoleIsLive(NOW - (CONSOLE_TTL_MS + 1), NOW, CONSOLE_TTL_MS)).toBe(false);
	});

	it('a closed console (old beat) reads stale', () => {
		expect(consoleIsLive(NOW - 60_000, NOW, CONSOLE_TTL_MS)).toBe(false);
	});

	it('no beat ever (null/undefined/0/negative) is not live', () => {
		expect(consoleIsLive(null, NOW)).toBe(false);
		expect(consoleIsLive(undefined, NOW)).toBe(false);
		expect(consoleIsLive(0, NOW)).toBe(false);
		expect(consoleIsLive(-1, NOW)).toBe(false);
	});

	it('a beat in the future (clock skew) is treated as live, never NaN-throws', () => {
		expect(consoleIsLive(NOW + 5_000, NOW, CONSOLE_TTL_MS)).toBe(true);
	});

	it('garbage never throws and never lies live', () => {
		expect(consoleIsLive(NaN, NOW)).toBe(false);
		expect(consoleIsLive(Infinity, NOW)).toBe(false);
		expect(consoleIsLive(NOW, NaN)).toBe(false);
		expect(consoleIsLive(NOW, Infinity)).toBe(false);
	});

	it('a degenerate ttl falls back to the default rather than answering everything', () => {
		// ttl NaN/0/negative → CONSOLE_TTL_MS, so a beat one default-ttl old is stale
		// and a fresh one is live regardless of the junk passed.
		expect(consoleIsLive(NOW - (CONSOLE_TTL_MS + 1), NOW, NaN)).toBe(false);
		expect(consoleIsLive(NOW, NOW, 0)).toBe(true);
		expect(consoleIsLive(NOW, NOW, -100)).toBe(true);
	});

	it('the ttl is a comfortable multiple of the beat, so one dropped beat never flickers', () => {
		expect(CONSOLE_TTL_MS).toBeGreaterThan(2 * CONSOLE_BEAT_MS);
	});
});
