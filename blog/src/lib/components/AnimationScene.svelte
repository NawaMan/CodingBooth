<!--
  AnimationScene — a controllable "scene": a wrapper whose subtree is one timeline.

  A single CSS @keyframes is one object's motion. A SCENE is several objects moving
  on ONE shared playhead — Obj1 travelling its path while Obj2 travels its own, all
  scrubbed together. AnimationScene is the unit that expresses that: drop any number
  of animated elements inside it and the bundled AnimationBar governs every finite
  @keyframes animation in the subtree as one group (shared wall-clock; the envelope
  is the longest animation; give two objects the same `duration` to lock them step
  for step).

      <AnimationScene>
        <Box class="obj1" />   (@keyframes path-a: here  to there)
        <Box class="obj2" />   (@keyframes path-b: point to point)
      </AnimationScene>

  This rests on the native model rather than working around it: the wrapper is a real
  DOM element, and the bar collects with `getAnimations({ subtree: true })` — the
  built-in "every animation on this element and its descendants" query. The grouping
  IS DOM containment, so it needs no keyframe names and no per-element tagging, and it
  behaves identically on a 1920x1080 slide and inside a flowing Text artifact: the
  wrapper is the bar's positioned ancestor, so the bar anchors to the scene, not to
  the slide canvas. (Mode-agnostic — no `.content` assumption.)

  The bar is pointed here by selector (`scope=".anim-scene"`), resolved from the bar's
  own position (anchor.closest), so multiple scenes on one page each control only
  their own subtree. Nesting note: an outer scene's subtree query also sees an inner
  scene's animations; keep scenes siblings unless you intend the outer to drive both.
-->
<script lang="ts">
	import AnimationBar from './AnimationBar.svelte';

	/* Open paused on frame 0 (Play to start) instead of auto-playing. */
	export let startPaused = false;
	/* External source owns the playhead (e.g. scroll); see AnimationBar. */
	export let driven = false;
	/* Emphasise the collapsed ANIMATION button with the accent look. */
	export let highlight = false;
</script>

<div class="anim-scene">
	<slot />
	<AnimationBar scope=".anim-scene" {startPaused} {driven} {highlight} />
</div>

<style>
	.anim-scene {
		/* Be the bar's containing block so its absolute controls anchor to the scene
		   (works the same on a slide and in a flowing document). Otherwise the scene
		   is a plain block that sizes to its content — style it from the call site. */
		position: relative;
	}
</style>
