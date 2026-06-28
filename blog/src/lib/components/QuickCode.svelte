<!--
  QuickCode — the small inline "code snippet" box used across slides.

  A lightweight, dark monospace block for short hand-written snippets (escaped
  HTML with <br/> and &nbsp; for layout). For real, syntax-highlighted code use
  Code / CodeBox (Monaco) instead.

  Usage:

    <script>
      import QuickCode from '$lib/components/QuickCode.svelte';
    </script>

    <QuickCode>
      &lt;Note&gt;<br/>
      &nbsp;&nbsp;&lt;p&gt;Remember to explain X.&lt;/p&gt;<br/>
      &lt;/Note&gt;
    </QuickCode>

  The `style` prop appends extra CSS to the box (e.g. `style="margin-top: 0.5em;"`).
-->
<script lang="ts">
	/** Extra inline CSS appended to the box (e.g. spacing tweaks per slide). */
	export let style: string = '';
</script>

<div class="quick-code" {style}><slot /></div>

<style>
	.quick-code {
		font-family: 'Fira Code', monospace;
		font-size: 0.85em;
		background: var(--quickcode-bg, #111111);
		color: var(--quickcode-fg, inherit);
		padding: 0.5em 1em;
		border-radius: 5px;
		line-height: 1.8em;
	}
</style>
