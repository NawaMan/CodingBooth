// fetchRows — one AJAX call, one array of rows.
//
// The I/O half of $lib/data. Everything it decides (which array in the
// payload, which number is the total, what the error says) is delegated to
// the pure remoteCore functions, so this file is only the request itself.
//
// THERE IS NO SERVER HERE. This project is adapter-static on GitHub Pages —
// no `+server.js`, no `load()`, no proxy — so the request leaves the
// audience's browser, which has two consequences worth saying out loud:
//   • the endpoint MUST send CORS headers (Access-Control-Allow-Origin), or
//     the browser refuses the response and you get a network-shaped error
//     with no status to read;
//   • any key you put in `headers` ships in the bundle and is readable by
//     anyone at the talk. Public endpoints only.

import {
	errorMessage,
	httpErrorMessage,
	mapRows,
	rowsFrom,
	totalFrom,
	buildUrl
} from './remoteCore';
import type { FetchRowsOptions, RemoteRows } from './types';

/**
 * GET a JSON endpoint and return rows the DataTable / chart family can eat.
 *
 * Unlike the pure core, this one THROWS — on a non-2xx status, on a body that
 * isn't JSON, on a network/CORS failure, and on abort. That is deliberate:
 * a failed request is a real event a slide should be able to show, whereas a
 * merely surprising payload shape is not (that degrades to `[]`). <RemoteData>
 * catches all of it and hands the message to its `failed` snippet.
 *
 * ```ts
 * const { rows, total } = await fetchRows<Region>(url, {
 *   params: toQuery(tableState),
 *   rowsPath: 'data.items',
 *   map: (r) => ({ ...r, requests: Number(r.requests) })
 * });
 * ```
 */
export async function fetchRows<T = unknown>(
	url: string,
	options: FetchRowsOptions<T> = {}
): Promise<RemoteRows<T>> {
	const { params, headers, signal, rowsPath, totalPath, map, fetchImpl } = options;

	const request = fetchImpl ?? (typeof fetch === 'function' ? fetch : undefined);
	if (!request) throw new Error('No fetch available in this environment');

	const target = buildUrl(url, params);
	if (!target) throw new Error('No URL given');

	const response = await request(target, {
		method: 'GET',
		headers: { Accept: 'application/json', ...(headers ?? {}) },
		credentials: 'omit',
		signal
	});

	if (!response.ok) {
		throw new Error(httpErrorMessage(response.status, response.statusText, target));
	}

	let payload: unknown;
	try {
		payload = await response.json();
	} catch (error) {
		throw new Error(`Response was not JSON (${errorMessage(error)})`);
	}

	const raw = rowsFrom(payload, rowsPath);
	const rows = mapRows<T>(raw, map);
	return { rows, total: totalFrom(payload, totalPath, raw.length), payload };
}
