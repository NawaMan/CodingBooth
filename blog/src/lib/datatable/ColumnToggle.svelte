<!--
  Column-visibility toggle for DataTable: one checkbox per column, flipping
  ColumnDef.visible on a BOUND columns array (bind:columns) — pass the same
  array to the DataTable and it reacts instantly. Toggling reassigns the
  array (new column object), it never mutates in place, so plain $state in
  the parent works. Hiding a column also suspends its column filter and
  drops it from global search and CSV export (see filterRows/exportCsv).
  Themed with the same --dt-* custom properties as the table.
-->
<script lang="ts" generics="T">
	import type { ColumnDef } from './types';

	let {
		columns = $bindable([]),
		label = 'Columns'
	}: {
		/** The table's column config (bind:columns) — shared with DataTable. */
		columns?: ColumnDef<T>[];
		/** Group label shown before the checkboxes (also the fieldset legend). */
		label?: string;
	} = $props();

	function toggle(key: string) {
		columns = columns.map((column) =>
			column.key === key ? { ...column, visible: column.visible === false } : column
		);
	}
</script>

<fieldset class="column-toggle">
	<legend>{label}</legend>
	{#each columns as column (column.key)}
		<label class="option">
			<input
				type="checkbox"
				checked={column.visible !== false}
				onchange={() => toggle(column.key)}
			/>
			{column.label}
		</label>
	{/each}
</fieldset>

<style>
	.column-toggle {
		display: inline-flex;
		align-items: center;
		flex-wrap: wrap;
		gap: 0.2em 0.9em;
		margin: 0;
		padding: 0.25em 0.7em 0.35em;
		border: 1px solid var(--dt-border, rgba(128, 128, 128, 0.35));
		border-radius: 6px;
		font-size: 1em;
	}
	legend {
		padding: 0 0.35em;
		font-size: 0.85em;
		font-weight: 700;
		opacity: 0.8;
	}
	.option {
		display: inline-flex;
		align-items: center;
		gap: 0.35em;
		cursor: pointer;
		white-space: nowrap;
	}
	.option input {
		accent-color: var(--dt-accent, #4a9eda);
		cursor: pointer;
	}
	.option input:focus-visible {
		outline: 2px solid var(--dt-accent, #4a9eda);
		outline-offset: 1px;
	}
</style>
