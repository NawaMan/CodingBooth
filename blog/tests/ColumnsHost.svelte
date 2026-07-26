<!--
  Test host for Columns / Column, shared by the SSR and the DOM test. Slotted
  children can't be handed to render() directly, and the whole point of Column is
  what it learns from its parent over context — the track count it clamps a span
  against, and whether the group draws gutter rules. So the pair has to be rendered
  together to be tested at all.
-->
<script lang="ts">
	import Column from '$lib/components/Column.svelte';
	import Columns from '$lib/components/Columns.svelte';
	import type { Track } from '$lib/utils/columnsCore';

	export let columns: number = 2;
	export let widths: string | Track[] | null = null;
	export let divider = false;
	export let stack = false;
	export let align: string = 'stretch';
	export let gap: string = '';
	export let resizable = false;
	export let minTrack = 40;
	/** Span of the FIRST column; the second always spans one. */
	export let span: number = 1;
	export let columnAlign: string | null = null;
</script>

<Columns {columns} {widths} {divider} {stack} {align} {gap} {resizable} {minTrack}>
	<Column {span} align={columnAlign}>one</Column>
	<Column>two</Column>
</Columns>
