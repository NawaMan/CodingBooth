<!--
  TextPage — the reusable shell for a Text artifact.

  A Text is the second kind of GeekPresent artifact: ONE long page whose height
  grows with the content that flows down it, authored by hand and reusing the
  same $lib components as the slides (it is NOT generated from a presentation).

  This component is the whole shell — global styles, text mode, the scroll
  container + flowing column, and the nav bar (which in text mode becomes a
  single TOP control). To make a Text artifact, give a route a tiny layout that
  wraps its <slot/> in <TextPage>. The authored markup uses bare browser
  defaults for typography; a Text artifact can style its own tags in +page.svelte.
-->
<script lang="ts">
	import '$lib/styles/global.css';
	import '$lib/styles/tooltip.css';

	import { setMode }   from '$lib/presentation';
	import { SITE_TITLE } from '$lib/utils/navigate';
	import { SITE_DESCRIPTION } from '$lib/seo/config';
	import NavigationBar from '$lib/components/NavigationBar.svelte';
	import Seo           from '$lib/components/Seo.svelte';

	// Publish this artifact's mode so reused components can adapt (e.g. the slide
	// nav bar becomes a single TOP control that scrolls this container up).
	setMode('text');

	// Browser-tab <title> for this Text artifact. A Text is one page, so there is no
	// page-vs-presentation cascade — just this one title, defaulting to the site
	// name (the same default a deck falls back to). A route can override it via
	// <TextPage title="...">.
	export let title: string = SITE_TITLE;
	/** SEO description for this Text; defaults to the site description. */
	export let description: string = SITE_DESCRIPTION;
	/** Social/OG image (absolute URL or site-relative path); undefined uses the
	    site-default OG image. */
	export let image: string | undefined = undefined;
	/** Alt text for the social image; undefined uses the default card alt. */
	export let imageAlt: string | undefined = undefined;
	/** OpenGraph type — 'website' for the landing page, 'article' for a long-form Text. */
	export let type: 'website' | 'article' = 'website';
</script>

<!-- Seo emits the <title> + full SEO/social metadata for this Text. -->
<Seo {title} {description} {image} {imageAlt} {type} />

<div class="text-scroll" data-text-scroll>
	<div class="text-page">
		<slot />
	</div>
</div>

<NavigationBar />

<style>
	.text-scroll {
		width: 100vw;
		height: 100vh;
		overflow: auto;
		background: var(--surface-bg, #181818);
	}

	.text-page {
		/* Base font-size lever for the authored text: nudges all the em-based
		   typography at once. 1em = the 16px browser default — tune to taste. */
		font-size: 1em;
		/* Fluid width: the column follows the viewport (equal left/right padding
		   keeps matching space on both sides), but caps at 1080px so lines don't
		   run too long on a wide monitor — past that it centers via margin auto. */
		width: 100%;
		max-width: 1080px;
		min-height: 100%;
		margin: 0 auto;
		padding: 36px 60px 96px;
		box-sizing: border-box;
		color: var(--surface-fg, #C0F1FF);
		background: var(--surface-bg, #181818);
		font-family: 'Noto Sans', 'Cormorant Garamond', serif;
	}
</style>
