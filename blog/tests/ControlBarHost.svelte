<!-- ControlBar fixture. SlideDeck normally supplies the TOC and the deck pager as snippets;
     the tests only need to see that the shell lays them out, so the host passes trivial
     stand-ins. -->
<script lang="ts">
	import ControlBar from '../src/lib/components/ControlBar.svelte';
</script>

<ControlBar>
	{#snippet tocItem()}
		<div class="toc gp-chrome">TOC</div>
	{/snippet}
	{#snippet navGroup()}
		<div class="nav gp-chrome">NAV</div>
	{/snippet}
</ControlBar>
