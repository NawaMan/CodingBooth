<!-- Fixture for the below-slide-note visibility gate. A plain <Note> carrying a
     marker; the test flips the displayMode / presenterMode / consoleLive stores and
     asserts whether the note is in the DOM. -->
<script>
	import Note from '$lib/components/Note.svelte';
</script>

<Note><p>SPEAKER_NOTE_MARKER</p></Note>
