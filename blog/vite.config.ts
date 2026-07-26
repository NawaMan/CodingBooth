import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';
import { adjustSavePlugin } from './src/lib/adjust/devSavePlugin';

// Absolute site base URL for SEO/social metadata (og:url, og:image, canonical,
// sitemap). Consistent with the other GEEKPRESENT_* build vars in svelte.config.js.
//   - UNSET            -> the project's GitHub Pages URL (the default deploy target).
//   - set but EMPTY (`GEEKPRESENT_SITE_URL=`) -> no base URL, so the SEO layer OMITS
//     every absolute-only tag instead of emitting a broken/relative one.
//   - set to a URL     -> use it verbatim (e.g. a custom domain).
// In-page ASSET paths stay relative regardless — only metadata URLs use this.
const DEFAULT_SITE_URL = 'https://nawaman.github.io/GeekPresent';
const rawSiteUrl = process.env.GEEKPRESENT_SITE_URL;
const SITE_URL = (rawSiteUrl === undefined ? DEFAULT_SITE_URL : rawSiteUrl)
	.trim()
	.replace(/\/+$/, ''); // trim a trailing slash for clean joins

export default defineConfig({
	plugins: [
		sveltekit(),
		// Dev-only: ADJUST SAVE (Block patches) and ViewSource SAVE (full +page.svelte).
		adjustSavePlugin()
	],
	// Inject the base URL as a string literal into BOTH the SSR/prerender output and
	// the client bundle, so prerendered pages carry absolute metadata with no
	// runtime process.env. Read via $lib/seo/config.ts.
	define: {
		__GEEKPRESENT_SITE_URL__: JSON.stringify(SITE_URL)
	},
	server: {
		host: '0.0.0.0',
		// Don't recurse the file-watcher into pnpm's content-addressed store or the
		// nested agent worktrees (worktree/<name>/, each with its OWN .pnpm-store).
		// The booth bind-mounts the whole project into the container, so without this
		// Vite tries to watch hundreds of thousands of store files and dies with
		// `ENOSPC: System limit for number of file watchers reached`.
		watch: {
			ignored: ['**/.pnpm-store/**', '**/worktree/**']
		}
	},
	optimizeDeps: {
        exclude: ["codemirror", "@codemirror/language-javascript"],
    },
});
