<!--
  Example: JavaCode component
  File: src/routes/slides/javacode-component.html/+page.svelte
-->
<script>
	import ContentPage from '$lib/templates/ContentPage.svelte';
	import JavaCode    from '$lib/components/JavaCode.svelte';

	const code = `import java.util.List;

public class Greeter {
    public static void main(String[] args) {
        List.of("world", "GeekPresent").forEach(Greeter::greet);
    }

    static void greet(String name) {
        System.out.println("Hello, " + name + "!");
    }
}`;
</script>

<ContentPage title="JavaCode" subtitle="Read-only Monaco editor specialised for Java">
	<p>Displays Java with syntax highlighting, code folding and a minimap (read-only):</p>
	<JavaCode javaCode={code} width="100%" height="10em" />
	<p style="margin-top: 0.5em; opacity: 0.8;">
		Unlike the generic <b>Code</b>, JavaCode adds a <b>custom Java folding provider</b>
		(folding <code>import</code> groups and brace blocks).
	</p>
	<p style="margin-top: 0.3em; opacity: 0.7;">
		Props: <code>javaCode</code>, <code>width</code>, <code>height</code>,
		<code>foldAllAtStart</code>, <code>revealLines</code>, <code>cursorLine</code>.
		Loads Monaco from a CDN &mdash; needs an internet connection.
	</p>
</ContentPage>
