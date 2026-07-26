<!--
  Test host for Timeline / TimelineItem, used by the SSR test. Slotted children
  can't be handed to render() directly, and the whole point of TimelineItem is the
  layout side it learns from its parent Timeline over context — so the pair has to
  be rendered together to test that the side reaches the items at all.
-->
<script lang="ts">
	import Timeline from '$lib/components/Timeline.svelte';
	import TimelineItem from '$lib/components/TimelineItem.svelte';

	export let orientation: 'vertical' | 'horizontal' = 'vertical';
	export let side: 'right' | 'left' | 'above' | 'below' | 'alternate' = 'right';
	export let gap: string = '1.6em';
</script>

<Timeline {orientation} {side} {gap}>
	<TimelineItem time="2019" title="Founded" text="Two people, one garage." />
	<TimelineItem time="2021" title="Series A" icon="★" color="#f0a33e">
		Ten million users.
	</TimelineItem>
	<TimelineItem time="Today" title="Here" active />
</Timeline>
