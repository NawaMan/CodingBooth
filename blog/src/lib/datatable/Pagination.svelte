<!--
  Pagination bar for DataTable: page-size select, "Showing X–Y of Z entries"
  readout (aria-live) and prev/next controls. Purely presentational — page
  math (clamping, windows) lives in tableCore; state lives in DataTable.
  Buttons use aria-disabled + a guard instead of `disabled` so keyboard focus
  survives reaching the first/last page.
-->
<script lang="ts">
	let {
		page,
		pageCount,
		pageSize,
		pageSizeOptions = [10, 25, 50, 100],
		total,
		start,
		end,
		onPage,
		onPageSize
	}: {
		page: number;
		pageCount: number;
		pageSize: number;
		pageSizeOptions?: number[];
		total: number;
		start: number;
		end: number;
		onPage: (page: number) => void;
		onPageSize: (size: number) => void;
	} = $props();

	function handleSizeChange(event: Event) {
		onPageSize(Number((event.currentTarget as HTMLSelectElement).value));
	}
</script>

<div class="pagination">
	<label class="size">
		Show
		<select value={pageSize} onchange={handleSizeChange} aria-label="Rows per page">
			{#each pageSizeOptions as option (option)}
				<option value={option}>{option}</option>
			{/each}
		</select>
		entries
	</label>

	<p class="readout" aria-live="polite">Showing {start}–{end} of {total} entries</p>

	<div class="controls">
		<button
			type="button"
			aria-label="Previous page"
			aria-disabled={page <= 1}
			onclick={() => page > 1 && onPage(page - 1)}
		>
			‹ Prev
		</button>
		<span class="where">Page {page} of {pageCount}</span>
		<button
			type="button"
			aria-label="Next page"
			aria-disabled={page >= pageCount}
			onclick={() => page < pageCount && onPage(page + 1)}
		>
			Next ›
		</button>
	</div>
</div>

<style>
	.pagination {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 1em;
		flex-wrap: wrap;
		margin-top: 0.5em;
		font-size: 1em;
	}
	.readout {
		margin: 0;
		opacity: 0.85;
	}
	.size {
		display: inline-flex;
		align-items: center;
		gap: 0.4em;
	}
	select,
	button {
		font: inherit;
		color: inherit;
		background: var(--dt-header-bg, rgba(128, 128, 128, 0.14));
		border: 1px solid var(--dt-border, rgba(128, 128, 128, 0.35));
		border-radius: 6px;
		padding: 0.25em 0.6em;
	}
	select option {
		color: initial;
	}
	button {
		cursor: pointer;
	}
	button:hover:not([aria-disabled='true']) {
		border-color: var(--dt-accent, #4a9eda);
	}
	button[aria-disabled='true'] {
		opacity: 0.45;
		cursor: default;
	}
	button:focus-visible,
	select:focus-visible {
		outline: 2px solid var(--dt-accent, #4a9eda);
		outline-offset: 1px;
	}
	.controls {
		display: inline-flex;
		align-items: center;
		gap: 0.6em;
	}
	.where {
		opacity: 0.85;
	}
</style>
