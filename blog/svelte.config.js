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
			fallback: "article.html",
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
