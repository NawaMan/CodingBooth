<!--
  Test fixture: hosts a selectable DataTable with bind:selected so tests can
  observe the selection (rows, keyed by rowKey) across paging and sorting.
-->
<script lang="ts">
	import DataTable from '../src/lib/datatable/DataTable.svelte';
	import type { ColumnDef, RowKey } from '../src/lib/datatable/types';

	let {
		rows = [],
		columns = [],
		pageSize = 5,
		rowKey = 'name'
	}: {
		// eslint-disable-next-line @typescript-eslint/no-explicit-any
		rows?: any[];
		columns?: ColumnDef[];
		pageSize?: number;
		rowKey?: RowKey;
	} = $props();

	// eslint-disable-next-line @typescript-eslint/no-explicit-any
	let selected = $state<any[]>([]);

	// eslint-disable-next-line @typescript-eslint/no-explicit-any
	export function getSelected(): any[] {
		return $state.snapshot(selected);
	}
</script>

<DataTable {rows} {columns} {pageSize} selectable {rowKey} bind:selected />
