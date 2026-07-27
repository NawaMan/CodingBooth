import { writable, type Writable } from 'svelte/store';
import { browser } from '$app/environment';
import { type Codec, jsonCodec } from '$lib/utils/stateCore';

/*
  persisted() — a Svelte store that remembers, across a reload and across tabs.

  Every persisted store in this deck used to hand-roll the same four steps, and
  each one got a slightly different subset right. displayMode.ts,
  diagramScroll.ts and adjustMode.ts have since moved onto this factory, and are
  now the worked examples rather than the cautionary tale — but the four steps
  are why it exists:

    1. Read the key — but ONLY in the browser. During prerender there is no
       `localStorage`, and touching it is not a degraded render, it is a build
       that fails.
    2. Distrust what you read. The value was written by another tab, or by an
       older version of this deck, or by half a write that a crash interrupted.
       `diagramScroll.ts` used to do `parseInt(stored)` with no guard, so one
       corrupt byte made the store `NaN` and the diagram laid out at `NaNpx`.
    3. Write on change — inside a try/catch. `setItem` THROWS in Safari's private
       mode and when the quota is full. An uncaught throw in a store subscriber
       takes the slide down, and a deck that dies because it could not save a
       zoom level has its priorities backwards.
    4. Listen for other tabs. The presenter console is a second window onto the
       same deck; without the `storage` event it drifts out of sync.

  So it lives here once, and the parse/serialize half of it lives in
  utils/stateCore.ts, where it is pure and directly testable.

  THE SSR CONTRACT, which is the part authors get wrong: on the server this is an
  ordinary `writable(initial)` and nothing else. No `window`, no `localStorage`,
  no listener. So the prerendered HTML always shows `initial` — never a
  browser-specific value, which would be wrong for every OTHER visitor anyway,
  since the prerender happens once at build time and is served to everyone. The
  remembered value arrives on hydration, one tick after the page paints.
*/

/** Which Web Storage bucket to use. `local` survives browser restarts;
    `session` survives full-page navigations in the same tab but clears when the
    tab closes — right for "keep running across slide loads, not across visits". */
export type PersistedStorage = 'local' | 'session';

/** Options for a persisted store. */
export interface PersistedOptions<T> {
	/** How the value is turned into a string and back. Defaults to JSON. */
	codec?: Codec<T>;
	/** Mirror writes from other tabs/windows into this store. Default `true`.
	    Only meaningful for `storage: 'local'` (sessionStorage is per-tab). */
	sync?: boolean;
	/** `local` (default) or `session`. */
	storage?: PersistedStorage;
}

/** A `writable` mirrored to Web Storage under `key` (localStorage by default).

    On the server (and if anything at all goes wrong in the browser) it degrades to a
    plain in-memory writable holding `initial` — a deck that cannot persist still runs;
    it just forgets. That is the correct failure mode for a presentation, which must
    never refuse to show a slide because storage was unavailable. */
export function persisted<T>(key: string, initial: T, options: PersistedOptions<T> = {}): Writable<T> {
	const codec = options.codec ?? jsonCodec<T>();
	const sync = options.sync !== false;
	const storageKind: PersistedStorage = options.storage === 'session' ? 'session' : 'local';

	const store = writable<T>(load(key, initial, codec, storageKind));

	if (!browser) return store;

	// Mirror every change out to storage. Best-effort: a full quota or a private-mode
	// window must not take the slide down, so the throw is swallowed and the store keeps
	// working in memory.
	store.subscribe((value) => {
		try {
			webStorage(storageKind)?.setItem(key, codec.write(value));
		} catch {
			/* storage unavailable or full — the deck runs anyway, it just forgets */
		}
	});

	// Cross-tab sync only applies to localStorage. sessionStorage is tab-private and
	// the `storage` event never carries another tab's session writes to us.
	if (sync && storageKind === 'local') {
		window.addEventListener('storage', (event: StorageEvent) => {
			if (event.key !== key) return;
			// `newValue === null` is the key being REMOVED (another tab cleared it, or the
			// user wiped site data). Fall back to `initial` rather than to `null`, which is
			// very likely not of type T and would poison every subscriber downstream.
			if (event.newValue === null) {
				store.set(initial);
				return;
			}
			const parsed = codec.read(event.newValue);
			// Garbage from another tab is ignored outright: keeping the value we already
			// have is strictly better than adopting one we know is broken.
			if (parsed !== null) store.set(parsed);
		});
	}

	return store;
}

function webStorage(kind: PersistedStorage): Storage | null {
	if (!browser) return null;
	try {
		return kind === 'session' ? sessionStorage : localStorage;
	} catch {
		return null;
	}
}

/** Read the key once, at construction. Every failure — no browser, no key, a codec that
    refuses the string, a `getItem` that throws behind a storage policy — lands on
    `initial`, so this function is total and the store always starts with a usable value. */
function load<T>(key: string, initial: T, codec: Codec<T>, storageKind: PersistedStorage): T {
	if (!browser) return initial;
	try {
		const raw = webStorage(storageKind)?.getItem(key) ?? null;
		if (raw === null) return initial;
		const parsed = codec.read(raw);
		return parsed === null ? initial : parsed;
	} catch {
		return initial;
	}
}

/** Reset a persisted store to its initial value — the demo slide's RESET.

    This deliberately does NOT remove the key. A `removeItem` here would be undone
    immediately by our own subscriber, which mirrors the very next value straight back to
    storage; the key would be absent for one tick and then reappear holding `initial`.
    Rather than fight that, `reset` means what a visitor means by it: back to the default.
    The end state — key present, holding `initial` — is identical either way, and this
    version doesn't lie about how it got there. */
export function reset<T>(store: Writable<T>, initial: T): void {
	store.set(initial);
}
