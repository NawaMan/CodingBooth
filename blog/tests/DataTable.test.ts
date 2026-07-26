import { fireEvent, render, screen } from '@testing-library/svelte';
import { createRawSnippet } from 'svelte';
import { describe, expect, it } from 'vitest';
import BindStateHost from './BindStateHost.svelte';
import SelectHost from './SelectHost.svelte';
import ToggleHost from './ToggleHost.svelte';
import DataTable from '../src/lib/datatable/DataTable.svelte';
import type { ColumnDef, TableState } from '../src/lib/datatable/types';

type Person = { name: string; score: number | null; joined: string | null };

const people: Person[] = Array.from({ length: 15 }, (_, i) => ({
	name: `Person ${i + 1}`,
	score: i === 3 ? null : (i * 7) % 60,
	joined: i === 5 ? null : `2024-0${(i % 9) + 1}-15`
}));

// ColumnDef<any> — testing-library's render() can't infer the component generic
const columns: ColumnDef[] = [
	{ key: 'name', label: 'Name' },
	{ key: 'score', label: 'Score', format: (v) => (v === null ? '—' : `${v} pts`) },
	{ key: 'joined', label: 'Joined' }
];

function rowsOf(container: HTMLElement): HTMLTableRowElement[] {
	return Array.from(container.querySelectorAll('tbody tr'));
}

describe('DataTable', () => {
	it('renders a semantic table with headers and one page of formatted rows', () => {
		const { container } = render(DataTable, { rows: people, columns });

		expect(container.querySelector('table thead')).not.toBeNull();
		const headers = Array.from(container.querySelectorAll('th[scope="col"]'));
		expect(headers.map((h) => h.textContent?.trim())).toEqual(['Name', 'Score', 'Joined']);

		// default pageSize 10 of 15 rows
		expect(rowsOf(container)).toHaveLength(10);
		expect(screen.getByText('Person 1')).toBeTruthy();
		expect(screen.getByText('0 pts')).toBeTruthy(); // format() applied
		expect(screen.getByText('—')).toBeTruthy(); // null formatted, not "null"
	});

	it('sorts on header click through the asc → desc → none cycle', async () => {
		const { container } = render(DataTable, {
			rows: [
				{ name: 'b', score: 100, joined: null },
				{ name: 'c', score: 2, joined: null },
				{ name: 'a', score: 10, joined: null }
			],
			columns
		});
		const scoreTh = Array.from(container.querySelectorAll('th')).find((th) =>
			th.textContent?.includes('Score')
		)!;
		const scoreButton = scoreTh.querySelector('button')!;
		const firstColumn = () => rowsOf(container).map((tr) => tr.cells[0].textContent);

		expect(firstColumn()).toEqual(['b', 'c', 'a']); // natural order

		await fireEvent.click(scoreButton); // asc: 2 < 10 < 100, numerically
		expect(firstColumn()).toEqual(['c', 'a', 'b']);
		expect(scoreTh.getAttribute('aria-sort')).toBe('ascending');

		await fireEvent.click(scoreButton); // desc
		expect(firstColumn()).toEqual(['b', 'a', 'c']);
		expect(scoreTh.getAttribute('aria-sort')).toBe('descending');

		await fireEvent.click(scoreButton); // back to natural order exactly
		expect(firstColumn()).toEqual(['b', 'c', 'a']);
		expect(scoreTh.getAttribute('aria-sort')).toBeNull();
	});

	it('filters rows from the debounced search box', async () => {
		const { container } = render(DataTable, { rows: people, columns });
		const input = screen.getByLabelText('Search') as HTMLInputElement;

		await fireEvent.input(input, { target: { value: 'Person 12' } });
		// debounced: nothing filtered yet
		expect(rowsOf(container)).toHaveLength(10);

		await new Promise((resolve) => setTimeout(resolve, 350));
		expect(rowsOf(container)).toHaveLength(1);
		expect(rowsOf(container)[0].cells[0].textContent).toBe('Person 12');

		await fireEvent.input(input, { target: { value: '' } });
		await new Promise((resolve) => setTimeout(resolve, 350));
		expect(rowsOf(container)).toHaveLength(10);
	});

	it('paginates with a correct readout and page-size select', async () => {
		const { container } = render(DataTable, { rows: people, columns });
		const readout = () => container.querySelector('.readout')?.textContent;

		expect(readout()).toBe('Showing 1–10 of 15 entries');

		await fireEvent.click(screen.getByLabelText('Next page'));
		expect(readout()).toBe('Showing 11–15 of 15 entries');
		expect(rowsOf(container)).toHaveLength(5);

		await fireEvent.click(screen.getByLabelText('Next page')); // guarded: already last
		expect(readout()).toBe('Showing 11–15 of 15 entries');

		await fireEvent.click(screen.getByLabelText('Previous page'));
		expect(readout()).toBe('Showing 1–10 of 15 entries');

		const select = screen.getByLabelText('Rows per page') as HTMLSelectElement;
		await fireEvent.change(select, { target: { value: '25' } });
		expect(rowsOf(container)).toHaveLength(15);
		expect(readout()).toBe('Showing 1–15 of 15 entries');
	});

	it('keeps state coherent through search → page → clear search', async () => {
		const { container } = render(DataTable, {
			rows: people,
			columns,
			pageSize: 3
		});
		const input = screen.getByLabelText('Search') as HTMLInputElement;
		const readout = () => container.querySelector('.readout')?.textContent;

		// go deep, then filter down to fewer pages → page snaps back into range
		for (let i = 0; i < 4; i++) await fireEvent.click(screen.getByLabelText('Next page'));
		expect(readout()).toBe('Showing 13–15 of 15 entries');

		await fireEvent.input(input, { target: { value: 'Person 1' } });
		await new Promise((resolve) => setTimeout(resolve, 350));
		// matches Person 1, 10–15 → 7 rows, and page reset to 1
		expect(readout()).toBe('Showing 1–3 of 7 entries');

		await fireEvent.click(screen.getByLabelText('Next page'));
		expect(readout()).toBe('Showing 4–6 of 7 entries');

		await fireEvent.input(input, { target: { value: '' } });
		await new Promise((resolve) => setTimeout(resolve, 350));
		expect(readout()).toBe('Showing 1–3 of 15 entries'); // no out-of-range page
	});

	it('distinguishes "No data" from "No results found"', async () => {
		const empty = render(DataTable, { rows: [], columns });
		expect(empty.container.querySelector('tbody')?.textContent).toContain('No data');
		expect(empty.container.querySelector('.readout')?.textContent).toBe('Showing 0–0 of 0 entries');
		empty.unmount();

		const { container } = render(DataTable, { rows: people, columns });
		await fireEvent.input(screen.getByLabelText('Search'), { target: { value: 'zzz-no-hit' } });
		await new Promise((resolve) => setTimeout(resolve, 350));
		expect(container.querySelector('tbody')?.textContent).toContain('No results found');
	});

	it('caps the body at maxHeight so large page sizes scroll instead of growing', () => {
		const { container } = render(DataTable, {
			rows: people,
			columns,
			pageSize: 50,
			maxHeight: '560px'
		});
		const scroll = container.querySelector('.scroll') as HTMLElement;
		expect(scroll.style.maxHeight).toBe('560px');
		expect(rowsOf(container)).toHaveLength(15); // all rows in the scroll container
	});

	it('sorts a column by its sortValue accessor (pending as latest)', async () => {
		const { container } = render(DataTable, {
			rows: [
				{ name: 'old', when: '2023-01-01' },
				{ name: 'wip', when: 'pending' },
				{ name: 'new', when: '2025-06-01' }
			],
			columns: [
				{ key: 'name', label: 'Name' },
				{
					key: 'when',
					label: 'When',
					type: 'date',
					sortValue: (r: { when: string }) => (r.when === 'pending' ? '9999-12-31' : r.when)
				}
			] as ColumnDef[]
		});
		const whenButton = Array.from(container.querySelectorAll('th button')).find((b) =>
			b.textContent?.includes('When')
		)!;
		const firstColumn = () => rowsOf(container).map((tr) => tr.cells[0].textContent);

		await fireEvent.click(whenButton); // asc: oldest → newest → pending
		expect(firstColumn()).toEqual(['old', 'new', 'wip']);

		await fireEvent.click(whenButton); // desc (newest-first): pending leads
		expect(firstColumn()).toEqual(['wip', 'new', 'old']);
	});

	it('fixes the body height so filtered-down results do not shrink the table', async () => {
		const { container } = render(DataTable, { rows: people, columns, height: '400px' });
		const scroll = container.querySelector('.scroll') as HTMLElement;
		expect(scroll.style.height).toBe('400px');

		await fireEvent.input(screen.getByLabelText('Search'), { target: { value: 'Person 12' } });
		await new Promise((resolve) => setTimeout(resolve, 350));
		expect(rowsOf(container)).toHaveLength(1);
		expect(scroll.style.height).toBe('400px'); // container height unchanged
	});

	it('stripes alternate rows when striped is set', () => {
		const { container } = render(DataTable, { rows: people, columns, striped: true });
		const stripes = rowsOf(container).map((tr) => tr.classList.contains('stripe'));
		expect(stripes.slice(0, 4)).toEqual([false, true, false, true]);

		const plain = render(DataTable, { rows: people, columns });
		expect(rowsOf(plain.container).some((tr) => tr.classList.contains('stripe'))).toBe(false);
	});

	it('overlays a loading indicator without collapsing the table', () => {
		const { container } = render(DataTable, { rows: people, columns, loading: true });
		expect(container.querySelector('[role="status"]')?.textContent).toContain('Loading');
		expect(rowsOf(container)).toHaveLength(10); // rows still rendered underneath
	});
});

describe('DataTable cell snippets', () => {
	type Service = { name: string; status: string; cost: number };
	const services: Service[] = [
		{ name: 'api', status: 'up', cost: 20 },
		{ name: 'db', status: 'down', cost: 3 },
		{ name: 'web', status: 'up', cost: 100 }
	];
	const serviceColumns: ColumnDef[] = [
		{ key: 'name', label: 'Name' },
		// format present too — the snippet must win (precedence snippet > format > raw)
		{ key: 'status', label: 'Status', format: () => 'format-loses' },
		{ key: 'cost', label: 'Cost', format: (v) => `$${v}.00` }
	];
	// createRawSnippet params arrive as getters: (row, value, rowIndex).
	// row is `() => unknown` because render() can't infer the component generic.
	const badge = createRawSnippet(
		(_row: () => unknown, value: () => unknown, rowIndex: () => number) => ({
			render: () =>
				`<span class="badge badge-${value()}" data-row-index="${rowIndex()}">${value()}</span>`
		})
	);

	it('renders cells via the snippets map with (row, value, rowIndex), beating format', () => {
		const { container } = render(DataTable, {
			rows: services,
			columns: serviceColumns,
			snippets: { status: badge }
		});

		const badges = Array.from(container.querySelectorAll('tbody .badge'));
		expect(badges.map((b) => b.textContent)).toEqual(['up', 'down', 'up']); // raw value, not format()
		expect(badges.map((b) => b.className)).toEqual(['badge badge-up', 'badge badge-down', 'badge badge-up']);
		expect(badges.map((b) => b.getAttribute('data-row-index'))).toEqual(['0', '1', '2']);
		expect(container.textContent).not.toContain('format-loses');
	});

	it('sorts snippet and format columns by the raw value, not the displayed text', async () => {
		const { container } = render(DataTable, {
			rows: services,
			columns: serviceColumns,
			snippets: { status: badge }
		});
		const names = () => rowsOf(container).map((tr) => tr.cells[0].textContent);
		const buttonFor = (label: string) =>
			Array.from(container.querySelectorAll('th button')).find((b) =>
				b.textContent?.includes(label)
			)!;

		// cost displays "$20.00" etc. but sorts numerically: 3 < 20 < 100
		await fireEvent.click(buttonFor('Cost'));
		expect(names()).toEqual(['db', 'api', 'web']);
		expect(rowsOf(container).map((tr) => tr.cells[2].textContent?.trim())).toEqual([
			'$3.00',
			'$20.00',
			'$100.00'
		]);

		// snippet column sorts by its raw value too
		await fireEvent.click(buttonFor('Status'));
		expect(names()).toEqual(['db', 'api', 'web']); // down < up (asc), ties keep order
	});

	it('matches global search against the formatted text, even for snippet cells', async () => {
		const { container } = render(DataTable, {
			rows: services,
			columns: serviceColumns,
			snippets: { status: badge }
		});
		const input = screen.getByLabelText('Search') as HTMLInputElement;

		await fireEvent.input(input, { target: { value: '$100' } }); // format() output
		await new Promise((resolve) => setTimeout(resolve, 350));
		expect(rowsOf(container).map((tr) => tr.cells[0].textContent)).toEqual(['web']);
	});

	it('renders the empty snippet instead of "No results found"', async () => {
		const emptySnippet = createRawSnippet(() => ({
			render: () => `<em class="custom-empty">Nothing matched, sorry!</em>`
		}));
		const { container } = render(DataTable, {
			rows: services,
			columns: serviceColumns,
			empty: emptySnippet
		});

		await fireEvent.input(screen.getByLabelText('Search'), { target: { value: 'zzz-no-hit' } });
		await new Promise((resolve) => setTimeout(resolve, 350));
		expect(container.querySelector('tbody .custom-empty')?.textContent).toBe(
			'Nothing matched, sorry!'
		);
		expect(container.textContent).not.toContain('No results found');
	});
});

describe('DataTable bind:state (controlled mode)', () => {
	const hostProps = { rows: people, columns };
	const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

	it('follows external state changes: page, search, sort', async () => {
		const { container, component } = render(BindStateHost, hostProps);
		const readout = () => container.querySelector('.readout')?.textContent;
		const names = () => rowsOf(container).map((tr) => tr.cells[0].textContent);

		expect(readout()).toBe('Showing 1–5 of 15 entries'); // host pageSize 5

		component.setState({ page: 3 });
		await flush();
		expect(readout()).toBe('Showing 11–15 of 15 entries');

		// external search needs no debounce — it drives the table directly
		component.setState({ search: 'Person 12', page: 1 });
		await flush();
		expect(names()).toEqual(['Person 12']);

		component.setState({ search: '', sort: { key: 'name', direction: 'desc' } });
		await flush();
		expect(names()[0]).toBe('Person 15'); // natural desc: 15 > 14 > … (numeric, not lexicographic)
		const nameTh = container.querySelector('th[aria-sort]');
		expect(nameTh?.getAttribute('aria-sort')).toBe('descending'); // UI reflects external sort
	});

	it('writes internal changes back to the bound parent state', async () => {
		const { container, component } = render(BindStateHost, hostProps);

		const nameButton = Array.from(container.querySelectorAll('th button')).find((b) =>
			b.textContent?.includes('Name')
		)!;
		await fireEvent.click(nameButton);
		expect(component.getState().sort).toEqual({ key: 'name', direction: 'asc' });

		await fireEvent.click(screen.getByLabelText('Next page'));
		expect(component.getState().page).toBe(2);

		const select = screen.getByLabelText('Rows per page') as HTMLSelectElement;
		await fireEvent.change(select, { target: { value: '10' } });
		expect(component.getState().pageSize).toBe(10);
	});

	it('accepts an initial state prop without binding', () => {
		const initial: TableState = {
			sort: null,
			search: '',
			columnFilters: {},
			page: 2,
			pageSize: 5
		};
		const { container } = render(DataTable, { rows: people, columns, state: initial });
		expect(container.querySelector('.readout')?.textContent).toBe('Showing 6–10 of 15 entries');
	});
});

describe('DataTable server mode', () => {
	const serverState: TableState = {
		sort: { key: 'name', direction: 'desc' },
		search: 'Person',
		columnFilters: {},
		page: 2,
		pageSize: 5
	};

	it('renders rows verbatim — no filtering, sorting, or paging applied', () => {
		// state says: sort desc, search "Person", pageSize 5 — none of it may
		// touch the rows; the server already applied it.
		const { container } = render(DataTable, {
			rows: people.slice(0, 8), // "the server's page": 8 rows, unsorted
			columns,
			mode: 'server',
			totalCount: 95,
			state: serverState
		});

		const names = rowsOf(container).map((tr) => tr.cells[0].textContent);
		expect(names).toEqual(people.slice(0, 8).map((p) => p.name)); // original order, all 8
	});

	it('honors totalCount for the readout and page math', () => {
		const { container } = render(DataTable, {
			rows: people.slice(0, 5),
			columns,
			mode: 'server',
			totalCount: 95,
			state: serverState
		});

		expect(container.querySelector('.readout')?.textContent).toBe('Showing 6–10 of 95 entries');
		expect(container.textContent).toContain('Page 2 of 19');
	});

	it('emits onstatechange for sort, search, and paging interactions', async () => {
		const emitted: TableState[] = [];
		const { container } = render(DataTable, {
			rows: people.slice(0, 5),
			columns,
			mode: 'server',
			totalCount: 95,
			state: serverState,
			onstatechange: (s: TableState) => emitted.push(s)
		});

		await fireEvent.click(screen.getByLabelText('Next page'));
		expect(emitted.at(-1)?.page).toBe(3);

		const nameButton = Array.from(container.querySelectorAll('th button')).find((b) =>
			b.textContent?.includes('Name')
		)!;
		await fireEvent.click(nameButton); // desc → none (cycle), back to page 1
		expect(emitted.at(-1)?.sort).toBeNull();
		expect(emitted.at(-1)?.page).toBe(1);

		await fireEvent.input(screen.getByLabelText('Search'), { target: { value: 'node' } });
		await new Promise((resolve) => setTimeout(resolve, 350)); // debounce
		expect(emitted.at(-1)?.search).toBe('node');
	});

	it('shows "No results found" when a server search comes back empty', () => {
		const { container } = render(DataTable, {
			rows: [],
			columns,
			mode: 'server',
			totalCount: 0,
			state: { ...serverState, search: 'zzz-no-hit', page: 1 }
		});
		expect(container.querySelector('tbody')?.textContent).toContain('No results found');
	});
});

describe('DataTable per-column filters', () => {
	const staff = [
		{ name: 'Alice Smith', region: 'east' },
		{ name: 'Bob Smith', region: 'west' },
		{ name: 'Cara Jones', region: 'east' },
		{ name: 'Dan Smith', region: 'east' }
	];
	const staffColumns: ColumnDef[] = [
		{ key: 'name', label: 'Name' },
		{ key: 'region', label: 'Region', filterable: true }
	];
	const names = (container: HTMLElement) =>
		rowsOf(container).map((tr) => tr.cells[0].textContent);

	it('column filter + global search return the intersection', async () => {
		const { container } = render(DataTable, { rows: staff, columns: staffColumns });

		await fireEvent.input(screen.getByLabelText('Filter Region'), { target: { value: 'east' } });
		await new Promise((resolve) => setTimeout(resolve, 350)); // debounced
		expect(names(container)).toEqual(['Alice Smith', 'Cara Jones', 'Dan Smith']);

		await fireEvent.input(screen.getByLabelText('Search'), { target: { value: 'smith' } });
		await new Promise((resolve) => setTimeout(resolve, 350));
		expect(names(container)).toEqual(['Alice Smith', 'Dan Smith']); // east ∩ smith

		await fireEvent.input(screen.getByLabelText('Filter Region'), { target: { value: '' } });
		await new Promise((resolve) => setTimeout(resolve, 350));
		expect(names(container)).toEqual(['Alice Smith', 'Bob Smith', 'Dan Smith']);
	});

	it('renders filter inputs only for filterable columns, and no row without any', () => {
		const withFilter = render(DataTable, { rows: staff, columns: staffColumns });
		expect(withFilter.container.querySelectorAll('.column-filter')).toHaveLength(1);
		expect(screen.getByLabelText('Filter Region')).toBeTruthy();
		withFilter.unmount();

		const { container } = render(DataTable, { rows: staff, columns: staffColumns.map((c) => ({ ...c, filterable: false })) });
		expect(container.querySelector('.filter-row')).toBeNull();
	});

	it('snaps back to page 1 when a column filter changes', async () => {
		const { container } = render(DataTable, {
			rows: people,
			columns: [
				{ key: 'name', label: 'Name', filterable: true },
				{ key: 'score', label: 'Score' }
			] as ColumnDef[],
			pageSize: 3
		});
		const readout = () => container.querySelector('.readout')?.textContent;

		await fireEvent.click(screen.getByLabelText('Next page'));
		expect(readout()).toBe('Showing 4–6 of 15 entries');

		await fireEvent.input(screen.getByLabelText('Filter Name'), { target: { value: 'Person 1' } });
		await new Promise((resolve) => setTimeout(resolve, 350));
		expect(readout()).toBe('Showing 1–3 of 7 entries'); // Person 1, 10–15
	});
});

describe('DataTable row selection', () => {
	const hostProps = { rows: people, columns, pageSize: 5 }; // rowKey 'name' (host default)
	const selectAll = () =>
		screen.getByLabelText('Select all rows on this page') as HTMLInputElement;
	const rowCheckboxes = (container: HTMLElement) =>
		Array.from(container.querySelectorAll('tbody input[type="checkbox"]')) as HTMLInputElement[];

	it('select-all selects only the current page and survives page changes', async () => {
		const { container, component } = render(SelectHost, hostProps);

		await fireEvent.click(selectAll());
		expect(component.getSelected().map((r: { name: string }) => r.name)).toEqual(
			people.slice(0, 5).map((p) => p.name) // page 1 only, not all 15
		);
		expect(selectAll().checked).toBe(true);
		expect(selectAll().indeterminate).toBe(false);

		await fireEvent.click(screen.getByLabelText('Next page'));
		// page 2: nothing selected here — header unchecked, rows unchecked
		expect(selectAll().checked).toBe(false);
		expect(rowCheckboxes(container).every((cb) => !cb.checked)).toBe(true);

		await fireEvent.click(screen.getByLabelText('Previous page'));
		// selection survived the round trip
		expect(selectAll().checked).toBe(true);
		expect(rowCheckboxes(container).every((cb) => cb.checked)).toBe(true);
		expect(component.getSelected()).toHaveLength(5);
	});

	it('is indeterminate when only some page rows are selected', async () => {
		const { container } = render(SelectHost, hostProps);

		await fireEvent.click(rowCheckboxes(container)[1]);
		expect(selectAll().checked).toBe(false);
		expect(selectAll().indeterminate).toBe(true);

		await fireEvent.click(rowCheckboxes(container)[1]); // deselect again
		expect(selectAll().indeterminate).toBe(false);
	});

	it('keeps identity by rowKey across re-sorting, not by index', async () => {
		const { container, component } = render(SelectHost, hostProps);

		// select the first visible row: Person 1
		await fireEvent.click(screen.getByLabelText('Select row Person 1'));
		expect(component.getSelected().map((r: { name: string }) => r.name)).toEqual(['Person 1']);

		// sort by name desc — natural sort puts Person 15..11 on page 1
		const nameButton = Array.from(container.querySelectorAll('th button')).find((b) =>
			b.textContent?.includes('Name')
		)!;
		await fireEvent.click(nameButton);
		await fireEvent.click(nameButton);

		// index 0 now holds a different row and must NOT be selected
		expect(rowCheckboxes(container)[0].checked).toBe(false);
		expect(component.getSelected().map((r: { name: string }) => r.name)).toEqual(['Person 1']);

		// Person 1 is on the last page now; its checkbox is still checked
		while (!screen.queryByLabelText('Select row Person 1')) {
			await fireEvent.click(screen.getByLabelText('Next page'));
		}
		expect((screen.getByLabelText('Select row Person 1') as HTMLInputElement).checked).toBe(true);
	});

	it('deselecting via select-all removes only this page from the selection', async () => {
		const { component } = render(SelectHost, hostProps);

		await fireEvent.click(selectAll()); // page 1 selected (5 rows)
		await fireEvent.click(screen.getByLabelText('Next page'));
		await fireEvent.click(selectAll()); // page 2 selected too (10 total)
		expect(component.getSelected()).toHaveLength(10);

		await fireEvent.click(selectAll()); // deselect page 2 only
		expect(component.getSelected()).toHaveLength(5);
		expect(
			component.getSelected().map((r: { name: string }) => r.name)
		).toEqual(people.slice(0, 5).map((p) => p.name));
	});

	it('renders no checkbox column unless selectable', () => {
		const { container } = render(DataTable, { rows: people, columns });
		expect(container.querySelector('input[type="checkbox"]')).toBeNull();
	});
});

describe('DataTable column visibility', () => {
	const headerLabels = (container: HTMLElement) =>
		Array.from(container.querySelectorAll('thead tr:first-child th')).map((th) =>
			th.textContent?.trim()
		);

	it('respects visible: false on a ColumnDef', () => {
		const { container } = render(DataTable, {
			rows: people,
			columns: columns.map((c) => (c.key === 'score' ? { ...c, visible: false } : c))
		});
		expect(headerLabels(container)).toEqual(['Name', 'Joined']);
		expect(rowsOf(container)[0].cells).toHaveLength(2);
	});

	it('ColumnToggle hides and shows a column through the bound columns array', async () => {
		const { container } = render(ToggleHost, { rows: people, columns });
		const toggleFor = (label: string) =>
			Array.from(container.querySelectorAll('.column-toggle .option')).find((option) =>
				option.textContent?.includes(label)
			)!.querySelector('input') as HTMLInputElement;

		expect(headerLabels(container)).toEqual(['Name', 'Score', 'Joined']);
		expect(toggleFor('Score').checked).toBe(true);

		await fireEvent.click(toggleFor('Score'));
		expect(headerLabels(container)).toEqual(['Name', 'Joined']);
		expect(rowsOf(container)[0].cells).toHaveLength(2);
		expect(toggleFor('Score').checked).toBe(false);

		await fireEvent.click(toggleFor('Score')); // show it again
		expect(headerLabels(container)).toEqual(['Name', 'Score', 'Joined']);
		expect(rowsOf(container)[0].cells).toHaveLength(3);
	});

	it('hides a filterable column together with its filter input', async () => {
		const { container } = render(ToggleHost, {
			rows: people,
			columns: columns.map((c) => (c.key === 'name' ? { ...c, filterable: true } : c))
		});
		expect(screen.getByLabelText('Filter Name')).toBeTruthy();

		const nameToggle = Array.from(container.querySelectorAll('.column-toggle .option'))
			.find((option) => option.textContent?.includes('Name'))!
			.querySelector('input') as HTMLInputElement;
		await fireEvent.click(nameToggle);
		expect(screen.queryByLabelText('Filter Name')).toBeNull();
		expect(container.querySelector('.filter-row')).toBeNull(); // no other filterable column
	});
});

describe('DataTable header snippets', () => {
	const fancy = createRawSnippet((column: () => ColumnDef) => ({
		render: () => `<span class="fancy-th">★ ${column().label}</span>`
	}));

	it('renders custom header content inside the sort button; sorting still works', async () => {
		const { container } = render(DataTable, {
			rows: people,
			columns,
			headerSnippets: { score: fancy }
		});

		const fancyTh = container.querySelector('th .fancy-th');
		expect(fancyTh?.textContent).toBe('★ Score'); // receives the ColumnDef
		expect(fancyTh?.closest('button')).not.toBeNull(); // inside the sort button

		await fireEvent.click(fancyTh!.closest('button')!);
		expect(fancyTh?.closest('th')?.getAttribute('aria-sort')).toBe('ascending');
	});

	it('renders bare header content for non-sortable columns', () => {
		const { container } = render(DataTable, {
			rows: people,
			columns: [{ key: 'name', label: 'Name', sortable: false }] as ColumnDef[],
			headerSnippets: { name: fancy }
		});

		const fancyTh = container.querySelector('th .fancy-th');
		expect(fancyTh?.textContent).toBe('★ Name');
		expect(fancyTh?.closest('button')).toBeNull(); // no button when unsortable
	});
});
