// The track arithmetic behind <Columns> / <Column>: turning an author's `columns`
// count or `widths` list into a `grid-template-columns` value, counting the tracks
// that result, and clamping a column's `span` to them.
//
// Kept pure and DOM-free (drawCore / connectorCore / videoCore discipline) so the
// components are left with nothing but markup, and so the interesting cases — a
// negative width, a `columns={0}`, a span past the last track — are testable
// without a layout engine, which jsdom does not have.
//
// Every function is total: bad input falls back to the sane default, never a
// throw and never an empty template. A slide must not collapse because someone
// typed `widths={[2, -1]}`.

/** One track, as an author writes it: a flex weight (`2` → `2fr`) or a CSS length. */
export type Track = number | string;

/** How a grid aligns its items on the block axis. */
export const ALIGNMENTS = ['stretch', 'start', 'center', 'end', 'baseline'] as const;
export type Align = (typeof ALIGNMENTS)[number];

/** The columns a `<Column>` reads from its `<Columns>`: how many tracks there are
    (null when the author supplied a raw template we cannot count) and whether the
    group draws rules between its columns. */
export const COLUMNS_CONTEXT = Symbol('geekpresent.columns');

/** Default track count when `columns` is unusable — a split is the common case. */
const DEFAULT_COLUMNS = 2;

/** An even track. `minmax(0, 1fr)`, never a bare `1fr`: an `fr` track's minimum is
    `auto` (i.e. min-content), so one long unbreakable token — a URL, a `<pre>` line —
    would blow the track wider than its share and push the grid off the canvas. */
const EVEN_TRACK = 'minmax(0, 1fr)';

/**
 * A single track token, or `null` for anything unusable.
 *
 * A finite positive number is a flex weight (`2` → `2fr`); a non-empty string is a
 * CSS value passed through (`'320px'`, `'minmax(0, 1fr)'`). A `;` is rejected: the
 * template is emitted inside an inline `style` attribute, where a stray semicolon
 * would silently terminate the declaration and swallow whatever follows.
 */
function trackToken(track: Track): string | null {
	if (typeof track === 'number') {
		return Number.isFinite(track) && track > 0 ? `${track}fr` : null;
	}
	if (typeof track !== 'string') return null;
	const text = track.trim();
	if (!text || text.includes(';')) return null;
	return text;
}

/** The usable tokens of a `widths` array, or `null` if it isn't an array or nothing
    in it survived — either way the caller falls back to the `columns` count. */
function widthTokens(widths: unknown): string[] | null {
	if (!Array.isArray(widths)) return null;
	const tokens = widths.map(trackToken).filter((token): token is string => token !== null);
	return tokens.length ? tokens : null;
}

/** A whole, positive column count; `DEFAULT_COLUMNS` for anything else. */
function columnCount(columns: unknown): number {
	if (typeof columns !== 'number' || !Number.isFinite(columns)) return DEFAULT_COLUMNS;
	const whole = Math.trunc(columns);
	return whole >= 1 ? whole : DEFAULT_COLUMNS;
}

/**
 * The `grid-template-columns` value for a group.
 *
 * `widths` wins when it yields anything usable: a string is the author's own
 * template, verbatim; an array becomes one token per entry. Otherwise `columns`
 * even tracks. The result is always a non-empty template.
 */
export function trackTemplate(columns: unknown, widths: unknown): string {
	if (typeof widths === 'string') {
		const template = widths.trim();
		if (template && !template.includes(';')) return template;
	}
	const tokens = widthTokens(widths);
	if (tokens) return tokens.join(' ');
	return Array.from({ length: columnCount(columns) }, () => EVEN_TRACK).join(' ');
}

/**
 * How many tracks `trackTemplate` just produced, or `null` when the author passed a
 * raw string template — `repeat(3, 1fr)` is three tracks and `1fr 1fr` is two, and
 * telling them apart means parsing CSS. A `null` count means a `<Column>` trusts the
 * author's `span` instead of clamping it.
 */
export function trackCount(columns: unknown, widths: unknown): number | null {
	if (typeof widths === 'string' && widths.trim() && !widths.includes(';')) return null;
	const tokens = widthTokens(widths);
	return tokens ? tokens.length : columnCount(columns);
}

/**
 * A `<Column>`'s span: a whole number of tracks, at least 1, and never more than the
 * group has. An over-long span is the trap this exists to close — grid quietly *adds*
 * an implicit column to fit it, so `span={3}` in a two-column group silently makes it
 * three. A `null` count (author's own template) is trusted as written.
 */
export function clampSpan(span: unknown, count: number | null): number {
	if (typeof span !== 'number' || !Number.isFinite(span)) return 1;
	const whole = Math.trunc(span);
	if (whole < 1) return 1;
	return count === null ? whole : Math.min(whole, count);
}

/** A recognized alignment, or `fallback` — never a value the stylesheet doesn't know. */
export function alignment<F extends Align | null>(value: unknown, fallback: F): Align | F {
	return ALIGNMENTS.includes(value as Align) ? (value as Align) : fallback;
}

// ── Resizable dividers ────────────────────────────────────────────────────────
//
// A draggable divider needs the tracks in PIXELS, which no amount of parsing the
// author's `widths` can give: `1fr` is a share of whatever space is left. The
// browser knows, though — `getComputedStyle(grid).gridTemplateColumns` resolves to
// the used widths (`'300px 500px'`). So the component measures, and everything
// below is arithmetic on that measurement.

/**
 * The used track widths from a computed `grid-template-columns`.
 *
 * `[]` for anything that isn't a clean list of pixel lengths — `'none'` (an
 * unrendered grid), a jsdom stub echoing the `var()` back, a `repeat()` that never
 * resolved. The caller falls back to the authored template rather than dragging
 * against numbers it invented.
 */
export function parseTrackPx(computed: unknown): number[] {
	if (typeof computed !== 'string') return [];
	const text = computed.trim();
	if (!text || text === 'none') return [];

	const tracks: number[] = [];
	for (const part of text.split(/\s+/)) {
		if (!/^-?\d+(\.\d+)?px$/.test(part)) return [];
		const px = Number.parseFloat(part);
		if (!Number.isFinite(px) || px < 0) return [];
		tracks.push(px);
	}
	return tracks;
}

/** A computed `column-gap` in px. `'normal'` (and anything else) is 0 — grid's own
    initial column-gap, so a missing measurement never shifts a handle. */
export function parseGapPx(computed: unknown): number {
	if (typeof computed !== 'string') return 0;
	const px = Number.parseFloat(computed);
	return Number.isFinite(px) && px >= 0 ? px : 0;
}

/**
 * The centre of each gutter, in px from the grid's content-box left edge — one per
 * divider, so `tracks.length - 1` of them. Gutter `i` sits between track `i` and
 * `i + 1`, which is exactly the pair a drag on it redistributes.
 */
export function gutterCenters(tracks: number[], gap: number): number[] {
	if (!Array.isArray(tracks) || tracks.length < 2) return [];
	const g = Number.isFinite(gap) && gap >= 0 ? gap : 0;

	const centers: number[] = [];
	let edge = 0;
	for (let i = 0; i < tracks.length - 1; i++) {
		const width = Number.isFinite(tracks[i]) ? tracks[i] : 0;
		edge += width;
		// `g * i` is the gutters already crossed; `g / 2` centres us in this one.
		centers.push(edge + g * i + g / 2);
	}
	return centers;
}

/**
 * Drag gutter `index` by `dx` px: the two tracks it separates trade width, and
 * every other track holds still. Their SUM is invariant, so the grid never changes
 * size and no other divider moves — which is what makes a drag feel local.
 *
 * `minTrack` floors both sides. When the pair is already too narrow to honour it
 * (a tiny group, an absurd `minTrack`) the tracks are returned untouched: refusing
 * to move beats jumping to a size the author never asked for.
 */
export function resizeTracks(
	tracks: number[],
	index: number,
	dx: number,
	minTrack: number
): number[] {
	if (!Array.isArray(tracks) || index < 0 || index >= tracks.length - 1) return tracks;

	const a = tracks[index];
	const b = tracks[index + 1];
	if (!Number.isFinite(a) || !Number.isFinite(b)) return tracks;

	const floor = Number.isFinite(minTrack) && minTrack > 0 ? minTrack : 0;
	const total = a + b;
	if (total < floor * 2) return tracks;

	const delta = Number.isFinite(dx) ? dx : 0;
	const next = Math.min(Math.max(a + delta, floor), total - floor);

	const out = tracks.slice();
	out[index] = next;
	out[index + 1] = total - next;
	return out;
}

/**
 * The measured tracks as a `grid-template-columns` of `fr` weights.
 *
 * Using the raw pixel widths AS the weights is exact, not an approximation: an `fr`
 * track gets `free space x (w / sum(w))`, and the measured widths already sum to the
 * free space. So the grid does not move on the frame the drag starts — and it stays
 * fluid afterwards, which raw `px` tracks would not (resize the Block around it and
 * px tracks refuse to reflow).
 *
 * `minmax(0, Nfr)` for the same reason the even tracks use it: a bare `fr` floors at
 * min-content, so a wide child would silently overrule the width the drag just set.
 */
export function weightsTemplate(tracks: number[]): string {
	if (!Array.isArray(tracks) || !tracks.length) return '';
	if (!tracks.every((w) => Number.isFinite(w) && w >= 0)) return '';
	// An all-zero measurement (a display:none grid) carries no ratio to preserve.
	if (!tracks.some((w) => w > 0)) return '';
	return tracks.map((w) => `minmax(0, ${w}fr)`).join(' ');
}

/**
 * The tracks as readable weights for the author to paste back: normalized so they
 * average 1 (`[1.17, 0.83]`, not `[700, 500]`) and rounded. A weight rounding to 0
 * is floored at the smallest representable value — pasting a `0fr` track back would
 * reproduce a column the author can see on screen as a column they cannot.
 */
export function toWeights(tracks: number[], precision = 2): number[] {
	if (!Array.isArray(tracks) || !tracks.length) return [];
	const usable = tracks.filter((w) => Number.isFinite(w) && w >= 0);
	if (usable.length !== tracks.length) return [];

	const total = usable.reduce((sum, w) => sum + w, 0);
	if (total <= 0) return [];

	const places = Number.isFinite(precision) && precision >= 0 ? Math.trunc(precision) : 2;
	const unit = 10 ** places;
	const smallest = 1 / unit;
	return usable.map((w) => Math.max(Math.round((w * usable.length * unit) / total) / unit, smallest));
}

/** The `widths={[…]}` snippet a ADJUST-mode Copy puts on the clipboard. */
export function formatWidths(tracks: number[], precision = 2): string {
	const weights = toWeights(tracks, precision);
	if (!weights.length) return '';
	return `widths={[${weights.join(', ')}]}`;
}
