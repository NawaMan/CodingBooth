<!--
  HandoutFrame — publish a per-instance handout context, then render the slot.

  The notes grid needs each slide rendered TWICE in one row: once as a small thumbnail with the
  note OFF (just the picture), and once at full size with only the note showing. Those two want
  OPPOSITE answers to "are notes on?", and the answer is a context (getHandout), which is
  per-subtree — so each render is wrapped in its own frame that sets its own answer.

  It is the honest fix for a real constraint: the <Note> is authored INSIDE the slide, as a
  sibling of the slide's visual, both inside the scaled canvas. There is no CSS that pulls the
  note out of that scale to full size — so the note is rendered a second time, in its own frame,
  where nothing scales it.
-->
<script lang="ts">
	import { setHandout } from '$lib/presentation';

	/** Whether <Note>s render in this subtree. */
	export let notes: boolean = false;

	setHandout({ notes });
</script>

<slot />
