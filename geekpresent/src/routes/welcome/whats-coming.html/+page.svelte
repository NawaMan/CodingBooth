<script>
	import ContentPage from '$lib/templates/ContentPage.svelte';
	import Hint        from '$lib/components/Hint.svelte';
	import ViewSource  from '$lib/components/ViewSource.svelte';
	import source      from './+page.svelte?raw';
</script>

<ContentPage title="What's coming" subtitle="Bits and pieces, one post at a time">
	<ul>
		<li><b>Reproducible by design</b> — how a project's whole environment travels with it in a <code>.booth/</code> folder.</li>
		<li><b>Variants</b> — a browser terminal, VS Code, Jupyter, or a full Linux desktop, all over the same environment.</li>
		<li><b>Isolation</b> — egress allow-listing and kernel-level sandboxing for running untrusted or AI-driven code.</li>
		<li><b>Templates &amp; recipes</b> — scaffolding a whole stack from one selection string.</li>
		<li><b>Under the hood</b> — the wrapper, the binary, and how your host identity maps inside the booth.</li>
	</ul>
	<Hint text="Have something you want covered? Open an issue on GitHub." />
</ContentPage>

<ViewSource {source} path="src/routes/welcome/whats-coming.html/+page.svelte" />
