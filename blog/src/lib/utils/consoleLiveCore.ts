// consoleLiveCore — is a presenter console still open, decided purely.
//
// The audience deck window and the ?present console are separate windows sharing
// only localStorage. There is no "is the other window still there?" API, so the
// console HEARTBEATS a fresh timestamp (stores/presenter.publishConsoleAlive) every
// CONSOLE_BEAT_MS while it is open, and the audience window treats it as LIVE only
// while that beat is recent: a console that is closed (or crashes) simply stops
// beating and goes stale after CONSOLE_TTL_MS — the same staleness discipline the
// ink uses (inkStaleAfter), not a farewell event a force-quit would skip.
//
// Pure, total and NaN-safe in the drawCore/toastCore tradition: a missing, zero or
// garbage beat reads "not live", never a throw and never a NaN comparison that
// silently evaluates true. The one number that matters — hide the redundant
// below-slide note or not — must never depend on `NaN < NaN`.

/** How often the open console re-stamps its heartbeat (ms). */
export const CONSOLE_BEAT_MS = 2_000;

/** How long after the last heartbeat the console still counts as live (ms). A
    comfortable multiple of CONSOLE_BEAT_MS so a single dropped beat never flickers
    the note back. */
export const CONSOLE_TTL_MS = 6_000;

/**
 * Is a console heartbeat from `lastBeatMs` still live as of `nowMs`, given `ttlMs`?
 *
 * - A null/undefined/≤0/non-finite beat → false (no console has ever beaten).
 * - A non-finite `nowMs` → false (can't judge age).
 * - A non-finite/≤0 `ttlMs` falls back to CONSOLE_TTL_MS rather than admitting a
 *   degenerate window that answers everything true or false.
 * - A beat "in the future" (nowMs < lastBeatMs — same-machine clock skew is nil,
 *   but stay total) is live: only a beat OLDER than the ttl is stale.
 */
export function consoleIsLive(
	lastBeatMs: number | null | undefined,
	nowMs: number,
	ttlMs: number = CONSOLE_TTL_MS
): boolean {
	if (lastBeatMs == null || !Number.isFinite(lastBeatMs) || lastBeatMs <= 0) return false;
	if (!Number.isFinite(nowMs)) return false;
	const ttl = Number.isFinite(ttlMs) && ttlMs > 0 ? ttlMs : CONSOLE_TTL_MS;
	return nowMs - lastBeatMs < ttl;
}
