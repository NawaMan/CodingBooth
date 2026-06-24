<!--
  Example: Code component
  File: src/routes/slides/code-component.html/+page.svelte
-->
<script>
	import ContentPage from '$lib/templates/ContentPage.svelte';
	import Code        from '$lib/components/Code.svelte';

	const code = `from functools import reduce

def sum_to(n):
    return reduce(lambda a, b: a + b, range(1, n + 1))

if __name__ == "__main__":
    print(sum_to(100))  # 5050`;
</script>

<ContentPage title="Code" subtitle="Read-only Monaco editor for any language">
	<p>Same editor as JavaCode, but the <code>language</code> prop picks the grammar &mdash; here, Python:</p>
	<Code code={code} language="python" width="100%" height="7em" />
	<p style="margin-top: 0.5em; opacity: 0.7;">
		Props: <code>code</code>, <code>language</code> (default <code>"java"</code>),
		<code>width</code>, <code>height</code>, <code>foldAllAtStart</code>,
		<code>revealLines</code>, <code>cursorLine</code>.
		Uses Monaco's built-in, language-aware folding. Loads Monaco from a CDN &mdash; needs internet.
	</p>
</ContentPage>
