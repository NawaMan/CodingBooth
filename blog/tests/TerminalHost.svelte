<!-- Terminal fixture: a session rendered under a chosen artifact mode. `setMode` is
     context, so only a PARENT can publish it — which is exactly how a Text's
     +layout.svelte reaches the components inside it. -->
<script lang="ts">
	import { setMode, type Mode } from '../src/lib/presentation';
	import Terminal from '../src/lib/components/Terminal.svelte';
	import type { TerminalInput } from '../src/lib/utils/terminalCore';

	export let mode: Mode = 'presentation';
	export let lines: TerminalInput[] = [];
	export let typing = true;
	export let caret = true;
	export let controls = true;
	export let autoplay = false;
	export let keys: 'global' | 'off' = 'off';

	setMode(mode);
</script>

<Terminal
	{lines}
	{typing}
	{caret}
	{controls}
	{autoplay}
	{keys}
	charMs={10}
	startMs={100}
	pauseMs={50}
	outMs={20}
/>
