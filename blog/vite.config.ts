import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';
import { geekpresent } from './src/lib/vite';
import site from './geekpresent.config';

// The blog's settings live in geekpresent.config.ts. GEEKPRESENT_SITE_URL, when set,
// still overrides its siteUrl per build ('' omits every absolute-only SEO tag).

export default defineConfig({
	plugins: [
		// Settings, the source stamp and the dev-only SAVE endpoints. FIRST, ahead of
		// sveltekit(): the stamp must see markup before the Svelte compiler does (both
		// are `enforce: 'pre'`, and within one tier order wins). See src/lib/vite.ts.
		geekpresent(site),
		sveltekit()
	],
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
