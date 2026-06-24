<!--
  Example: Speaker Notes
  File: src/routes/slides/speaker-notes.html/+page.svelte
-->
<script>
	import ContentPage from '$lib/templates/ContentPage.svelte';
	import Note from '$lib/components/Note.svelte';
	import QuickCode from '$lib/components/QuickCode.svelte';
</script>

<ContentPage title="Speaker Notes" subtitle="Notes visible below the slide in SCALED mode">
	<p>Switch to <b>SCALED</b> mode (top-right) and zoom out below the fit to see notes below the slide.</p>
	<QuickCode>
		&lt;Note&gt;<br/>
		&nbsp;&nbsp;&lt;p&gt;Remember to explain X.&lt;/p&gt;<br/>
		&nbsp;&nbsp;&lt;p&gt;Mention Y as a follow-up.&lt;/p&gt;<br/>
		&lt;/Note&gt;
	</QuickCode>
	<p>Notes are hidden in <b>FITTED</b> mode and when printing.</p>
</ContentPage>

<Note>
	<p>This is a speaker note! It appears below the slide in SCALED mode (zoomed out).</p>
	<p>Use notes to remind yourself of talking points during your presentation.</p>
	<p>Notes are not visible to the audience when presenting in FITTED mode.</p>
</Note>
