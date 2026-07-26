<!-- Fixture for the note-driven highlight trigger: a <Note> whose lines name the
     Blocks they talk about. The test flips presenter mode on (so the checklist
     action runs), hovers a `data-highlight` line, and asserts the highlightTarget
     store lights up. -->
<script>
	import Note from '$lib/components/Note.svelte';
</script>

<Note>
	<li data-highlight="db">Now the query hits the database</li>
	<li>A line with no highlight target</li>
	<li data-highlight="cache">The cache warms</li>
</Note>
