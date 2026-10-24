// Public types for the remote-data module ($lib/data).
//
// The job: turn a REST endpoint into the plain `T[]` that DataTable and the
// chart family already eat. Nothing here knows about either — the contract
// stays "plain arrays + accessors", exactly as $lib/chart/index.ts states it.

/** A value that can go into a query string. Nullish/blank values are dropped
 *  by buildUrl, so an unset filter simply doesn't appear in the URL. */
export type QueryValue = string | number | boolean | null | undefined;

/** Query parameters as authored — a flat bag, order-insensitive. */
export type QueryParams = Record<string, QueryValue>;

/** Parameter NAMES a backend expects, so a deck can talk to an API that calls
 *  its page cursor `offset` or its search `q` without rewriting anything.
 *  Every field is optional; unset fields keep the defaults shown. */
export interface QueryNames {
	/** 1-based page number. Default `page`. */
	page?: string;
	/** Rows per page. Default `pageSize`. */
	pageSize?: string;
	/** Global search text. Default `search`. */
	search?: string;
	/** Sorted column key. Default `sort`. */
	sort?: string;
	/** Sort direction (`asc` / `desc`). Default `order`. */
	order?: string;
	/** Prefix for per-column filters: `filter.region=us-west`. Default
	 *  `filter.`. Set it to `''` for backends that take bare column names. */
	filterPrefix?: string;
}

/** What a row-shaped response looked like once it was read. */
export interface RemoteRows<T> {
	/** The rows, after `map` if one was given. Never null — `[]` on an
	 *  unrecognisable payload, so a chart or table always has something. */
	rows: T[];
	/** Total result count the backend reported (post-filter, pre-paging) —
	 *  what DataTable's `totalCount` wants. Falls back to `rows.length`. */
	total: number;
	/** The parsed body, untouched — for a caller that needs a field the two
	 *  above didn't cover (a cursor, a server-side warning). */
	payload: unknown;
}

/** Options for fetchRows() and, via its props, for <RemoteData>. */
export interface FetchRowsOptions<T> {
	/** Appended to the URL, blanks dropped. */
	params?: QueryParams;
	/** Extra request headers (an `Accept`, a bearer token). Remember there is
	 *  no server here: anything you put in a header ships in the bundle. */
	headers?: Record<string, string>;
	/** Cancels the request — <RemoteData> wires one per load. */
	signal?: AbortSignal;
	/** Dot path to the array inside the payload (`data.items`, `result.0.rows`).
	 *  Omit it and the common REST envelopes are detected — see rowsFrom(). */
	rowsPath?: string;
	/** Dot path to the total count. Omit it and `total`/`totalCount`/`count`/
	 *  `recordsTotal` are tried — see totalFrom(). */
	totalPath?: string;
	/** Reshape each raw record into the row your columns/accessors expect.
	 *  A record that throws is dropped rather than taking the slide down. */
	// eslint-disable-next-line @typescript-eslint/no-explicit-any
	map?: (raw: any, index: number) => T;
	/** Test seam — defaults to the global `fetch`. */
	fetchImpl?: typeof fetch;
}
