// remoteCore — the pure half of $lib/data: URL building, payload digging and
// TableState → query translation. DOM-free, fetch-free, testable in node.
//
// Every function here is TOTAL, in the house sense (see drawCore/tableCore):
// garbage in yields an empty list, an empty string, or the input as typed —
// never a throw and never `NaN`. That matters more here than almost anywhere
// else in the tree, because the input is a *remote server's* JSON: it is the
// one thing an author cannot proofread. A renamed field must leave the slide
// standing with an empty table, not blank it with an exception mid-talk.

import type { TableState } from '$lib/datatable/types';
import type { QueryNames, QueryParams, QueryValue } from './types';

/** Envelope keys tried, in order, when no explicit `rowsPath` is given. */
const ROW_KEYS = ['data', 'items', 'results', 'rows', 'records', 'content'];

/** Count keys tried, in order, when no explicit `totalPath` is given.
 *  `recordsTotal` is jQuery DataTables' server protocol — the thing this
 *  module exists to replace, so it costs nothing to keep speaking it. */
const TOTAL_KEYS = ['total', 'totalCount', 'count', 'totalRows', 'recordsTotal'];

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === 'object' && value !== null && !Array.isArray(value);
}

/**
 * Walk a dot path into a parsed payload: `data.items`, `result.0.rows`.
 * A numeric segment indexes an array. Anything the path does not reach —
 * a missing key, a null midway, an index past the end — is `undefined`.
 * An empty/blank path returns the payload itself.
 */
export function pluck(payload: unknown, path?: string): unknown {
	const trimmed = typeof path === 'string' ? path.trim() : '';
	if (!trimmed) return payload;

	let current: unknown = payload;
	for (const segment of trimmed.split('.')) {
		if (!segment) continue;
		if (Array.isArray(current)) {
			const index = Number(segment);
			current = Number.isInteger(index) ? current[index] : undefined;
		} else if (isRecord(current)) {
			current = current[segment];
		} else {
			return undefined;
		}
		if (current === undefined || current === null) return undefined;
	}
	return current;
}

/**
 * The row array inside a payload.
 *
 * With `rowsPath`, that path and nothing else — if it doesn't land on an
 * array you get `[]`, which is the honest answer for "your path is wrong"
 * and keeps the table rendering its empty state.
 *
 * Without one, the usual REST envelopes are recognised: a bare top-level
 * array, then `data` / `items` / `results` / `rows` / `records` / `content`,
 * then — as a last resort — the first array-valued property in the object.
 */
export function rowsFrom(payload: unknown, rowsPath?: string): unknown[] {
	if (typeof rowsPath === 'string' && rowsPath.trim()) {
		const found = pluck(payload, rowsPath);
		return Array.isArray(found) ? found : [];
	}
	if (Array.isArray(payload)) return payload;
	if (!isRecord(payload)) return [];

	for (const key of ROW_KEYS) {
		const found = payload[key];
		if (Array.isArray(found)) return found;
	}
	for (const value of Object.values(payload)) {
		if (Array.isArray(value)) return value;
	}
	return [];
}

/** Coerce to a finite, non-negative integer, or `null` for anything else. */
function toCount(value: unknown): number | null {
	if (typeof value === 'number')
		return Number.isFinite(value) && value >= 0 ? Math.trunc(value) : null;
	if (typeof value === 'string' && value.trim()) {
		const n = Number(value);
		return Number.isFinite(n) && n >= 0 ? Math.trunc(n) : null;
	}
	return null;
}

/**
 * The total result count a backend reported — DataTable's `totalCount`, i.e.
 * post-filter and pre-paging, which is what makes "Showing 1–10 of 4,312"
 * and the page math right while only one page of rows is in hand.
 *
 * With `totalPath`, that path; otherwise `total` / `totalCount` / `count` /
 * `totalRows` / `recordsTotal`. When none of them is a usable number, the
 * fallback wins — pass `rows.length`, so a server that reports nothing
 * degrades to "this page is all there is" instead of to zero.
 */
export function totalFrom(
	payload: unknown,
	totalPath: string | undefined,
	fallback: number
): number {
	const safeFallback = toCount(fallback) ?? 0;

	if (typeof totalPath === 'string' && totalPath.trim()) {
		return toCount(pluck(payload, totalPath)) ?? safeFallback;
	}
	if (isRecord(payload)) {
		for (const key of TOTAL_KEYS) {
			const found = toCount(payload[key]);
			if (found !== null) return found;
		}
	}
	return safeFallback;
}

/** Drop nullish and blank values; stringify what's left. Numbers that aren't
 *  finite are dropped too — `NaN` in a URL is never what anyone meant. */
function usableParams(params: QueryParams | undefined): [string, string][] {
	if (!isRecord(params)) return [];
	const out: [string, string][] = [];
	for (const [key, value] of Object.entries(params as Record<string, QueryValue>)) {
		if (!key || value === null || value === undefined) continue;
		if (typeof value === 'number' && !Number.isFinite(value)) continue;
		const text = String(value);
		if (text === '') continue;
		out.push([key, text]);
	}
	return out;
}

/**
 * Append query parameters to a URL.
 *
 * Deliberately string-level rather than `new URL()`: the URLs a deck uses are
 * usually RELATIVE (a bundled `./feed.json?url` import, a path under the
 * deploy's base), and `new URL('./feed.json')` throws. Existing query and
 * hash are preserved — params land before the `#`.
 */
export function buildUrl(base: string, params?: QueryParams): string {
	if (typeof base !== 'string') return '';
	const pairs = usableParams(params);
	if (pairs.length === 0) return base;

	const hashAt = base.indexOf('#');
	const head = hashAt === -1 ? base : base.slice(0, hashAt);
	const hash = hashAt === -1 ? '' : base.slice(hashAt);
	const separator = head.includes('?') ? '&' : '?';
	const query = pairs
		.map(([key, value]) => `${encodeURIComponent(key)}=${encodeURIComponent(value)}`)
		.join('&');

	return `${head}${separator}${query}${hash}`;
}

/**
 * A DataTable `TableState` as query parameters — the missing half of the
 * component's server mode. `onstatechange` hands you the state; this turns it
 * into the URL the backend answers, so sorting, searching, paging and column
 * filters all travel over HTTP with no per-slide plumbing.
 *
 * Blank parts are omitted, so an untouched table asks for `?page=1&pageSize=10`
 * and nothing more. Rename anything the backend spells differently with
 * `names` — `toQuery(state, { search: 'q', filterPrefix: '' })`.
 */
export function toQuery(state: TableState | null | undefined, names: QueryNames = {}): QueryParams {
	const out: QueryParams = {};
	if (!isRecord(state)) return out;

	const pageName = names.page ?? 'page';
	const pageSizeName = names.pageSize ?? 'pageSize';
	const searchName = names.search ?? 'search';
	const sortName = names.sort ?? 'sort';
	const orderName = names.order ?? 'order';
	const filterPrefix = names.filterPrefix ?? 'filter.';

	const page = toCount(state.page);
	if (page !== null && page > 0) out[pageName] = page;

	const pageSize = toCount(state.pageSize);
	if (pageSize !== null && pageSize > 0) out[pageSizeName] = pageSize;

	const search = typeof state.search === 'string' ? state.search.trim() : '';
	if (search) out[searchName] = search;

	const sort = state.sort;
	if (isRecord(sort) && typeof sort.key === 'string' && sort.key && sort.direction) {
		out[sortName] = sort.key;
		out[orderName] = String(sort.direction);
	}

	if (isRecord(state.columnFilters)) {
		for (const [key, value] of Object.entries(state.columnFilters)) {
			if (!key || typeof value !== 'string') continue;
			const text = value.trim();
			if (text) out[`${filterPrefix}${key}`] = text;
		}
	}

	return out;
}

/**
 * A short, speakable message for a failed load — what the `failed` snippet
 * puts on the slide. Never returns an empty string: a thrown non-Error, a
 * bare `undefined`, an object with no message all still say *something*.
 */
export function errorMessage(error: unknown): string {
	if (typeof error === 'string' && error.trim()) return error.trim();
	if (error instanceof Error && error.message.trim()) return error.message.trim();
	if (isRecord(error) && typeof error.message === 'string' && error.message.trim()) {
		return error.message.trim();
	}
	return 'Request failed';
}

/** The message for a non-2xx response, naming the status and the URL — the
 *  two things you need to tell a 404 from a CORS-shaped failure. */
export function httpErrorMessage(status: number, statusText: string, url: string): string {
	const code = Number.isFinite(status) ? String(status) : '?';
	const text = typeof statusText === 'string' && statusText.trim() ? ` ${statusText.trim()}` : '';
	const where = typeof url === 'string' && url ? ` for ${url}` : '';
	return `HTTP ${code}${text}${where}`;
}

/** True when a rejection is an abort (a superseded or torn-down request),
 *  which is bookkeeping rather than a failure worth showing the room. */
export function isAbort(error: unknown): boolean {
	return isRecord(error) && error.name === 'AbortError';
}

/**
 * Apply a row `map`, dropping records that throw rather than letting one bad
 * record take the slide down — the same "total" bargain as the rest of this
 * module, extended to the caller's own function.
 */
export function mapRows<T>(
	raw: readonly unknown[],
	// eslint-disable-next-line @typescript-eslint/no-explicit-any
	map?: (raw: any, index: number) => T
): T[] {
	if (!Array.isArray(raw)) return [];
	if (typeof map !== 'function') return raw as T[];

	const out: T[] = [];
	raw.forEach((row, index) => {
		try {
			out.push(map(row, index));
		} catch {
			/* one unmappable record is dropped; the rest of the page still draws */
		}
	});
	return out;
}
