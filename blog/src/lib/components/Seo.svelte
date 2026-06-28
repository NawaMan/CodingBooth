<!--
  Seo — renders SEO + social (OpenGraph / Twitter) metadata into <svelte:head>.

  Because every route is prerendered, these tags must be present in the STATIC
  HTML. <svelte:head> is server-rendered, and this component sets everything at
  module/render time (no onMount gating), so the tags land in the prerendered
  output and work for scrapers with JS disabled.

  The split that matters: the document <title>, description, og/twitter title and
  description are plain strings and always emitted. The ABSOLUTE-ONLY tags —
  og:url, og:image, twitter:image, <link rel="canonical"> — are derived from the
  build-time base URL (SITE_URL); when that is empty they are OMITTED rather than
  emitted broken/relative. In-page assets are unaffected and stay relative.
-->
<script lang="ts">
	import { page } from '$app/stores';
	import {
		SITE_NAME,
		OG_IMAGE_ALT,
		OG_IMAGE_WIDTH,
		OG_IMAGE_HEIGHT,
		absoluteUrl,
		resolveImage
	} from '$lib/seo/config';

	/** Full document <title> (already composed, e.g. "Slide — Deck"). */
	export let title: string;
	/** Meta/OG/Twitter description. Omitted from output when empty. */
	export let description = '';
	/** OG/Twitter image: an absolute URL, a site-relative path, or undefined to use
	    the site default. Resolved to absolute; omitted entirely when no base URL. */
	export let image: string | undefined = undefined;
	/** Alt text for the social image. Defaults to a description of the default card,
	    or the page title when a custom image is supplied. */
	export let imageAlt: string | undefined = undefined;
	/** OpenGraph type. */
	export let type: 'website' | 'article' = 'website';
	/** Canonical URL override; defaults to base URL + the current route. */
	export let canonical: string | undefined = undefined;
	/** Emit <meta name="robots" content="noindex"> when true. */
	export let noindex = false;

	// Absolute-only values, each undefined when no base URL is configured (so the
	// matching tag is omitted). The route comes from $page so canonical/og:url are
	// correct per prerendered page; trailingSlash is "never", so no trailing slash.
	$: url = canonical ?? absoluteUrl($page.url.pathname);
	$: ogImage = resolveImage(image);
	// Dimensions are only known for the bundled default card; a custom image has an
	// unknown size, so skip width/height for it rather than assert a wrong one.
	$: usingDefaultImage = !image;
	$: ogImageAlt = imageAlt ?? (image ? title : OG_IMAGE_ALT);
</script>

<svelte:head>
	<title>{title}</title>
	{#if description}<meta name="description" content={description} />{/if}
	{#if noindex}<meta name="robots" content="noindex" />{/if}

	<meta property="og:title" content={title} />
	{#if description}<meta property="og:description" content={description} />{/if}
	<meta property="og:type" content={type} />
	<meta property="og:site_name" content={SITE_NAME} />
	{#if url}<meta property="og:url" content={url} />{/if}
	{#if ogImage}
		<meta property="og:image" content={ogImage} />
		<meta property="og:image:alt" content={ogImageAlt} />
		{#if usingDefaultImage}
			<meta property="og:image:width" content={`${OG_IMAGE_WIDTH}`} />
			<meta property="og:image:height" content={`${OG_IMAGE_HEIGHT}`} />
		{/if}
	{/if}

	<meta name="twitter:card" content="summary_large_image" />
	<meta name="twitter:title" content={title} />
	{#if description}<meta name="twitter:description" content={description} />{/if}
	{#if ogImage}
		<meta name="twitter:image" content={ogImage} />
		<meta name="twitter:image:alt" content={ogImageAlt} />
	{/if}

	{#if url}<link rel="canonical" href={url} />{/if}
</svelte:head>
