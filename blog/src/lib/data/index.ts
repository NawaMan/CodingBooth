// Public exports for the remote-data module.
//
// The bridge between a REST endpoint and the two families that already render
// data: $lib/datatable and $lib/chart. It imports neither — rows come out as
// a plain `T[]`, which is the only contract either of them asks for.
//
// Three layers, deliberately separable:
//   • remoteCore  — pure, total, node-testable: buildUrl / toQuery / rowsFrom /
//                   totalFrom / pluck / errorMessage. No fetch, no DOM.
//   • fetchRows   — one request, one `{ rows, total, payload }`. Throws on a
//                   failed request; degrades to `[]` on a surprising payload.
//   • RemoteData  — the component: pending / failed / empty / children, aborts
//                   superseded requests, SSR-inert because the fetch is in an
//                   $effect.
//
// toQuery() is the piece that closes DataTable's server mode: `onstatechange`
// hands over a TableState, toQuery turns it into the query string, and the
// backend answers with one page plus a count.
export { default as RemoteData } from './RemoteData.svelte';
export { fetchRows } from './fetchRows';
export * from './remoteCore';
export type * from './types';
