<!-- Host for the ScatterChart tooltip test: a custom `tooltip` snippet that reads
     the THIRD argument (the hovered source row) to show a field the chart itself
     never sees — the point's name — proving the row is threaded through. -->
<script lang="ts">
	import ScatterChart from '../src/lib/chart/ScatterChart.svelte';

	type City = { city: string; rent: number; income: number };
	const data: City[] = [
		{ city: 'Alpha', rent: 1000, income: 50 },
		{ city: 'Beta', rent: 3000, income: 90 }
	];
</script>

<ScatterChart
	{data}
	x={{ value: 'rent', type: 'linear' }}
	series={{ key: 'income', label: 'Income', value: 'income' }}
	title="Tip"
>
	{#snippet tooltip(_x, points, row)}
		<span class="city">{row.city}</span>
		{#each points as p (p.key)}<span class="val">{p.formatted}</span>{/each}
	{/snippet}
</ScatterChart>
