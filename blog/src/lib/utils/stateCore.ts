/*
  State — the pure decision layer behind a deck that remembers things.

  A deck carries state in three places, and they are not interchangeable:

    - The URL (`?name=Ada`)  — shareable, survives a reload, and is the ONLY one
      a speaker can hand to an audience by reading it aloud. Untrusted: anyone
      can type anything into it.
    - localStorage           — per-browser, survives a reload, invisible to
      everyone else. Also untrusted: another tab, an older version of the deck,
      or a half-finished write can leave garbage behind.
    - A Svelte store         — per-page-load, the fastest and the most forgetful.

  What they share is that the first two are STRINGS FROM OUTSIDE, so every read
  is a parse that can fail. This module is where those parses live.

  Pure and total in the drawCore / adjustAccessCore / appendixCore tradition:
  every input may be junk — an absent param, a NaN, a value another tab
  corrupted, a 4 MB string — and each has exactly one defined answer. Nothing
  here throws, and nothing here returns NaN. That matters more than it sounds:
  `stores/diagramScroll.ts` used to read its key with a bare `parseInt`, so a
  corrupt value made the store NaN and the diagram was laid out at `NaNpx`. A
  parse that cannot fail is the fix, and it belongs here rather than in each
  store — which is where all three persisted stores now get it.

  Note what is deliberately NOT here: `browser` guards. This module never
  touches `window` or `localStorage` — it only interprets values that someone
  else read. That is what makes it testable in the SSR project as well as the
  DOM one, and it is the discipline that keeps the prerender honest.
*/

/** Bounds for a numeric read. Both ends optional; an absent end does not clamp. */
export interface Bounds {
	min?: number;
	max?: number;
}

/** Clamp, tolerating junk bounds. A `min` above its `max` is a caller bug, and the
    honest answer is to let `max` win rather than to invent a value outside both. */
export function clamp(value: number, { min, max }: Bounds = {}): number {
	let v = value;
	if (typeof min === 'number' && Number.isFinite(min) && v < min) v = min;
	if (typeof max === 'number' && Number.isFinite(max) && v > max) v = max;
	return v;
}

/** Interpret a string as a number, with a fallback for everything that isn't one.

    The fallback is returned for: absent, empty, whitespace, `"abc"`, `"NaN"`,
    `"Infinity"`, and `"12px"`. Note `parseInt("12px")` is 12 and `parseFloat("1e999")`
    is `Infinity` — both are silent lies, so this uses `Number()` and demands finite.
    A trailing-garbage value is a corrupted key, not a value with a unit. */
export function parseNumber(
	raw: string | null | undefined,
	fallback: number,
	bounds?: Bounds
): number {
	if (typeof raw !== 'string') return fallback;
	const trimmed = raw.trim();
	if (trimmed === '') return fallback;
	const n = Number(trimmed);
	if (!Number.isFinite(n)) return fallback;
	return clamp(n, bounds);
}

/** Serialize a number for storage. Non-finite values would round-trip as the strings
    `"NaN"` / `"Infinity"`, which `parseNumber` then refuses — so they are never written
    in the first place, and the key keeps its last good value instead of becoming a trap
    for the next reader. */
export function writeNumber(value: number, fallback = 0): string {
	return String(Number.isFinite(value) ? value : fallback);
}

/** The longest text we will accept from a URL. Long enough for any real answer,
    short enough that a hand-built megabyte param cannot blow out the layout. */
export const MAX_TEXT = 64;

/** Control characters — including the newlines and tabs a crafted URL can carry. */
const CONTROL = /[\u0000-\u001F\u007F]/g;

/** Interpret a string as display text, refusing what would break the slide.

    Control characters are stripped rather than escaped: they have no meaning in a
    one-line label, and a stripped character is one the author can SEE is gone.
    Over-long input is cut to `MAX_TEXT`.

    This is NOT an XSS guard and does not pretend to be one — Svelte escapes text it
    interpolates, so `<script>` in a param renders as those literal characters and is
    inert. The danger being handled here is a ADJUST one, which is the danger that is
    actually real. */
export function parseText(raw: string | null | undefined, fallback = ''): string {
	if (typeof raw !== 'string') return fallback;
	const cleaned = raw.replace(CONTROL, '').trim();
	if (cleaned === '') return fallback;
	return cleaned.slice(0, MAX_TEXT);
}

/** Read a numeric query parameter. Absent or unparseable → the fallback, so a slide
    always has a value to render and never has to branch on "did the URL make sense". */
export function readNumberParam(
	search: URLSearchParams | null | undefined,
	name: string,
	fallback: number,
	bounds?: Bounds
): number {
	if (!search) return fallback;
	return parseNumber(search.get(name), fallback, bounds);
}

/** Read a text query parameter, cleaned and length-capped. */
export function readTextParam(
	search: URLSearchParams | null | undefined,
	name: string,
	fallback = ''
): string {
	if (!search) return fallback;
	return parseText(search.get(name), fallback);
}

/** A codec turns a stored string into a value and back.

    `read` returns `null` for "this string is not one of mine" — distinct from a value
    that happens to be falsy. `0` is a perfectly good stored count; `null` means the key
    held garbage and the caller should fall back to its initial value. Conflating the two
    is how a persisted zero turns back into a default on reload. */
export interface Codec<T> {
	read(raw: string): T | null;
	write(value: T): string;
}

/** A number codec, clamped to `bounds`. Garbage reads as `null` (→ the store's initial),
    never as NaN. */
export function numberCodec(bounds?: Bounds): Codec<number> {
	return {
		read(raw: string): number | null {
			const trimmed = typeof raw === 'string' ? raw.trim() : '';
			if (trimmed === '') return null;
			const n = Number(trimmed);
			if (!Number.isFinite(n)) return null;
			return clamp(n, bounds);
		},
		write: (value: number) => writeNumber(value)
	};
}

/** A text codec — cleaned and capped on the way in, verbatim on the way out. An empty
    string is a real value here (the author cleared the field), so only a non-string is
    `null`. */
export function textCodec(): Codec<string> {
	return {
		read: (raw: string) => (typeof raw === 'string' ? parseText(raw) : null),
		write: (value: string) => (typeof value === 'string' ? value : '')
	};
}

/** A strict boolean codec — the two strings this codec writes, and nothing else.

    `jsonCodec<boolean>()` would very nearly do, and that is the trap: `JSON.parse` happily
    returns an OBJECT for `{"not":"a boolean"}`, which is truthy, so a corrupt key would
    read back as "true enough" and arm a flag nobody set. A flag guarding authoring chrome
    has to fail CLOSED, so anything that is not exactly `true`/`false` is `null` — the
    caller's initial value. */
export function booleanCodec(): Codec<boolean> {
	return {
		read(raw: string): boolean | null {
			const trimmed = typeof raw === 'string' ? raw.trim() : '';
			if (trimmed === 'true') return true;
			if (trimmed === 'false') return false;
			return null;
		},
		write: (value: boolean) => (value ? 'true' : 'false')
	};
}

/** A JSON codec for structured values. A key another version of the deck wrote with a
    different shape is the ordinary case, not the exotic one, so a throw from
    `JSON.parse` is caught and reported as `null` rather than taking the page down at
    module-init time — before any error boundary exists to catch it. */
export function jsonCodec<T>(): Codec<T> {
	return {
		read(raw: string): T | null {
			try {
				const parsed = JSON.parse(raw);
				return (parsed ?? null) as T | null;
			} catch {
				return null;
			}
		},
		write: (value: T) => JSON.stringify(value)
	};
}
