<!--
  Comments.svelte — a free, GitHub-Discussions-backed comment thread (giscus).
  Drop it at the end of an article; it renders one thread per page (keyed by the
  page's pathname, so each post gets its own).

  No backend, no cost — but it needs a ONE-TIME setup (a maintainer does this once;
  the repo-id / category-id can't be guessed, they're GitHub node IDs):

    1. The repo must be PUBLIC and have Discussions enabled
       (GitHub → Settings → General → Features → ✓ Discussions).
    2. Install the giscus GitHub App and grant it this repo:
       https://github.com/apps/giscus
    3. Create a Discussions category for comments — recommended type
       "Announcement" so visitors can't open raw threads; giscus creates them.
    4. Go to https://giscus.app, enter the repo + category, and copy the
       `data-repo-id` and `data-category-id` it shows into REPO_ID / CATEGORY_ID
       below.

  Until REPO_ID / CATEGORY_ID are filled in, this shows a short setup note instead
  of loading giscus (so the build never ships a broken widget).
-->
<script lang="ts">
	import { onMount } from 'svelte';

	// ---- giscus config (single source of truth for the whole blog) ----
	const REPO        = 'NawaMan/CodingBooth';
	const REPO_ID     = 'R_kgDOPk8u5Q';              // GitHub node id of the repo
	const CATEGORY    = 'Announcements';             // Announcement-type category (maintainer-gated)
	const CATEGORY_ID = 'DIC_kwDOPk8u5c4DACvl';      // node id of the Announcements category
	const THEME       = 'dark_dimmed';               // matches the dark blog theme

	const configured = !REPO_ID.startsWith('REPLACE') && !CATEGORY_ID.startsWith('REPLACE');
	let container: HTMLDivElement;

	// giscus is a client-only widget: load it in onMount so prerender stays static.
	onMount(() => {
		if (!configured) return;
		const s = document.createElement('script');
		s.src = 'https://giscus.app/client.js';
		s.async = true;
		s.crossOrigin = 'anonymous';
		const attrs: Record<string, string> = {
			'data-repo': REPO,
			'data-repo-id': REPO_ID,
			'data-category': CATEGORY,
			'data-category-id': CATEGORY_ID,
			'data-mapping': 'pathname', // one thread per post URL (/blog/<date>.html)
			'data-strict': '1',
			'data-reactions-enabled': '1',
			'data-emit-metadata': '0',
			'data-input-position': 'top',
			'data-theme': THEME,
			'data-lang': 'en',
			'data-loading': 'lazy'
		};
		for (const [k, v] of Object.entries(attrs)) s.setAttribute(k, v);
		container.appendChild(s);
	});
</script>

<section class="comments">
	<h2>Comments</h2>
	{#if !configured}
		<p class="setup-note">
			Comments aren't configured yet — set <code>REPO_ID</code> and <code>CATEGORY_ID</code> in
			<code>src/lib/components/Comments.svelte</code> from
			<a href="https://giscus.app" target="_blank" rel="noopener">giscus.app</a>
			(see the setup notes at the top of that file).
		</p>
	{/if}
	<div bind:this={container}></div>
</section>

<style>
	.comments {
		margin-top: 2.5em;
		padding-top: 1.2em;
		border-top: 1px solid #2a3a40;
	}
	.comments h2 {
		color: #7fd9ff;
		margin-bottom: 0.6em;
	}
	.setup-note {
		opacity: 0.7;
		font-style: italic;
	}
	.setup-note a { color: #7fd9ff; }
	.setup-note code { font-family: 'Fira Code', monospace; font-size: 0.9em; }
</style>
