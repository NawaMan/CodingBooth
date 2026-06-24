<!--
  Example: CodeBox component
  File: src/routes/slides/codebox-component.html/+page.svelte
-->
<script>
	import ContentPage from '$lib/templates/ContentPage.svelte';
	import CodeBox     from '$lib/components/CodeBox.svelte';
	import CtrlBtn     from '$lib/components/CtrlBtn.svelte';
	import QuickCode   from '$lib/components/QuickCode.svelte';

	let show = false;

	const code = `function sumTo(n) {
  let sum = 0;
  for (let i = 1; i <= n; i++) sum += i;
  return sum;
}

console.log(sumTo(100)); // 5050`;
</script>

<ContentPage title="CodeBox" subtitle="Code inside an expandable Box (any language)">
	<p>Like JavaCodeBox, but for any language &mdash; pass <code>language</code> and an optional <code>title</code>:</p>
	<CtrlBtn text="Reveal code" on:click={() => (show = true)} />
	<QuickCode style="margin-top: 0.6em;">
		&lt;CodeBox code=&#123;code&#125; language="javascript" title="sum.js" expanded=&#123;show&#125; /&gt;
	</QuickCode>
	<p style="margin-top: 0.5em; opacity: 0.7;">
		Click CLOSE, click outside, or press Escape to dismiss. (Monaco loads from a CDN &mdash; needs internet.)
	</p>
</ContentPage>

<CodeBox code={code} language="javascript" title="sum.js" bind:expanded={show} revealedLines={[1]} />
