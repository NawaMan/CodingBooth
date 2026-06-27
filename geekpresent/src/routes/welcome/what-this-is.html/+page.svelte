<script>
	import ContentPage from '$lib/templates/ContentPage.svelte';
	import ViewSource  from '$lib/components/ViewSource.svelte';
	import source      from './+page.svelte?raw';
</script>

<ContentPage title="Welcome 👋" subtitle="What this blog is">
	<p>
		This is the home for short, focused write-ups about <b>CodingBooth</b> — the tool that
		delivers fully reproducible, isolated development environments in a Docker container that
		runs as <i>you</i>, with your files staying yours on the host.
	</p>
	<p>
		Rather than one giant manual, the blog takes it one piece at a time: a single feature, a
		design decision, or a workflow per post — each authored as a slide deck you can click
		through, or a long-form page you can read at your own pace.
	</p>
	<p>
		New posts land here over time. This first one is just the welcome mat.
	</p>
</ContentPage>

<ViewSource {source} path="src/routes/welcome/what-this-is.html/+page.svelte" />
