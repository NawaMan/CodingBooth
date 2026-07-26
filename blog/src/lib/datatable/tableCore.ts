// Pure data-processing functions for DataTable. No component imports, no DOM —
// everything here is independently unit-testable (tests/tableCore.test.ts).
//
// The pipeline (each stage its own $derived in DataTable.svelte — never merged):
//   rows → filterRows → sortRows → paginateRows → visible rows

import type { ColumnDef, ResolvedColumnType, RowKey, SortDescriptor } from './types';

/** Values that always sort last and never match a search: null/undefined/''. */
export function isBlank(value: unknown): boolean {
	return value === null || value === undefined || value === '';
}

function toNumber(value: unknown): number {
	if (typeof value === 'number') return value;
	const s = String(value).trim();
	return s === '' ? NaN : Number(s);
}

function toTime(value: unknown): number {
	if (value instanceof Date) return value.getTime();
	if (typeof value === 'number') return value; // already a timestamp
	return new Date(String(value)).getTime();
}

/** True when a non-blank value cannot be compared under the given type
 *  (NaN for numbers, invalid date for dates). These sort last too. */
function isUncomparable(value: unknown, type: ResolvedColumnType): boolean {
	if (type === 'number') return Number.isNaN(toNumber(value));
	if (type === 'date') return Number.isNaN(toTime(value));
	return false;
}

/** Blank or uncomparable — belongs in the sorts-last bucket regardless of
 *  sort direction. */
export function sortsLast(value: unknown, type: ResolvedColumnType): boolean {
	return isBlank(value) || isUncomparable(value, type);
}

/**
 * Ascending comparator for two cell values of a resolved column type.
 * Blank / NaN / invalid-date values sort last; direction handling lives in
 * sortRows so that "last" stays last even when descending.
 */
export function compareValues(a: unknown, b: unknown, type: ResolvedColumnType): number {
	const aLast = sortsLast(a, type);
	const bLast = sortsLast(b, type);
	if (aLast || bLast) return aLast && bLast ? 0 : aLast ? 1 : -1;

	switch (type) {
		case 'number': {
			const an = toNumber(a);
			const bn = toNumber(b);
			return an < bn ? -1 : an > bn ? 1 : 0;
		}
		case 'date': {
			const at = toTime(a);
			const bt = toTime(b);
			return at < bt ? -1 : at > bt ? 1 : 0;
		}
		default:
			// numeric: true gives natural sort ("item2" before "item10")
			return String(a).localeCompare(String(b), undefined, {
				sensitivity: 'base',
				numeric: true
			});
	}
}

/**
 * Resolve a column's effective type from the data: if every non-blank value
 * coerces cleanly to a number → 'number'; else if every one parses as a date
 * → 'date'; else 'string'. Called once per column (cache the result — never
 * infer per comparison). Empty/all-blank columns fall back to 'string'.
 * When the column has a sortValue accessor, pass it as getValue so the
 * inference looks at the values that will actually be compared.
 */
export function inferColumnType<T>(
	rows: readonly T[],
	key: string,
	getValue?: (row: T) => unknown
): ResolvedColumnType {
	let sampled = false;
	let allNumbers = true;
	let allDates = true;
	for (const row of rows) {
		// eslint-disable-next-line @typescript-eslint/no-explicit-any
		const value = getValue ? getValue(row) : (row as any)?.[key];
		if (isBlank(value)) continue;
		sampled = true;
		if (allNumbers && Number.isNaN(toNumber(value))) allNumbers = false;
		if (allDates && !(value instanceof Date) && typeof value !== 'string') allDates = false;
		if (allDates && Number.isNaN(toTime(value))) allDates = false;
		if (!allNumbers && !allDates) break;
	}
	if (!sampled) return 'string';
	if (allNumbers) return 'number';
	if (allDates) return 'date';
	return 'string';
}

/** A row's identity under a RowKey (field name or accessor) — what selection
 *  is keyed by, so it survives sorting, filtering, and paging. */
export function rowKeyOf<T>(row: T, rowKey: RowKey<T>): unknown {
	// eslint-disable-next-line @typescript-eslint/no-explicit-any
	return typeof rowKey === 'function' ? rowKey(row) : (row as any)?.[rowKey];
}

/** The raw value a cell holds (row[column.key]) — what cell snippets receive
 *  and what sorting compares (absent a sortValue accessor). */
export function cellValue<T>(row: T, column: ColumnDef<T>): unknown {
	// eslint-disable-next-line @typescript-eslint/no-explicit-any
	return (row as any)?.[column.key];
}

/** The text a cell displays (and what global search matches against, even
 *  when a snippet renders the cell): the format() result when present, else
 *  the raw value stringified. */
export function cellText<T>(row: T, column: ColumnDef<T>): string {
	const raw = cellValue(row, column);
	if (column.format) return column.format(raw, row);
	return isBlank(raw) ? '' : String(raw);
}

/** Resolve every column's effective type against the data in one map (keyed by
 *  column.key): an explicit non-'auto' type is taken as-is, else inferred via
 *  inferColumnType (sampling the sortValue accessor when present). This is the
 *  same resolution DataTable does internally — call it once and hand the map to
 *  filterRows so the shared pipeline (charts, CSV, fake server) filters numbers
 *  and dates the same way the table does. */
export function resolveColumnTypes<T>(
	rows: readonly T[],
	columns: readonly ColumnDef<T>[]
): Record<string, ResolvedColumnType> {
	const map: Record<string, ResolvedColumnType> = {};
	for (const column of columns) {
		map[column.key] =
			!column.type || column.type === 'auto'
				? inferColumnType(rows, column.key, column.sortValue)
				: column.type;
	}
	return map;
}

type ComparisonOp = '=' | '!=' | '<' | '<=' | '>' | '>=' | 'in';

/** Numeric operand: strip thousands separators (commas/underscores/spaces) so
 *  "1,000,000" and "1_000_000" parse; blank → NaN (never Number('') === 0). */
function numberOperand(text: string): number {
	const cleaned = text.replace(/[,_\s]/g, '');
	return cleaned === '' ? NaN : Number(cleaned);
}

/**
 * Parse a number/date column filter into an operator + comparable operand(s),
 * or null when it isn't a typed expression (a bare date, a half-typed or
 * non-numeric fragment) — the caller then falls back to a substring match.
 * Grammar (whitespace-tolerant): `42` (bare → exact, numbers only),
 * `<42 <=42 >42 >=42 !=42 <>42 =42`, and `in(1, 2, 3)`. Date operands are
 * coerced to timestamps; number operands through numberOperand.
 */
function parseComparisonFilter(
	text: string,
	type: ResolvedColumnType
): { op: ComparisonOp; values: number[] } | null {
	const coerce = (s: string): number => (type === 'date' ? toTime(s.trim()) : numberOperand(s));

	const inMatch = /^in\s*\(([^)]*)\)$/i.exec(text);
	if (inMatch) {
		const values = inMatch[1].split(',').map(coerce).filter((n) => !Number.isNaN(n));
		return values.length ? { op: 'in', values } : null;
	}
	const opMatch = /^(<=|>=|!=|<>|<|>|=)\s*(.+)$/.exec(text);
	if (opMatch) {
		const op = (opMatch[1] === '<>' ? '!=' : opMatch[1]) as ComparisonOp;
		const value = coerce(opMatch[2]);
		return Number.isNaN(value) ? null : { op, values: [value] };
	}
	// A bare value is an exact match for numbers; on a date column it stays a
	// substring match (bare "2025"/"2025-06" narrow naturally — use =date for
	// an exact day), so return null and let the caller fall back.
	if (type === 'date') return null;
	const value = coerce(text);
	return Number.isNaN(value) ? null : { op: '=', values: [value] };
}

/**
 * Does a single cell satisfy one column filter? String columns: a
 * case-insensitive substring of the displayed text (`displayed`). Number/date
 * columns understand an operator grammar on the raw comparable value:
 *   42            exact match (number columns)
 *   <42 <=42 >42 >=42 !=42   inequality
 *   in(1, 2, 3)   membership in the listed set
 *   >2025-01-01, in(2025-01-01, 2025-06-18)   the same for date columns
 * Anything a number/date column can't parse as such (a bare date, a half-typed
 * or non-numeric fragment) falls back to the substring match, so typing never
 * snaps the table empty mid-keystroke. A blank/uncomparable cell (null, 'N/A',
 * invalid date) never satisfies a typed comparison.
 */
export function matchColumnFilter(
	rawValue: unknown,
	displayed: string,
	filterText: string,
	type: ResolvedColumnType
): boolean {
	const needle = filterText.trim();
	if (needle === '') return true;
	const substring = () => displayed.toLowerCase().includes(needle.toLowerCase());
	if (type !== 'number' && type !== 'date') return substring();

	const parsed = parseComparisonFilter(needle, type);
	if (!parsed) return substring();
	const x = type === 'date' ? toTime(rawValue) : toNumber(rawValue);
	if (Number.isNaN(x)) return false;
	switch (parsed.op) {
		case '=':
			return x === parsed.values[0];
		case '!=':
			return x !== parsed.values[0];
		case '<':
			return x < parsed.values[0];
		case '<=':
			return x <= parsed.values[0];
		case '>':
			return x > parsed.values[0];
		case '>=':
			return x >= parsed.values[0];
		case 'in':
			return parsed.values.includes(x);
	}
}

/**
 * Filter stage: global search AND per-column filters. The global search is
 * always a case-insensitive substring match against the displayed (formatted)
 * text of ANY visible column. Each non-blank column filter must ALSO match its
 * own column (AND composition) — via matchColumnFilter, so number/date columns
 * (per `columnTypes`, from resolveColumnTypes) accept operator expressions
 * (`>1000`, `!=0`, `in(1,2,3)`) while string columns stay substring matches.
 * Without a `columnTypes` entry a column filters as a string (backward
 * compatible). Filters keyed to unknown or hidden columns are ignored — hiding
 * a column suspends its filter (WYSIWYG: no invisible criteria). Empty search +
 * no active filters returns all rows.
 */
export function filterRows<T>(
	rows: readonly T[],
	search: string,
	columns: readonly ColumnDef<T>[],
	columnFilters: Record<string, string> = {},
	columnTypes: Record<string, ResolvedColumnType> = {}
): T[] {
	const needle = search.trim().toLowerCase();
	const searched = columns.filter((c) => c.visible !== false);
	const active = Object.entries(columnFilters)
		.map(([key, text]) => ({
			column: searched.find((c) => c.key === key),
			text
		}))
		.filter((f) => f.column !== undefined && f.text.trim() !== '');
	if (needle === '' && active.length === 0) return rows.slice();
	return rows.filter(
		(row) =>
			(needle === '' ||
				searched.some((column) => cellText(row, column).toLowerCase().includes(needle))) &&
			active.every((f) =>
				matchColumnFilter(
					cellValue(row, f.column!),
					cellText(row, f.column!),
					f.text,
					columnTypes[f.column!.key] ?? 'string'
				)
			)
	);
}

/**
 * Stable, non-mutating, type-aware sort. `direction: null` (or no descriptor)
 * returns the natural order. Blank/uncomparable values stay last regardless
 * of direction. Ties keep original order via index tagging (guaranteed stable
 * even if the engine's sort weren't). An optional getValue accessor (a
 * column's sortValue) supplies the compared value instead of row[sort.key] —
 * display and sort key stay independent.
 */
export function sortRows<T>(
	rows: readonly T[],
	sort: SortDescriptor | null,
	type: ResolvedColumnType,
	getValue?: (row: T) => unknown
): T[] {
	if (!sort || sort.direction === null) return rows.slice();
	const dir = sort.direction === 'asc' ? 1 : -1;
	return rows
		.map((row, index) => ({ row, index }))
		.sort((a, b) => {
			// eslint-disable-next-line @typescript-eslint/no-explicit-any
			const av = getValue ? getValue(a.row) : (a.row as any)?.[sort.key];
			// eslint-disable-next-line @typescript-eslint/no-explicit-any
			const bv = getValue ? getValue(b.row) : (b.row as any)?.[sort.key];
			const aLast = sortsLast(av, type);
			const bLast = sortsLast(bv, type);
			const c =
				aLast || bLast
					? aLast && bLast
						? 0
						: aLast
							? 1
							: -1 // not flipped by dir: last is last in both directions
					: dir * compareValues(av, bv, type);
			return c !== 0 ? c : a.index - b.index;
		})
		.map((tagged) => tagged.row);
}

/**
 * CSV for the given rows over the visible columns: a header row of column
 * labels, then one line per row using the displayed text (format applied via
 * cellText). Pass the FILTERED+SORTED set — what the user sees across all
 * pages — not just the current page. RFC 4180 quoting: fields containing
 * commas, quotes, or line breaks are wrapped in quotes with inner quotes
 * doubled; CRLF row endings so Excel opens it cleanly.
 */
export function exportCsv<T>(rows: readonly T[], columns: readonly ColumnDef<T>[]): string {
	const exported = columns.filter((c) => c.visible !== false);
	const escape = (text: string): string =>
		/[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
	const lines = [
		exported.map((column) => escape(column.label)).join(','),
		...rows.map((row) => exported.map((column) => escape(cellText(row, column))).join(','))
	];
	return lines.join('\r\n') + '\r\n';
}

/** Total pages for a result set — never less than 1, so an empty set still
 *  has a "page 1" to stand on. */
export function pageCount(total: number, pageSize: number): number {
	if (pageSize <= 0) return 1;
	return Math.max(1, Math.ceil(total / pageSize));
}

/** Snap a requested page into [1, pageCount] — e.g. page 9 of 3 → 3. */
export function clampPage(page: number, total: number, pageSize: number): number {
	if (!Number.isFinite(page)) return 1;
	return Math.min(Math.max(1, Math.floor(page)), pageCount(total, pageSize));
}

/** One page of rows. The page is clamped first, so a stale page number after
 *  a filter change still yields a valid (last) page rather than an empty slice. */
export function paginateRows<T>(rows: readonly T[], page: number, pageSize: number): T[] {
	if (pageSize <= 0) return rows.slice();
	const p = clampPage(page, rows.length, pageSize);
	const start = (p - 1) * pageSize;
	return rows.slice(start, start + pageSize);
}

/** 1-based inclusive bounds for the "Showing X–Y of Z entries" readout
 *  ({start: 0, end: 0} when there are no rows). */
export function pageWindow(
	page: number,
	pageSize: number,
	total: number
): { start: number; end: number } {
	if (total === 0) return { start: 0, end: 0 };
	if (pageSize <= 0) return { start: 1, end: total };
	const p = clampPage(page, total, pageSize);
	return { start: (p - 1) * pageSize + 1, end: Math.min(p * pageSize, total) };
}
