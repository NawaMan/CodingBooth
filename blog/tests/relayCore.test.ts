// relayCore — who may drive whom on the cross-window current-slide channel.
//
// The bug this file guards: the relay was a BROADCAST. Every top-level window of a
// deck both announced its slide and followed anyone else's, so two ordinary tabs of
// one deck locked each other in step — paging in either yanked the other. The
// channel knew "which deck" (deckKey) but not "which role", and the console↔audience
// pair it was built for is a RELATIONSHIP, not a broadcast.
//
// The asymmetry below is the fix, and every "ignores" case is the regression.
import { describe, expect, it } from 'vitest';
import {
	asRole,
	followTarget,
	mayFollow,
	parseAnnouncement,
	roleOf
} from '$lib/utils/relayCore';

describe('roleOf', () => {
	it('reads the ?present flag as the console role', () => {
		expect(roleOf(true)).toBe('present');
		expect(roleOf(false)).toBe('audience');
	});
});

describe('asRole', () => {
	it('takes only the exact string "present" as the console', () => {
		expect(asRole('present')).toBe('present');
		expect(asRole('audience')).toBe('audience');
	});

	it('reads an UNTAGGED payload as audience — the compatibility hinge', () => {
		// An older build of the deck, left open in a tab, announces {path, ts} with no
		// role at all. Audience is what every window was before roles existed, so a
		// stale tab keeps its old meaning against a new one instead of falling silent.
		expect(asRole(undefined)).toBe('audience');
		expect(asRole(null)).toBe('audience');
	});

	it('never invents a third role from junk', () => {
		// A role that matched nothing would make a window unfollowable; one that
		// matched everything would restore the bug. Junk must land on a real role.
		for (const junk of ['PRESENT', 'Present', '', 0, 1, {}, [], NaN, true]) {
			expect(asRole(junk)).toBe('audience');
		}
	});
});

describe('parseAnnouncement', () => {
	it('reads a well-formed tagged payload', () => {
		expect(parseAnnouncement('{"path":"intro.html","ts":1,"role":"present"}')).toEqual({
			path: 'intro.html',
			role: 'present'
		});
	});

	it('defaults an untagged payload to audience', () => {
		expect(parseAnnouncement('{"path":"intro.html","ts":1}')).toEqual({
			path: 'intro.html',
			role: 'audience'
		});
	});

	it('returns null rather than throwing on anything malformed', () => {
		// The payload comes from ANOTHER window; it is never to be trusted. A throw
		// here would kill the storage listener and silently end all syncing.
		for (const bad of [
			null,
			undefined,
			'',
			'not json',
			'{"path":', // half-written
			'null',
			'42',
			'"a string"',
			'[]',
			'{}', // no path
			'{"path":""}', // blank path
			'{"path":123}', // non-string path
			'{"ts":5}'
		]) {
			expect(parseAnnouncement(bad as string)).toBeNull();
		}
	});
});

describe('mayFollow — the rule the whole fix rests on', () => {
	it('lets the console and the audience drive each other', () => {
		expect(mayFollow('present', 'audience')).toBe(true);
		expect(mayFollow('audience', 'present')).toBe(true);
	});

	it('makes two audience tabs IGNORE each other — the reported bug', () => {
		expect(mayFollow('audience', 'audience')).toBe(false);
	});

	it('makes two consoles ignore each other too', () => {
		// Falls out of "roles must differ" for free rather than needing its own case.
		expect(mayFollow('present', 'present')).toBe(false);
	});

	it('treats an untagged sender as an audience window', () => {
		expect(mayFollow(undefined, 'audience')).toBe(false); // two old-style tabs: still ignore
		expect(mayFollow(undefined, 'present')).toBe(true); // a console may still be driven
	});
});

describe('followTarget — the whole per-payload decision', () => {
	const from = (role: string, path = 'two.html') =>
		JSON.stringify({ path, ts: 1, role });

	it('returns the path when a console drives an audience window', () => {
		expect(followTarget(from('present'), 'audience', 'one.html')).toBe('two.html');
	});

	it('returns null when the sender shares our role', () => {
		expect(followTarget(from('audience'), 'audience', 'one.html')).toBeNull();
	});

	it('returns null when we are already there — the ping-pong guard', () => {
		// B follows A, then B publishes its new slide; without this, that echo would
		// bounce A back and the two windows would trade navigations forever.
		expect(followTarget(from('present', 'one.html'), 'audience', 'one.html')).toBeNull();
	});

	it('still applies the role check when we have no current slide yet', () => {
		expect(followTarget(from('present'), 'audience', null)).toBe('two.html');
		expect(followTarget(from('audience'), 'audience', null)).toBeNull();
	});

	it('returns null on a malformed payload', () => {
		expect(followTarget('not json', 'audience', 'one.html')).toBeNull();
		expect(followTarget(null, 'present', 'one.html')).toBeNull();
	});
});
