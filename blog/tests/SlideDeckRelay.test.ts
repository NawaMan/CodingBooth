// The cross-window slide relay, AT THE CALL SITES — which is the only place the bug
// ever lived.
//
// tests/presenter.test.ts exercises the channel primitives in isolation, where
// publish/subscribe symmetry is correct by design: a channel should relay what it is
// given. The lock-step bug was not in the channel. It was in SlideDeck wiring itself
// to both ends of that channel unconditionally, so every top-level window announced
// its slide AND followed everyone else's, and two ordinary tabs of one deck dragged
// each other around. Nothing at the store layer could have caught that, and nothing
// tested this layer at all.
//
// So these tests mount real decks and assert the two halves of the wiring:
//   1. what a deck WRITES carries its own role, and
//   2. what a deck DOES on an incoming announcement depends on the sender's role.
import { render } from '@testing-library/svelte';
import { tick } from 'svelte';
import { afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import Host from './SlideDeckRelayHost.svelte';
import { setPageUrl, resetPageUrl } from './stubs/app-stores';
import { gotoCalls, resetGoto } from './stubs/app-navigation';

const pages = [
	{ path: 'one.html', title: 'One' },
	{ path: 'two.html', title: 'Two' }
];

const KEY = 'geekpresent:current:/slides/';

async function mount(query = '', slide = 'one.html') {
	setPageUrl(`/slides/${slide}${query}`);
	const { container } = render(Host, { props: { pages } });
	await tick();
	await tick(); // onMount → initialized → the relay subscription is live
	return container;
}

/** Synthesize the storage event another window's write would raise. (A real browser
    never fires `storage` in the window that wrote it — hence the manual dispatch.) */
function announce(role: string | undefined, path = 'two.html') {
	const payload: Record<string, unknown> = { path, ts: 1 };
	if (role !== undefined) payload.role = role;
	window.dispatchEvent(
		new StorageEvent('storage', { key: KEY, newValue: JSON.stringify(payload) })
	);
}

beforeAll(() => {
	// The ?present branch mounts PresenterView, which observes its preview box.
	// jsdom ships no ResizeObserver, and nothing here depends on a measurement —
	// the relay is about which slide, not what size — so an inert stub is enough.
	if (!('ResizeObserver' in globalThis)) {
		(globalThis as { ResizeObserver?: unknown }).ResizeObserver = class {
			observe() {}
			unobserve() {}
			disconnect() {}
		};
	}
	// Likewise PresenterAnim collects the slide's animations (utils/slideAnim). jsdom
	// has no Web Animations, so report none — this deck's stub slide has none anyway.
	const none = () => [] as Animation[];
	(Element.prototype as unknown as { getAnimations: () => Animation[] }).getAnimations = none;
	(Document.prototype as unknown as { getAnimations: () => Animation[] }).getAnimations = none;
});

beforeEach(resetGoto);
afterEach(() => {
	resetPageUrl();
	localStorage.clear();
});

describe('what a deck announces', () => {
	it('an ordinary deck window tags itself audience', async () => {
		await mount();
		const raw = localStorage.getItem(KEY);
		expect(raw).toBeTruthy();
		expect(JSON.parse(raw!)).toMatchObject({ path: 'one.html', role: 'audience' });
	});

	it('a ?present console tags itself present', async () => {
		// This is the assertion that proves SlideDeck passes its OWN role through, rather
		// than a constant that happens to read correctly in the audience case.
		await mount('?present');
		expect(JSON.parse(localStorage.getItem(KEY)!)).toMatchObject({ role: 'present' });
	});
});

describe('what a deck follows', () => {
	it('an audience window follows the console', async () => {
		await mount();
		announce('present');
		await tick();
		expect(gotoCalls).toEqual(['./two.html']);
	});

	it('an audience window IGNORES another audience tab — the reported bug', async () => {
		// Two ordinary tabs of one deck. Before the fix this navigated, which is exactly
		// the surprise: paging in one tab yanked the other onto its slide.
		await mount();
		announce('audience');
		await tick();
		expect(gotoCalls).toEqual([]);
	});

	it('…and ignores an untagged announcement, which reads as audience', async () => {
		// An older build of the deck left open in another tab announces {path, ts} with
		// no role. Audience is what every window was before roles existed.
		await mount();
		announce(undefined);
		await tick();
		expect(gotoCalls).toEqual([]);
	});

	it('the console follows the audience, keeping its ?present flag', async () => {
		await mount('?present');
		announce('audience');
		await tick();
		expect(gotoCalls).toEqual(['./two.html?present']);
	});

	it('two consoles ignore each other', async () => {
		await mount('?present');
		announce('present');
		await tick();
		expect(gotoCalls).toEqual([]);
	});

	it('nobody follows an announcement for the slide already showing', async () => {
		// The ping-pong guard: B follows A, then B announces its new slide, and that echo
		// must not bounce A back. Role scoping does not replace this — it is orthogonal.
		await mount();
		announce('present', 'one.html');
		await tick();
		expect(gotoCalls).toEqual([]);
	});

	it('ignores an announcement from a different deck', async () => {
		// deckKey answers "which deck?"; the role answers "who may drive whom?". Both gates
		// still apply, so a /portrait/ console never moves a /slides/ window.
		await mount();
		window.dispatchEvent(
			new StorageEvent('storage', {
				key: 'geekpresent:current:/portrait/',
				newValue: JSON.stringify({ path: 'two.html', ts: 1, role: 'present' })
			})
		);
		await tick();
		expect(gotoCalls).toEqual([]);
	});
});
