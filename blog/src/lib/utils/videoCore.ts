// The arithmetic behind <Video>: parsing an author's bookmark times, formatting a
// clock readout, deciding which chapter is current, and turning a click on the
// progress track into a position in the video.
//
// Kept pure and DOM-free (drawCore / connectorCore / stepKeys discipline) so the
// component is left with nothing but markup and media-element bindings, and so the
// interesting cases — a malformed time, a video whose duration is still NaN, a
// click a pixel outside the track — are testable without a media element, which
// jsdom does not really have.
//
// Every function is total: bad input yields a harmless value (NaN, -1, 0, '0:00'),
// never a throw. A slide must not blow up because someone typed "1:xx".

/** A chapter marker, as an author writes it. */
export interface Bookmark {
	/** Seconds (`74`) or a clock string (`'1:14'`, `'0:03'`, `'1:02:03'`). */
	at: number | string;
	/** What happens at that moment. */
	label?: string;
	/** Optional short badge, e.g. 'HOST' / 'BOOTH'. */
	tag?: string;
}

/** A bookmark once its time is resolved to seconds. */
export interface ResolvedBookmark {
	time: number;
	label: string;
	tag?: string;
}

/**
 * Seconds from a number or a clock string. `NaN` for anything unusable — the
 * caller drops it rather than seeking the video to nowhere.
 *
 * Colon groups are read right-to-left as s / m:s / h:m:s, so `'1:14'` is 74s.
 * Lenient about the ranges (`'0:75'` is 75s): out-of-range digits are an author's
 * typo, and computing the obvious thing beats discarding their marker.
 */
export function parseTime(value: number | string | null | undefined): number {
	if (typeof value === 'number') return Number.isFinite(value) && value >= 0 ? value : NaN;
	if (typeof value !== 'string') return NaN;

	const text = value.trim();
	if (!text) return NaN;

	const parts = text.split(':');
	if (parts.length > 3) return NaN;

	let total = 0;
	for (const part of parts) {
		// Digits, optionally with a decimal tail. No sign: a negative bookmark is
		// meaningless, and '-' would otherwise sneak through Number().
		if (!/^\d+(\.\d+)?$/.test(part)) return NaN;
		total = total * 60 + Number(part);
	}
	return total;
}

/**
 * `m:ss`, or `h:mm:ss` once there is an hour to show. Anything not a real,
 * non-negative number reads as `'0:00'` — which is exactly what an unloaded
 * video's `duration` (NaN) should look like in the readout.
 */
export function formatTime(seconds: number): string {
	if (!Number.isFinite(seconds) || seconds < 0) return '0:00';

	const whole = Math.floor(seconds);
	const s = whole % 60;
	const m = Math.floor(whole / 60) % 60;
	const h = Math.floor(whole / 3600);

	const mm = h > 0 ? String(m).padStart(2, '0') : String(m);
	return `${h > 0 ? `${h}:` : ''}${mm}:${String(s).padStart(2, '0')}`;
}

/**
 * Resolve, drop the unusable, and sort by time. Sorting is what lets
 * `activeBookmarkIndex` stop at the first marker past the playhead, and it frees
 * the author to list chapters in whatever order they think of them.
 */
export function normalizeBookmarks(bookmarks: readonly Bookmark[] | null | undefined): ResolvedBookmark[] {
	return (bookmarks ?? [])
		.map((b) => ({ time: parseTime(b?.at), label: b?.label ?? '', tag: b?.tag }))
		.filter((b) => Number.isFinite(b.time))
		.sort((a, b) => a.time - b.time);
}

/**
 * The chapter the playhead is in: the last one whose time has passed. `-1` before
 * the first marker (a video may well open on unlabelled footage), and `-1` while
 * `currentTime` is still NaN.
 *
 * Expects the sorted output of `normalizeBookmarks`.
 */
export function activeBookmarkIndex(bookmarks: readonly ResolvedBookmark[], currentTime: number): number {
	if (!Number.isFinite(currentTime)) return -1;

	let active = -1;
	for (let i = 0; i < bookmarks.length; i++) {
		if (bookmarks[i].time > currentTime) break;
		active = i;
	}
	return active;
}

/**
 * Where along the track a click landed, as 0..1. Clamped, because a pointer that
 * starts on the track and drags past its edge still reports coordinates outside it,
 * and a zero-width track (never laid out, `display: none`) must not divide by zero.
 */
export function seekFraction(clientX: number, rect: { left: number; width: number }): number {
	if (!Number.isFinite(clientX) || !(rect.width > 0)) return 0;
	return Math.min(1, Math.max(0, (clientX - rect.left) / rect.width));
}

/**
 * How far through the video, as a percentage — for the progress fill and the
 * chapter ticks. A duration of 0 or NaN (metadata not in yet, or a live stream)
 * yields 0 rather than an Infinity that CSS would drop on the floor.
 */
export function progressPercent(currentTime: number, duration: number): number {
	if (!Number.isFinite(currentTime) || !Number.isFinite(duration) || duration <= 0) return 0;
	return Math.min(100, Math.max(0, (currentTime / duration) * 100));
}
