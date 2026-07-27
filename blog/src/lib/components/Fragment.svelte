<!--
  Fragment — one build step inside <Steps>.

  A Fragment starts hidden and fades in when the presenter steps past it. It keeps
  its layout space while hidden (visibility, not display), so the slide never
  reflows as pieces appear. Nest Fragments in a <Steps> in document order; the
  Steps container hands each one a stable index and drives the reveal.

    <Steps>
      <Fragment tag="li">First point</Fragment>
      <Fragment tag="li" transition="fly">Second point</Fragment>
    </Steps>

  Props:
    tag        — element to render (default 'div'; use 'li', 'p', 'span', … to keep
                 the surrounding markup semantic).
    transition — 'fade' | 'fly' | 'slide' | 'scale' | 'none'. Omit to inherit the
                 Steps default.
    duration   — reveal length in seconds. Omit to inherit the Steps default.
    style      — extra inline CSS.

  Used outside a <Steps> a Fragment simply renders visible — so content degrades
  gracefully (and prerenders) when there's no build to drive it.
-->
<script lang="ts">
	import { getContext } from 'svelte';
	import { writable, type Readable } from 'svelte/store';

	type Ctx = {
		register: () => number;
		revealed: Readable<number>;
		defaults: Readable<{ transition: string; duration: number }>;
	};

	/** Element to render. Match the surrounding markup (li/p/span/…). */
	export let tag: string = 'div';
	/** Reveal transition; `null` → inherit the Steps default. */
	export let transition: 'fade' | 'fly' | 'slide' | 'scale' | 'none' | null = null;
	/** Reveal length in seconds; `null` → inherit the Steps default. */
	export let duration: number | null = null;
	/** Extra inline CSS. */
	export let style: string = '';
	/** DOM id for the root element. */
	export let id: string = '';
	/** Extra class(es) for the root element. NOTE: a slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS (global.css / roles.css / a
	    :global(...) block) or a utility class. See AGENTS.md. */
	let klass: string = '';
	export { klass as class };

	// May be used standalone (no Steps): fall back to a permanently-shown stub so
	// the content still renders and prerenders.
	const ctx = getContext<Ctx>('steps');

	const index = ctx ? ctx.register() : 0;
	const revealed = ctx ? ctx.revealed : writable(Infinity);
	const defaults = ctx ? ctx.defaults : writable({ transition: 'fade', duration: 0.35 });

	$: mode = transition ?? ($defaults?.transition ?? 'fade');
	$: dur = duration ?? ($defaults?.duration ?? 0.35);
	$: shown = $revealed > index;
</script>

<svelte:element
	this={tag}
	class="fragment mode-{mode} {klass}"
	class:hidden={!shown}
	id={id || undefined}
	style="--frag-dur: {dur}s; {style}"
	aria-hidden={shown ? undefined : 'true'}
>
	<slot />
</svelte:element>

<style>
	.fragment {
		transition:
			opacity var(--frag-dur, 0.35s) ease,
			transform var(--frag-dur, 0.35s) ease,
			visibility 0s;
	}
	/* Hidden: invisible AND out of the a11y/pointer tree, but still occupying its
	   box so the slide doesn't reflow. Delay the visibility flip until the fade-out
	   finishes so it animates out; on the way in it's immediate (base rule, 0s). */
	.fragment.hidden {
		opacity: 0;
		visibility: hidden;
		transition-delay: 0s, 0s, var(--frag-dur, 0.35s);
	}

	/* Per-mode entrance offset (only applied while hidden). */
	.fragment.mode-fly.hidden {
		transform: translateY(14px);
	}
	.fragment.mode-slide.hidden {
		transform: translateX(-24px);
	}
	.fragment.mode-scale.hidden {
		transform: scale(0.96);
	}
	.fragment.mode-none {
		transition: none;
	}

	@media (prefers-reduced-motion: reduce) {
		.fragment {
			transition-property: opacity, visibility;
			transform: none !important;
		}
	}
</style>
