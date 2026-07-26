import { afterEach, describe, expect, it, vi } from 'vitest';
import {
	deckKeyFromPath,
	publishCurrentSlide,
	subscribeCurrentSlide,
	publishAnimCommand,
	subscribeAnimCommand,
	publishContinue,
	subscribeContinue,
	publishTrigger,
	subscribeTrigger,
	presenterTimerStart,
	resetPresenterTimer,
	loadPresenterPause,
	savePresenterPause,
	loadPresenterSplit,
	savePresenterSplit,
	loadChecks,
	saveChecks,
	clearSlideChecks,
	clearDeckChecks
} from '../src/lib/stores/presenter';

// The cross-window presenter channel: publishCurrentSlide writes one namespaced
// localStorage value; subscribeCurrentSlide reacts to `storage` events (which, in
// a real browser, fire only in OTHER windows — here we synthesize them). The
// caller owns the `path !== mine` guard, so the subscriber delivers every event
// for its key, including a same-path re-broadcast.
//
// The channel is ROLE-SCOPED (utils/relayCore): an announcement is delivered only
// when its sender's role differs from the subscriber's. That is why the tests below
// pass a sender role and a receiver role rather than trusting a bare path — a
// console drives an audience window and vice versa, but two audience tabs of one
// deck must ignore each other. They used to lock-step, which was the bug.

function fireStorage(key: string | null, newValue: string | null) {
	window.dispatchEvent(new StorageEvent('storage', { key: key ?? undefined, newValue: newValue ?? undefined }));
}

afterEach(() => {
	localStorage.clear();
});

describe('deckKeyFromPath', () => {
	it('reduces a slide path to its deck prefix', () => {
		expect(deckKeyFromPath('/slides/intro.html')).toBe('/slides/');
		expect(deckKeyFromPath('/slides/intro.html/')).toBe('/slides/'); // trailing slash
		expect(deckKeyFromPath('/portrait/title.html')).toBe('/portrait/');
	});
	it('falls back to root for a top-level path', () => {
		expect(deckKeyFromPath('/intro.html')).toBe('/');
		expect(deckKeyFromPath('/')).toBe('/');
	});
});

describe('publishCurrentSlide', () => {
	it('writes the bare path under the deck-namespaced key', () => {
		publishCurrentSlide('/slides/', 'chart-bar.html');
		const raw = localStorage.getItem('geekpresent:current:/slides/');
		expect(raw).toBeTruthy();
		expect(JSON.parse(raw!).path).toBe('chart-bar.html');
	});
	it('namespaces per deck so two decks never collide', () => {
		publishCurrentSlide('/slides/', 'a.html');
		publishCurrentSlide('/portrait/', 'b.html');
		expect(JSON.parse(localStorage.getItem('geekpresent:current:/slides/')!).path).toBe('a.html');
		expect(JSON.parse(localStorage.getItem('geekpresent:current:/portrait/')!).path).toBe('b.html');
	});
	it('tags the announcement with the sender role, defaulting to audience', () => {
		// The tag is what lets the listener decide whether it may be driven at all.
		publishCurrentSlide('/slides/', 'a.html');
		expect(JSON.parse(localStorage.getItem('geekpresent:current:/slides/')!).role).toBe('audience');
		publishCurrentSlide('/slides/', 'b.html', 'present');
		expect(JSON.parse(localStorage.getItem('geekpresent:current:/slides/')!).role).toBe('present');
	});

	it('ignores an empty path', () => {
		publishCurrentSlide('/slides/', '');
		expect(localStorage.getItem('geekpresent:current:/slides/')).toBeNull();
	});
});

describe('subscribeCurrentSlide', () => {
	// A console announcing to an audience window — the pair the channel exists for.
	const fromConsole = (path: string, ts = 1) => JSON.stringify({ path, ts, role: 'present' });

	it('delivers the path from a storage event for its key', () => {
		const cb = vi.fn();
		const stop = subscribeCurrentSlide('/slides/', cb, 'audience');
		fireStorage('geekpresent:current:/slides/', fromConsole('next.html'));
		expect(cb).toHaveBeenCalledWith('next.html');
		stop();
	});

	it('ignores events for a different deck key', () => {
		const cb = vi.fn();
		const stop = subscribeCurrentSlide('/slides/', cb, 'audience');
		fireStorage('geekpresent:current:/portrait/', fromConsole('x.html'));
		expect(cb).not.toHaveBeenCalled();
		stop();
	});

	it('delivers a same-path re-broadcast (guard lives in the caller)', () => {
		// Deliberately preserved: re-selecting the current slide bumps `ts` and
		// re-announces, and that echo is how a console re-syncs a drifted audience.
		const cb = vi.fn();
		const stop = subscribeCurrentSlide('/slides/', cb, 'audience');
		fireStorage('geekpresent:current:/slides/', fromConsole('same.html', 1));
		fireStorage('geekpresent:current:/slides/', fromConsole('same.html', 2));
		expect(cb).toHaveBeenCalledTimes(2);
		stop();
	});

	it('ignores a cleared value and malformed JSON', () => {
		const cb = vi.fn();
		const stop = subscribeCurrentSlide('/slides/', cb, 'audience');
		fireStorage('geekpresent:current:/slides/', null);          // localStorage.clear()
		fireStorage('geekpresent:current:/slides/', '{not json');   // corrupt payload
		expect(cb).not.toHaveBeenCalled();
		stop();
	});

	// The role scoping — the fix for two ordinary tabs lock-stepping each other.
	it('does NOT deliver an announcement from a window of its own role', () => {
		const cb = vi.fn();
		const stop = subscribeCurrentSlide('/slides/', cb, 'audience');
		fireStorage(
			'geekpresent:current:/slides/',
			JSON.stringify({ path: 'next.html', ts: 1, role: 'audience' })
		);
		expect(cb).not.toHaveBeenCalled();
		stop();
	});

	it('drives the console from the audience window too (the pairing is mutual)', () => {
		const cb = vi.fn();
		const stop = subscribeCurrentSlide('/slides/', cb, 'present');
		fireStorage(
			'geekpresent:current:/slides/',
			JSON.stringify({ path: 'next.html', ts: 1, role: 'audience' })
		);
		expect(cb).toHaveBeenCalledWith('next.html');
		stop();
	});

	it('reads an untagged payload as audience, so an older tab still drives a console', () => {
		const cb = vi.fn();
		const stop = subscribeCurrentSlide('/slides/', cb, 'present');
		fireStorage('geekpresent:current:/slides/', JSON.stringify({ path: 'old.html', ts: 1 }));
		expect(cb).toHaveBeenCalledWith('old.html');
		stop();
	});

	it('…but two untagged audience tabs still ignore each other', () => {
		const cb = vi.fn();
		const stop = subscribeCurrentSlide('/slides/', cb, 'audience');
		fireStorage('geekpresent:current:/slides/', JSON.stringify({ path: 'old.html', ts: 1 }));
		expect(cb).not.toHaveBeenCalled();
		stop();
	});

	it('stops delivering after unsubscribe', () => {
		const cb = vi.fn();
		const stop = subscribeCurrentSlide('/slides/', cb, 'audience');
		stop();
		fireStorage('geekpresent:current:/slides/', fromConsole('after.html'));
		expect(cb).not.toHaveBeenCalled();
	});
});

describe('anim command channel', () => {
	it('publishes a command under a distinct anim key', () => {
		publishAnimCommand('/slides/', { playing: true, fraction: 0.5 });
		expect(localStorage.getItem('geekpresent:current:/slides/')).toBeNull(); // separate channel
		const raw = localStorage.getItem('geekpresent:anim:/slides/');
		expect(JSON.parse(raw!)).toMatchObject({ playing: true, fraction: 0.5 });
	});

	it('delivers a valid command to the subscriber', () => {
		const cb = vi.fn();
		const stop = subscribeAnimCommand('/slides/', cb);
		fireStorage('geekpresent:anim:/slides/', JSON.stringify({ playing: false, fraction: 0.25, ts: 1 }));
		expect(cb).toHaveBeenCalledWith({ playing: false, fraction: 0.25 });
		stop();
	});

	it('ignores wrong deck key and malformed / wrong-typed payloads', () => {
		const cb = vi.fn();
		const stop = subscribeAnimCommand('/slides/', cb);
		fireStorage('geekpresent:anim:/portrait/', JSON.stringify({ playing: true, fraction: 1, ts: 1 }));
		fireStorage('geekpresent:anim:/slides/', '{bad');
		fireStorage('geekpresent:anim:/slides/', JSON.stringify({ playing: 'yes', fraction: 'x' }));
		expect(cb).not.toHaveBeenCalled();
		stop();
	});
});

describe('continue pulse channel', () => {
	it('publishes a pulse under a distinct continue key', () => {
		publishContinue('/slides/');
		expect(localStorage.getItem('geekpresent:continue:/slides/')).toBeTruthy();
		expect(localStorage.getItem('geekpresent:current:/slides/')).toBeNull(); // separate channel
	});

	it('fires the subscriber on a pulse for its key, ignores other keys', () => {
		const cb = vi.fn();
		const stop = subscribeContinue('/slides/', cb);
		fireStorage('geekpresent:continue:/portrait/', JSON.stringify({ ts: 1 }));
		expect(cb).not.toHaveBeenCalled();
		fireStorage('geekpresent:continue:/slides/', JSON.stringify({ ts: 2 }));
		fireStorage('geekpresent:continue:/slides/', JSON.stringify({ ts: 3 }));
		expect(cb).toHaveBeenCalledTimes(2); // each press is a distinct pulse
		stop();
	});
});

describe('trigger pulse channel', () => {
	it('publishes a named pulse under a distinct trigger key', () => {
		publishTrigger('/slides/', 'save-cursor');
		expect(localStorage.getItem('geekpresent:trigger:/slides/')).toBeTruthy();
		expect(localStorage.getItem('geekpresent:continue:/slides/')).toBeNull(); // separate channel
	});

	it('ignores an empty name — nothing worth firing', () => {
		publishTrigger('/slides/', '');
		expect(localStorage.getItem('geekpresent:trigger:/slides/')).toBeNull();
	});

	it('fires the subscriber with the name on a pulse for its key, ignores other keys', () => {
		const cb = vi.fn();
		const stop = subscribeTrigger('/slides/', cb);
		fireStorage('geekpresent:trigger:/portrait/', JSON.stringify({ name: 'x', ts: 1 }));
		expect(cb).not.toHaveBeenCalled();
		fireStorage('geekpresent:trigger:/slides/', JSON.stringify({ name: 'save-cursor', ts: 2 }));
		fireStorage('geekpresent:trigger:/slides/', JSON.stringify({ name: 'save-cursor', ts: 3 }));
		expect(cb).toHaveBeenCalledTimes(2); // re-checking the same line replays it
		expect(cb).toHaveBeenNthCalledWith(1, 'save-cursor');
		stop();
	});

	it('ignores malformed / empty-name payloads without throwing', () => {
		const cb = vi.fn();
		const stop = subscribeTrigger('/slides/', cb);
		fireStorage('geekpresent:trigger:/slides/', '{bad');
		fireStorage('geekpresent:trigger:/slides/', JSON.stringify({ name: '' }));
		fireStorage('geekpresent:trigger:/slides/', JSON.stringify({ ts: 1 }));
		expect(cb).not.toHaveBeenCalled();
		stop();
	});
});

describe('durable timer', () => {
	it('persists the start and returns it unchanged on the next call (reload-proof)', () => {
		const a = presenterTimerStart('/slides/');
		expect(localStorage.getItem('geekpresent:timerStart:/slides/')).toBe(String(a));
		const b = presenterTimerStart('/slides/'); // simulate a reload re-reading the store
		expect(b).toBe(a);
	});
	it('namespaces per deck', () => {
		const a = presenterTimerStart('/slides/');
		const b = presenterTimerStart('/portrait/');
		expect(localStorage.getItem('geekpresent:timerStart:/portrait/')).toBe(String(b));
		expect(presenterTimerStart('/slides/')).toBe(a); // untouched
	});
	it('resetPresenterTimer overwrites the stored start', () => {
		presenterTimerStart('/slides/');
		const r = resetPresenterTimer('/slides/');
		expect(Number(localStorage.getItem('geekpresent:timerStart:/slides/'))).toBe(r);
	});
	it('resetPresenterTimer accepts an explicit start (Time set) and persists it', () => {
		const start = 1_000_000; // a fixed epoch — SET the elapsed by back-dating
		const r = resetPresenterTimer('/slides/', start);
		expect(r).toBe(start);
		expect(Number(localStorage.getItem('geekpresent:timerStart:/slides/'))).toBe(start);
		expect(presenterTimerStart('/slides/')).toBe(start); // reload resumes from it
	});
});

describe('durable pause', () => {
	it('defaults to running (null) and round-trips a pause epoch', () => {
		expect(loadPresenterPause('/slides/')).toBeNull();
		savePresenterPause('/slides/', 123456);
		expect(loadPresenterPause('/slides/')).toBe(123456); // reload resumes paused
	});
	it('clearing with null removes the key (back to running)', () => {
		savePresenterPause('/slides/', 999);
		savePresenterPause('/slides/', null);
		expect(loadPresenterPause('/slides/')).toBeNull();
		expect(localStorage.getItem('geekpresent:timerPaused:/slides/')).toBeNull();
	});
});

describe('durable split', () => {
	it('round-trips a valid fraction, rejects out-of-range / unset', () => {
		expect(loadPresenterSplit()).toBeNull();
		savePresenterSplit(0.4);
		expect(loadPresenterSplit()).toBe(0.4);
		savePresenterSplit(1.5); // out of (0,1)
		expect(loadPresenterSplit()).toBeNull();
	});
});

describe('note check-off persistence', () => {
	it('round-trips per deck+slide, and drops the key when nothing is checked', () => {
		expect(loadChecks('/slides/', 'a.html')).toEqual([]);
		saveChecks('/slides/', 'a.html', [true, false, true]);
		expect(loadChecks('/slides/', 'a.html')).toEqual([true, false, true]);
		expect(loadChecks('/slides/', 'b.html')).toEqual([]); // isolated per slide
		saveChecks('/slides/', 'a.html', [false, false]); // all unchecked → removed
		expect(localStorage.getItem('geekpresent:checks:/slides/:a.html')).toBeNull();
	});
	it('clearSlideChecks clears one page; clearDeckChecks clears the whole deck', () => {
		saveChecks('/slides/', 'a.html', [true]);
		saveChecks('/slides/', 'b.html', [true]);
		saveChecks('/portrait/', 'c.html', [true]);
		clearSlideChecks('/slides/', 'a.html');
		expect(loadChecks('/slides/', 'a.html')).toEqual([]);
		expect(loadChecks('/slides/', 'b.html')).toEqual([true]); // sibling untouched
		clearDeckChecks('/slides/');
		expect(loadChecks('/slides/', 'b.html')).toEqual([]);      // whole deck gone
		expect(loadChecks('/portrait/', 'c.html')).toEqual([true]); // other deck untouched
	});
});
