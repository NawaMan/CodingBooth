<!--
  Test fixture: a ColumnToggle and a DataTable sharing one bound columns
  array, so tests can verify that toggling visibility updates the table.
-->
<script lang="ts">
	import ColumnToggle from '../src/lib/datatable/ColumnToggle.svelte';
	import DataTable from '../src/lib/datatable/DataTable.svelte';
	import type { ColumnDef } from '../src/lib/datatable/types';

	let {
		rows = [],
		columns: initial = []
	}: {
		// eslint-disable-next-line @typescript-eslint/no-explicit-any
		rows?: any[];
		columns?: ColumnDef[];
	} = $props();

	// svelte-ignore state_referenced_locally
	let columns = $state<ColumnDef[]>([...initial]);
</script>

<ColumnToggle bind:columns />
<DataTable {rows} {columns} />
