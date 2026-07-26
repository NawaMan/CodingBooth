<!--
  Test host for Tabs / Tab, used by the SSR test. Slotted children can't be handed
  to render() directly, and the whole point of the pair is that a Tab registers its
  label UP to the Tabs so the strip can draw it — so they have to be rendered
  together to prove the strip reflects the registered tabs at all.
-->
<script lang="ts">
	import Tabs from '$lib/components/Tabs.svelte';
	import Tab from '$lib/components/Tab.svelte';
	import { setMode } from '$lib/presentation';
	import type { Mode } from '$lib/presentation';

	export let start = 0;
	export let align = 'start';
	export let transition: 'fade' | 'none' = 'fade';
	// A Text artifact publishes its mode from its +layout; a host stands in for that
	// so the text-mode branch (no strip, panels shown in flow) can be rendered.
	export let mode: Mode = 'presentation';

	setMode(mode);
</script>

<Tabs {start} {align} {transition}>
	<Tab label="JavaScript">const a = 1;</Tab>
	<Tab label="Python" icon="🐍">a = 1</Tab>
	<Tab label="Go" disabled>a := 1</Tab>
</Tabs>
