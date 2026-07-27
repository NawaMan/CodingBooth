import adapter from '@sveltejs/adapter-static';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

// Where the prerendered static site is written. Defaults to `docs/` (used by the
// GitHub Pages flow); `build-static.sh` overrides it to build into any folder.
const outDir = process.env.GEEKPRESENT_OUT || 'docs';

// Emit .br/.gz alongside each asset. Only useful when the host serves precompressed
// files (nginx gzip_static, Caddy, …). Default on (keeps the docs/ output as-is);
// `build-static.sh` sets GEEKPRESENT_PRECOMPRESS=0 to skip the dead copies.
const precompress = process.env.GEEKPRESENT_PRECOMPRESS !== '0';

export default {

	preprocess: vitePreprocess(),

	kit: {
		adapter: adapter({
			pages: outDir,
			assets: outDir,
			// SPA fallback: the empty app shell a host serves for a URL that has no
			// prerendered file. Named 404.html because that is the one name GitHub
			// Pages acts on — it serves this file, with a 404 status, for any unknown
			// path, so a mistyped slide URL boots the app and lands on SvelteKit's
			// styled error page instead of GitHub's default one.
			//
			// It used to be "article.html", which was inert on every host AND read like
			// a content page: it answered 200 with a blank, title-less document at a
			// URL that looked like a real article. A host that serves nothing on 404
			// simply never reaches this file — every route is prerendered, so nothing
			// depends on the fallback either way.
			fallback: "404.html",
			precompress
		}),
		prerender: {
			// There is no site-wide favicon in static/ (presentations set their own
			// via <svelte:head>). Don't fail the build over that one 404; still fail
			// on any other broken link.
			handleHttpError: ({ path, message }) => {
				if (path === '/favicon.png') return;
				throw new Error(message);
			}
		}
	}
};
