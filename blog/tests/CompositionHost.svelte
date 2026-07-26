<!-- Composition fixture: a DataTable and a BarChart driven by ONE dataset and
     ONE shared TableState/selection, mirroring the datatable-chart slide. The
     chart derives from `visibleRows` (the table's own pure filterRows/sortRows)
     via aggregate, and highlights the regions of the selected rows — proving the
     two move together with no coupling. -->
<script lang="ts">
	import {
		DataTable,
		filterRows,
		sortRows,
		type ColumnDef,
		type TableState
	} from '../src/lib/datatable';
	import BarChart from '../src/lib/chart/BarChart.svelte';
	import { aggregate, sumOf } from '../src/lib/chart/chartCore';

	type Row = { id: number; region: string; requests: number };
	const rows: Row[] = [
		{ id: 1, region: 'us-east', requests: 100 },
		{ id: 2, region: 'us-west', requests: 200 },
		{ id: 3, region: 'eu', requests: 300 }
	];
	const columns: ColumnDef<Row>[] = [
		{ key: 'id', label: 'ID' },
		{ key: 'region', label: 'Region', filterable: true },
		{ key: 'requests', label: 'Requests', type: 'number' }
	];

	let tableState = $state<TableState>({
		sort: null,
		search: '',
		columnFilters: {},
		page: 1,
		pageSize: 10
	});
	let selected = $state<Row[]>([]);

	// The table's own pipeline, reused outside it — the charts sit downstream.
	const visibleRows = $derived(
		sortRows(filterRows(rows, tableState.search, columns), null, 'string')
	);
	const byRegion = $derived(aggregate(visibleRows, 'region', { value: sumOf('requests') }));
	const selectedRegions = $derived([...new Set(selected.map((r) => r.region))]);
</script>

<DataTable {rows} {columns} bind:state={tableState} selectable rowKey="id" bind:selected />
<BarChart
	data={byRegion}
	x={{ value: 'group' }}
	series={[{ key: 'value', label: 'Requests', value: 'value' }]}
	rowKeyAccessor="group"
	highlighted={selectedRegions}
	title="Requests by region"
/>
