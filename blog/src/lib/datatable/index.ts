// Public exports for the DataTable module.
//
// Custom cell rendering convention (settled in Phase 2): per-column cell
// snippets are wired through the explicit `snippets` prop map —
// `snippets={{ status: myBadge }}` where each snippet receives
// (row, value, rowIndex) — NOT dynamically-named `cell_*` snippets, since
// dynamic snippet names aren't resolvable in Svelte. Structural snippets
// (`empty`) stay regular named snippets. Cell precedence: snippet >
// column.format > raw value; sorting always compares the raw/sortValue
// value and global search always matches the format()/raw text.
export { default as ColumnToggle } from './ColumnToggle.svelte';
export { default as DataTable } from './DataTable.svelte';
export { default as Pagination } from './Pagination.svelte';
export { default as SearchBox } from './SearchBox.svelte';
export * from './tableCore';
export type * from './types';
