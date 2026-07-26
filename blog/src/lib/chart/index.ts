// Public exports for the chart module.
//
// Charts consume plain T[] arrays + accessors and never import from
// $lib/datatable — the only contract is "plain arrays + accessors + pure
// pipeline", so a chart can sit downstream of a table's bind:state with no
// coupling. All geometry/data math lives in the pure chartCore.ts; components
// (BarChart, LineChart, Axis) land alongside these exports as they arrive.
export { default as AreaChart } from './AreaChart.svelte';
export { default as Axis } from './Axis.svelte';
export { default as BarChart } from './BarChart.svelte';
export { default as ChartLegend } from './ChartLegend.svelte';
export { default as ChartTooltip } from './ChartTooltip.svelte';
export { default as ComboChart } from './ComboChart.svelte';
export { default as Gantt } from './Gantt.svelte';
export { default as Heatmap } from './Heatmap.svelte';
export { default as Histogram } from './Histogram.svelte';
export { default as LineChart } from './LineChart.svelte';
export { default as PieChart } from './PieChart.svelte';
export { default as ScatterChart } from './ScatterChart.svelte';
export { default as Waterfall } from './Waterfall.svelte';
export * from './chartCore';
export type * from './types';
