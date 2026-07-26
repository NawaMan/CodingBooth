<!--
  SSR fixture: the state-demo slide's two live widgets, wired exactly as the slide
  wires them — a `persisted` counter and a `?name=`-driven greeting.

  Prerendered output must show the DEFAULTS (0 and "world"), because at build time
  there is no browser to remember anything and no request URL to read. The remembered
  value is a client concern that arrives on hydration.
-->
<script lang="ts">
	import { browser } from '$app/environment';
	import { page } from '$app/stores';
	import { persisted } from '../src/lib/stores/persisted';
	import { numberCodec, readTextParam } from '../src/lib/utils/stateCore';

	const count = persisted<number>('geekpresent:demo:count', 0, {
		codec: numberCodec({ min: 0, max: 99 })
	});

	$: name = browser ? readTextParam($page.url.searchParams, 'name', '') : '';
	$: greeting = name || 'world';
</script>

<div>
	<p>SSR_STATE_MARKER</p>
	<span data-testid="count">{$count}</span>
	<span data-testid="greeting">{greeting}</span>
</div>
