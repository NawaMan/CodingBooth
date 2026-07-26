import { render, screen, cleanup, fireEvent } from '@testing-library/svelte';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { readable } from 'svelte/store';
import AppendixHost from './AppendixHost.svelte';

// AppendixPage — the slide you jump INTO and return FROM, and which behaves like a
// real book's appendix: a CHAPTER of contiguous hidden slides you page through, whose
// edges lead back to the slide that called it. So the three things under test are that
// it pages like the deck, that walking forward off the end RETURNS (no new gesture),
// and that it never strands you when there is no caller.

// The URL is the whole input, so the test drives it: a mutable holder the $page mock
// reads, set by each test before it renders.
let url = new URL('http://localhost/slides/detail.html');

vi.mock('$app/stores', () => ({
	page: {
		subscribe: (run: (v: { url: URL }) => void) => readable({ url }).subscribe(run)
	},
	navigating: readable(null),
	updated: readable(false)
}));

// Every way out pages through deckNav — the same helper the NavigationBar uses, so a
// View-Transition deck animates out of an appendix as it animates between slides. Spy
// on that seam rather than on window.location, which jsdom cannot navigate anyway.
const navigate = vi.fn();
vi.mock('$lib/utils/deckNav', () => ({ navigate: (...args: unknown[]) => navigate(...args) }));

beforeEach(() => {
	navigate.mockClear();
	url = new URL('http://localhost/slides/detail.html');
});
afterEach(() => cleanup());

/** Put the appendix at `slide`, called (or not) from `?return=`. */
const at = (slide: string, search = '') => {
	url = new URL(`http://localhost/slides/${slide}${search}`);
};
const click = (name: RegExp) => fireEvent.click(screen.getByRole('button', { name }));
const wentTo = (href: string) => expect(navigate).toHaveBeenCalledWith(href, expect.anything());

describe('AppendixPage — an appendix is a chapter, and pages like one', () => {
	it('pages on to the next slide of the appendix, carrying the return address', () => {
		at('detail.html', '?return=caller.html');
		render(AppendixHost);

		click(/^NEXT\b/i);
		wentTo('./detail-2.html?return=caller.html');
	});

	// The heart of it: the last slide's NEXT is the way OUT. Because the NavigationBar
	// drives → and Space from the same link, the ordinary forward march returns from an
	// appendix — there is no separate gesture to teach.
	it('paging forward off the END of the appendix returns to the caller', () => {
		at('detail-2.html', '?return=caller.html');
		render(AppendixHost);

		click(/^NEXT\b/i);
		wentTo('./caller.html');
	});

	it('→ and Space do the same, since they are the same navigation', async () => {
		at('detail-2.html', '?return=caller.html');
		render(AppendixHost);

		await fireEvent.keyDown(window, { key: 'ArrowRight' });
		wentTo('./caller.html');

		navigate.mockClear();
		await fireEvent.keyDown(window, { key: ' ' });
		wentTo('./caller.html');
	});

	it('paging back off the FRONT of the appendix leaves it the way it was entered', () => {
		at('detail.html', '?return=caller.html');
		render(AppendixHost);

		click(/^PREV\b/i);
		wentTo('./caller.html');
	});

	// FIRST/LAST bound to the appendix, not the deck: jumping to the deck's last slide
	// from inside a chapter would land the audience somewhere the talk has not reached.
	it('FIRST and LAST stay within the appendix', () => {
		at('detail-2.html', '?return=caller.html');
		render(AppendixHost);

		click(/^FIRST\b/i);
		wentTo('./detail.html?return=caller.html');
	});

	// The deck's own slides are not the appendix's business: paging within the run must
	// never step into `thanks.html`, the slide that happens to follow it in pages.ts.
	it('never pages into the deck that surrounds it', () => {
		at('detail-2.html', '?return=caller.html');
		render(AppendixHost);

		click(/^NEXT\b/i);
		expect(navigate).not.toHaveBeenCalledWith('./thanks.html', expect.anything());
	});
});

describe('AppendixPage — RETURN, the shortcut out of the middle', () => {
	it('offers RETURN when the URL names the slide that called it', () => {
		at('detail.html', '?return=caller.html');
		render(AppendixHost);

		expect(screen.getByRole('button', { name: /RETURN/i })).toBeTruthy();
		expect(screen.queryByRole('button', { name: /DECK/i })).toBeNull();
	});

	it('RETURN goes back to the caller, backwards', () => {
		at('detail.html', '?return=caller.html');
		render(AppendixHost);

		click(/RETURN/i);
		expect(navigate).toHaveBeenCalledTimes(1);
		expect(navigate.mock.calls[0][0]).toBe('./caller.html');
		expect(navigate.mock.calls[0][1]).toMatchObject({ direction: 'back' });
	});

	// Prominent, not `chrome`: the muted chrome look is for machinery a speaker already
	// knows is there. This is the one control on the slide that must be findable at a
	// glance, mid-talk, with an audience watching.
	it('is a prominent control, not muted chrome like the pager', () => {
		at('detail.html', '?return=caller.html');
		render(AppendixHost);

		expect(screen.getByRole('button', { name: /RETURN/i }).classList.contains('chrome')).toBe(false);
		expect(screen.getByRole('button', { name: /^NEXT\b/i }).classList.contains('chrome')).toBe(true);
	});

	it('Backspace does what RETURN does', async () => {
		at('detail.html', '?return=caller.html');
		render(AppendixHost);

		await fireEvent.keyDown(window, { key: 'Backspace' });
		wentTo('./caller.html');
	});

	// ↑ is where leaving GOES — the same direction the animation travels, so the key and
	// the motion say one thing. It is free to mean that because ←/→ page the deck and the
	// vertical axis is otherwise unbound; a caller binds ↓ to jump in (appendix-page.html).
	it('↑ leaves the appendix, the way the motion travels', async () => {
		at('detail.html', '?return=caller.html');
		render(AppendixHost);

		await fireEvent.keyDown(window, { key: 'ArrowUp' });
		wentTo('./caller.html');
	});

	// Deep in the appendix, ↑ still leaves outright rather than stepping back a page —
	// stepping is what ← is for.
	it('↑ leaves from the middle, it does not step back', async () => {
		at('detail-2.html', '?return=caller.html');
		render(AppendixHost);

		await fireEvent.keyDown(window, { key: 'ArrowUp' });
		wentTo('./caller.html');
		expect(navigate).not.toHaveBeenCalledWith('./detail.html?return=caller.html', expect.anything());
	});

	// A key that navigates must not fire while someone is typing (a Draw label, a filter
	// box). Backspace there means "delete a character".
	it('Backspace while typing is left alone', async () => {
		at('detail.html', '?return=caller.html');
		render(AppendixHost);

		const input = document.createElement('input');
		document.body.appendChild(input);
		await fireEvent.keyDown(input, { key: 'Backspace' });
		expect(navigate).not.toHaveBeenCalled();
	});
});

describe('AppendixPage — when there is nobody to return to', () => {
	// The one thing an appendix must never do is strand you: it is off the linear order,
	// so with no way out the only escape would be the browser's Back button.
	it('degrades to DECK on a direct link, going to the first slide', () => {
		at('detail.html');
		render(AppendixHost);

		expect(screen.queryByRole('button', { name: /RETURN/i })).toBeNull();
		click(/DECK/i);
		wentTo('./title.html');
	});

	it('and the run still leads out — off the end is the deck', () => {
		at('detail-2.html');
		render(AppendixHost);

		click(/^NEXT\b/i);
		wentTo('./title.html');
	});

	it('refuses a return address that would leave the deck', () => {
		at('detail.html', '?return=https://evil.example');
		render(AppendixHost);

		expect(screen.queryByRole('button', { name: /RETURN/i })).toBeNull();
		expect(screen.getByRole('button', { name: /DECK/i })).toBeTruthy();
	});

	// Passes the syntax check but names no slide in THIS deck — following it would land
	// on a 404, so it is treated as no address at all.
	it('refuses a return address that names no slide in the deck', () => {
		at('detail.html', '?return=ghost.html');
		render(AppendixHost);

		expect(screen.getByRole('button', { name: /DECK/i })).toBeTruthy();
	});

	it('the DECK fallback skips a hidden first slide', () => {
		at('detail.html');
		render(AppendixHost, {
			props: {
				pages: [
					{ path: 'detail.html', title: 'Secret', hidden: true },
					{ path: 'real.html',   title: 'Real' }
				]
			}
		});
		click(/DECK/i);
		wentTo('./real.html');
	});
});

describe('AppendixPage — an appendix in the deck’s normal flow', () => {
	// `hidden` is optional. Without it the appendix is back matter you can simply page
	// into, like a book's: the DECK's own navigation applies...
	const inFlow = [
		{ path: 'title.html',  title: 'Title' },
		{ path: 'caller.html', title: 'Caller' },
		{ path: 'detail.html', title: 'Detail' },   // an appendix, but not hidden
		{ path: 'thanks.html', title: 'Thanks' }
	];

	it('pages with the deck, not out of it', () => {
		at('detail.html', '?return=caller.html');
		render(AppendixHost, { props: { pages: inFlow } });

		click(/^NEXT\b/i);
		// ...on to the next slide of the DECK — carrying the return address, so a caller
		// that jumped in can still be returned to from further along.
		wentTo('./thanks.html?return=caller.html');
	});

	it('still offers RETURN to a caller that jumped in', () => {
		at('detail.html', '?return=caller.html');
		render(AppendixHost, { props: { pages: inFlow } });

		click(/RETURN/i);
		wentTo('./caller.html');
	});

	// Reached by ordinary paging, with nobody having called it, it is simply a slide —
	// so it gets no extra control cluttering the bar.
	it('is just a slide when nobody called it', () => {
		at('detail.html');
		render(AppendixHost, { props: { pages: inFlow } });

		expect(screen.queryByRole('button', { name: /RETURN/i })).toBeNull();
		expect(screen.queryByRole('button', { name: /DECK/i })).toBeNull();
	});
});

// The animation is a sentence: going in, the deck slides DOWN and the appendix drops
// in from above; leaving, it lifts back UP. So the vertical axis means "we stepped out
// of the talk" and nothing else — which is why paging WITHIN the appendix stays
// sideways, and why every way OUT lifts, whichever control performed it.
describe('AppendixPage — the motion of a detour (transition)', () => {
	const kindOf = () => navigate.mock.calls[0][1] as { kind: string; viewTransitions: boolean };

	it('lifts away when paging off the end of the appendix', () => {
		at('detail-2.html', '?return=caller.html');
		render(AppendixHost, { props: { transition: true } });

		click(/^NEXT\b/i);
		expect(kindOf().kind).toBe('appendix-out');
		expect(kindOf().viewTransitions).toBe(true);
	});

	it('lifts away for RETURN too — the same gesture, not a different one', () => {
		at('detail.html', '?return=caller.html');
		render(AppendixHost, { props: { transition: true } });

		click(/RETURN/i);
		expect(kindOf().kind).toBe('appendix-out');
	});

	it('steps sideways within the appendix — that is reading, not travelling', () => {
		at('detail.html', '?return=caller.html');
		render(AppendixHost, { props: { transition: true } });

		click(/^NEXT\b/i);
		expect(kindOf().kind).toBe('appendix-step');
	});

	// Off by default, and deliberately so: an animated navigation must be client-side,
	// and Monaco (ViewSource/Code/CodeBox) does not survive one. A deck opts in and uses
	// SourceView on the slides it animates between.
	it('is off by default — the deck keeps paging with honest full loads', () => {
		at('detail.html', '?return=caller.html');
		render(AppendixHost);

		click(/RETURN/i);
		expect(kindOf().viewTransitions).toBe(false);
	});

	// An IN-FLOW appendix (not hidden) is part of the deck, so its NEXT leads into the
	// deck — slides that know nothing about any of this and may well render a Monaco
	// CodeBox. Animating THAT would blank them. So the bar keeps the deck's full loads
	// and only the way out — which goes to the caller and nowhere else — animates.
	describe('an in-flow appendix animates its exit, but not the deck', () => {
		const inFlow = [
			{ path: 'title.html',  title: 'Title' },
			{ path: 'caller.html', title: 'Caller' },
			{ path: 'detail.html', title: 'Detail' },   // an appendix, but in the march
			{ path: 'thanks.html', title: 'Thanks' }
		];

		it('does not drag the deck into a client-side navigation', () => {
			at('detail.html', '?return=caller.html');
			render(AppendixHost, { props: { pages: inFlow, transition: true } });

			click(/^NEXT\b/i);
			expect(navigate.mock.calls[0][0]).toBe('./thanks.html?return=caller.html');
			expect(kindOf().viewTransitions).toBe(false);
		});

		it('but RETURN still travels back up to the caller', () => {
			at('detail.html', '?return=caller.html');
			render(AppendixHost, { props: { pages: inFlow, transition: true } });

			click(/RETURN/i);
			expect(kindOf().viewTransitions).toBe(true);
			expect(kindOf().kind).toBe('appendix-out');
		});
	});
});

describe('AppendixPage — otherwise an ordinary slide', () => {
	it('renders its header and content', () => {
		render(AppendixHost, { props: { title: 'How the GC marks' } });
		expect(screen.getByText('How the GC marks')).toBeTruthy();
		expect(screen.getByTestId('body').textContent).toBe('The long version.');
	});
});
