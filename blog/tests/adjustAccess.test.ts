import { describe, expect, it } from 'vitest';
import { readSticky, readAdjustParam, resolveCanAdjust } from '$lib/adjust/adjustAccessCore';

// The pure precedence layer behind the ADJUST control (stores/adjustMode wires it
// to localStorage, the URL, and SlideDeck's `adjust` prop). Everything here is
// total: a corrupt localStorage value, a URL with no query, a bare `?adjust` with
// no value — each has one defined answer, so the store never has to guess.

const q = (s: string) => new URL(`http://x/slide.html${s}`).searchParams;

describe('readSticky — the recorded choice', () => {
	it('reads the two strings the store writes', () => {
		expect(readSticky('true')).toBe(true);
		expect(readSticky('false')).toBe(false);
	});

	it('treats absent as "no choice", not as false', () => {
		expect(readSticky(null)).toBe(null);
		expect(readSticky(undefined)).toBe(null);
	});

	// The distinction that matters: garbage must fall THROUGH to the deck default,
	// not veto it. Mapping it to false would let one bad byte silently hide a demo
	// deck's ADJUST button with nothing to point at.
	it('treats garbage as "no choice", so it cannot veto the deck default', () => {
		for (const junk of ['', 'TRUE', 'yes', '1', '{}', 'undefined'])
			expect(readSticky(junk)).toBe(null);
	});
});

describe('readAdjustParam — the URL flag', () => {
	it('enables on a bare ?adjust, and on the affirmative spellings', () => {
		expect(readAdjustParam(q('?adjust'))).toBe(true);
		expect(readAdjustParam(q('?adjust=on'))).toBe(true);
		expect(readAdjustParam(q('?adjust=1'))).toBe(true);
	});

	it('disables on off / false / 0, case- and space-insensitively', () => {
		expect(readAdjustParam(q('?adjust=off'))).toBe(false);
		expect(readAdjustParam(q('?adjust=false'))).toBe(false);
		expect(readAdjustParam(q('?adjust=0'))).toBe(false);
		expect(readAdjustParam(q('?adjust=OFF'))).toBe(false);
		expect(readAdjustParam(q('?adjust=%20off%20'))).toBe(false);
	});

	// A slide reached by clicking NEXT carries no query — that URL says nothing
	// about ADJUST and must leave the speaker's earlier choice standing.
	it('says nothing when the flag is absent, so it never overwrites a stored choice', () => {
		expect(readAdjustParam(q(''))).toBe(null);
		expect(readAdjustParam(q('?present&clean'))).toBe(null);
		expect(readAdjustParam(null)).toBe(null);
		expect(readAdjustParam(undefined)).toBe(null);
	});
});

describe('resolveCanAdjust — precedence', () => {
	it('dev always offers ADJUST, whatever anyone else says', () => {
		expect(resolveCanAdjust(true, false, false)).toBe(true);
		expect(resolveCanAdjust(true, null, false)).toBe(true);
	});

	// The headline guarantee: an ordinary slide in a built site is ADJUST-free. This is
	// the case the DOM tests structurally cannot reach (vitest runs with DEV=true), so
	// it is pinned here or nowhere.
	it('a built, undeclared slide is OFF — a published deck shows no authoring chrome', () => {
		expect(resolveCanAdjust(false, null, false)).toBe(false);
	});

	it('a slide that declares adjust offers the control in a BUILD (this is the demo flag)', () => {
		expect(resolveCanAdjust(false, null, true)).toBe(true);
	});

	// The speaker asked, so the speaker wins — both ways round. `?adjust` lights up an
	// ordinary slide; `?adjust=off` hushes a demo slide for a straight run-through.
	it("the speaker's sticky choice outranks what the slide declares", () => {
		expect(resolveCanAdjust(false, true, false)).toBe(true);
		expect(resolveCanAdjust(false, false, true)).toBe(false);
	});
});
