// Public types for the DataTable component family.
// See specs/DATATABLE-1.md for the full design; this is the target API surface —
// filterable/visible land in Phase 3.

import type { Snippet } from 'svelte';

export type SortDirection = 'asc' | 'desc' | null;

export interface SortDescriptor {
	key: string;
	direction: SortDirection;
}

/** Column value type driving sorting/comparison. 'auto' is resolved once per
 *  column by sampling the data (see inferColumnType in tableCore.ts). */
export type ColumnType = 'string' | 'number' | 'date' | 'auto';

/** A ColumnType after 'auto' has been resolved against the data. */
export type ResolvedColumnType = Exclude<ColumnType, 'auto'>;

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export interface ColumnDef<T = any> {
	key: string; // property accessor (flat keys for MVP; dot paths later)
	label: string;
	sortable?: boolean; // default true
	type?: ColumnType; // default 'auto'
	// eslint-disable-next-line @typescript-eslint/no-explicit-any
	format?: (value: any, row: T) => string;
	/** Custom sort accessor ("orthogonal data", as jQuery DataTables calls
	 *  it): returns the value a row *sorts by* in this column, independent
	 *  of what the cell displays. E.g. map a 'pending' deploy to a far-future
	 *  date so it counts as latest — after every real date ascending, first
	 *  when sorting newest-first. The result is compared under the column's
	 *  (resolved) type; blank/uncomparable results still always sort last. */
	sortValue?: (row: T) => unknown;
	width?: string; // CSS width, optional
	filterable?: boolean; // per-column filter (Phase 3)
	visible?: boolean; // column visibility (Phase 3)
	align?: 'left' | 'center' | 'right';
}

/** A custom cell renderer, receiving (row, value, rowIndex) — value is the
 *  raw row[column.key] (format() is NOT applied first), rowIndex is 0-based
 *  within the current page. */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type CellSnippet<T = any> = Snippet<[T, any, number]>;

/** Per-column custom cell snippets, keyed by column key. Passed as the
 *  `snippets` prop — an explicit map, deliberately NOT dynamically-named
 *  `cell_*` snippets (dynamic snippet names aren't resolvable in Svelte).
 *  Rendering precedence per cell: snippet > column.format > raw value.
 *  Sorting and searching are untouched by snippets: rows still sort by the
 *  raw value (or sortValue) and search still matches the format()/raw text. */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type CellSnippets<T = any> = Record<string, CellSnippet<T>>;

/** Row identity for selection: a key field name, or an accessor function
 *  for composite/derived keys. Required when `selectable` — array index is
 *  deliberately NOT an option, since it changes under sort/filter/page. */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type RowKey<T = any> = string | ((row: T) => unknown);

/** Per-column custom header content, keyed by column key; each snippet
 *  receives the ColumnDef. For sortable columns it renders INSIDE the header
 *  button (replacing the label text), so click-to-sort, keyboard
 *  operability, and the sort indicator are preserved. */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type HeaderSnippets<T = any> = Record<string, Snippet<[ColumnDef<T>]>>;

/** All processing state in one object, exposed as the `bind:state` prop —
 *  bind it for controlled mode (internal changes write back; external
 *  changes drive the table) and for server-side data. */
export interface TableState {
	sort: SortDescriptor | null;
	search: string;
	columnFilters: Record<string, string>;
	page: number; // 1-based
	pageSize: number;
}

/** 'client': the component filters/sorts/paginates rows itself (default).
 *  'server': rows are rendered as-is and the component only emits state
 *  changes (onstatechange / bind:state) — the parent fetches each page and
 *  supplies `totalCount`. */
export type TableMode = 'client' | 'server';
