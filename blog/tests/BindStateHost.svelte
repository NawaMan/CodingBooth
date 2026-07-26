<!--
  Test fixture: hosts a DataTable with bind:state so tests can drive the
  table by mutating the parent's state (controlled mode) and observe
  write-backs from internal changes (sort clicks, paging).
-->
<script lang="ts">
	import DataTable from '../src/lib/datatable/DataTable.svelte';
	import type { ColumnDef, TableState } from '../src/lib/datatable/types';

	let {
		rows = [],
		columns = []
	}: {
		// eslint-disable-next-line @typescript-eslint/no-explicit-any
		rows?: any[];
		columns?: ColumnDef[];
	} = $props();

	let tableState = $state<TableState>({
		sort: null,
		search: '',
		columnFilters: {},
		page: 1,
		pageSize: 5
	});

	export function getState(): TableState {
		return $state.snapshot(tableState) as TableState;
	}

	export function setState(next: Partial<TableState>) {
		tableState = { ...tableState, ...next };
	}
</script>

<DataTable {rows} {columns} bind:state={tableState} />
