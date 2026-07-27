<!--
  Debounced global-search input for DataTable. Emits onSearch(text) ~250ms
  after the last keystroke; the actual filtering (case-insensitive substring
  across visible columns) lives in tableCore.filterRows.
-->
<script lang="ts">
	let {
		value = '',
		label = 'Search',
		placeholder = 'Type to filter…',
		delay = 250,
		onSearch
	}: {
		value?: string;
		label?: string;
		placeholder?: string;
		delay?: number;
		onSearch: (text: string) => void;
	} = $props();

	// svelte-ignore state_referenced_locally
	let text = $state(value);
	let timer: ReturnType<typeof setTimeout> | undefined;

	// Follow external resets (e.g. a parent clearing table.search in Phase 2's
	// controlled mode). While a debounce is pending `value` hasn't changed, so
	// this never fights the user's typing.
	$effect(() => {
		text = value;
	});

	// Cancel a pending emit on unmount.
	$effect(() => () => clearTimeout(timer));

	function handleInput(event: Event) {
		text = (event.currentTarget as HTMLInputElement).value;
		clearTimeout(timer);
		timer = setTimeout(() => onSearch(text), delay);
	}
</script>

<label class="searchbox">
	<span class="searchbox-label">{label}</span>
	<input type="search" {placeholder} value={text} oninput={handleInput} />
</label>

<style>
	.searchbox {
		display: inline-flex;
		align-items: center;
		gap: 0.5em;
		font-size: 1em;
	}
	input {
		font: inherit;
		color: inherit;
		background: var(--dt-header-bg, rgba(128, 128, 128, 0.14));
		border: 1px solid var(--dt-border, rgba(128, 128, 128, 0.35));
		border-radius: 6px;
		padding: 0.3em 0.6em;
		min-width: 14em;
	}
	input:focus-visible {
		outline: 2px solid var(--dt-accent, #4a9eda);
		outline-offset: 1px;
	}
</style>
