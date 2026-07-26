<!-- Fixture for the note-driven trigger: a <Note> whose lines can start named
     animations. The test flips presenter mode on (so the checklist action
     runs), checks a data-trigger line, and asserts the lastTrigger store
     pulses (and does NOT pulse on shift-cumulative or unchecking). -->
<script>
	import Note from '$lib/components/Note.svelte';
</script>

<Note>
	<li data-trigger="save-cursor">Now I click Save</li>
	<li>A line with no trigger</li>
	<li data-trigger="menu-cursor">And open the menu</li>
</Note>
