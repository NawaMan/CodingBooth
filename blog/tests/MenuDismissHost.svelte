<!-- SlideToolbar fixture for the ☰ DISMISS rule. SlideToolbarHost supplies a single bare
     row; this one mirrors production more closely, because the rule is about how rows
     differ: an ordinary row lets the click bubble to the panel (which closes the latch AND
     dismisses), while PRINT stops propagation so its flyout can live inside the drop. -->
<script lang="ts">
	import SlideToolbar from '../src/lib/components/SlideToolbar.svelte';
</script>

<SlideToolbar width={1920} height={1080}>
	{#snippet overviewBtn()}
		<button type="button" class="annot-tool" data-row="ordinary">OVERVIEW</button>
	{/snippet}
	{#snippet printBtn()}
		<!-- The real PRINT row's shape: it opens a submenu in here, so it must NOT dismiss. -->
		<button type="button" class="annot-tool" data-row="print" on:click|stopPropagation={() => {}}>
			PRINT
		</button>
	{/snippet}
	{#snippet sourceItem()}
		<!-- The row that surfaced the bug: it opens a panel UNDER the drop. -->
		<button type="button" class="annot-tool" data-row="source" on:click={() => {}}>SOURCE</button>
	{/snippet}
</SlideToolbar>
