// relayCore — WHO may drive WHOM on the current-slide channel, decided purely.
//
// The cross-window slide relay (stores/presenter.publishCurrentSlide /
// subscribeCurrentSlide) was built for ONE relationship: the ?present console and
// its audience window should show the same slide. But it was implemented as a
// BROADCAST — every top-level window of a deck both announces and follows — so two
// ordinary audience tabs of the same deck locked each other in step. `deckKey`
// already namespaces the channel per deck ("which deck?"); the missing axis is
// "which ROLE?", and that is what this file adds.
//
// The rule is one line: a window follows an announcement only when the sender's
// role DIFFERS from its own. Console ↔ audience cross-drive (the pair the feature
// exists for); audience ↔ audience ignore each other (the bug); console ↔ console
// ignore each other too, which falls out for free rather than needing its own case.
//
// Pure, total and NaN-safe in the consoleLiveCore/drawCore tradition: garbage in
// yields a defined verdict, never a throw. That matters more than usual here,
// because the payload arrives from ANOTHER window — possibly an older build of the
// deck left open in a tab, whose announcements carry no role at all. An untagged
// payload is read as 'audience', which is what every window was before this file
// existed, so a stale tab degrades to the old behaviour against a new one instead
// of falling silent.

/** Which kind of window announced (or is hearing) a slide change. 'present' is a
    ?present presenter console; 'audience' is an ordinary deck window. */
export type RelayRole = 'present' | 'audience';

/** The parsed form of a current-slide announcement. `role` is always resolved —
    never undefined — so callers compare two known values, not one known and one
    maybe. */
export interface Announcement {
	path: string;
	role: RelayRole;
}

/** The role a window plays, from its `?present` flag. Trivial, but named so the
    two call sites in SlideDeck can't disagree about which boolean means what. */
export function roleOf(present: boolean): RelayRole {
	return present ? 'present' : 'audience';
}

/**
 * Normalise anything into a RelayRole.
 *
 * Only the exact string 'present' counts as the console. Everything else —
 * 'audience', undefined (an older build's untagged payload), null, a number, an
 * object — reads 'audience'. See the header: untagged must mean audience, because
 * that is what every window was before roles existed.
 */
export function asRole(value: unknown): RelayRole {
	return value === 'present' ? 'present' : 'audience';
}

/**
 * Parse a raw announcement payload (the JSON string read off localStorage).
 *
 * Returns null — never throws — for malformed JSON, a non-object payload, a
 * missing/blank/non-string `path`, or a null/undefined input. A payload that
 * parses but carries no `role` yields role 'audience' (see asRole).
 */
export function parseAnnouncement(raw: string | null | undefined): Announcement | null {
	if (typeof raw !== 'string' || raw === '') return null;
	let parsed: unknown;
	try {
		parsed = JSON.parse(raw);
	} catch {
		return null; // a half-written or foreign value on our key
	}
	if (parsed === null || typeof parsed !== 'object') return null;
	const { path, role } = parsed as { path?: unknown; role?: unknown };
	if (typeof path !== 'string' || path === '') return null;
	return { path, role: asRole(role) };
}

/**
 * May a window of role `me` follow an announcement sent by role `sender`?
 *
 * True only when the roles differ. Both arguments run through asRole first, so an
 * untagged sender is judged as an audience window and junk can never produce a
 * third role that matches nothing (or, worse, matches everything).
 */
export function mayFollow(sender: unknown, me: unknown): boolean {
	return asRole(sender) !== asRole(me);
}

/**
 * The whole decision for one incoming payload: parse it, check the roles, and
 * check it isn't where we already are — the guard that stops the two-window
 * ping-pong from looping (B follows A, then B's own publish would bounce back).
 *
 * Returns the path to navigate to, or null to ignore. `currentPath` may be
 * null/undefined (a window that hasn't resolved its slide yet), in which case only
 * the role check applies.
 */
export function followTarget(
	raw: string | null | undefined,
	me: unknown,
	currentPath: string | null | undefined
): string | null {
	const announcement = parseAnnouncement(raw);
	if (!announcement) return null;
	if (!mayFollow(announcement.role, me)) return null;
	if (announcement.path === currentPath) return null;
	return announcement.path;
}
