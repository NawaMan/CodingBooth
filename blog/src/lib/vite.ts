// The Vite plugin a GeekPresent site adds to its vite.config.ts — BEFORE sveltekit():
//
//     import site from './geekpresent.config';
//     plugins: [geekpresent(site), sveltekit()]
//
// It bundles four things:
//   - the project's settings, resolved once and injected as `__GEEKPRESENT_CONFIG__`
//     (config/siteConfigCore.ts; GEEKPRESENT_SITE_URL still overrides `siteUrl`);
//   - sourceStampPlugin, which must run before the Svelte compiler (both are
//     `enforce: 'pre'`, and within one tier order wins), hence "before sveltekit()";
//   - adjustSavePlugin, the dev-only write endpoints (ADJUST/EDIT SAVE, deck editing,
//     note editing). Its middleware is added straight away, ahead of SvelteKit's own
//     handler, which SvelteKit installs last;
//   - sourceFilesPlugin, the dev-only file endpoints behind the EDIT window's tree and
//     tabs (source/devFilePlugin.ts).
//
// In a project this file is loaded from the package's compiled `vite.js` (Node cannot run
// TypeScript out of node_modules), so it must import nothing that needs Vite to resolve —
// no `$lib`, no `.svelte`.
import type { Plugin } from 'vite';
import { adjustSavePlugin, sourceStampPlugin } from './adjust/devSavePlugin';
import { sourceFilesPlugin } from './source/devFilePlugin';
import { resolveConfig, type GeekPresentConfig, type SiteConfig } from './config/siteConfigCore';

export type { GeekPresentConfig, SiteConfig };
export { adjustSavePlugin, sourceStampPlugin, sourceFilesPlugin };

/** Loaded from inside node_modules ⇒ a project using the package, whose slides reach the
    framework as '@geekpresent/core'; anywhere else ⇒ this repo, where it is '$lib'. */
function defaultLibImport(): string {
	return import.meta.url.includes('/node_modules/') ? '@geekpresent/core' : '$lib';
}

/** The define a test config needs to load anything that reads SITE (config/site.ts). */
export function configDefine(user: GeekPresentConfig = {}, envSiteUrl?: string): Record<string, string> {
	return {
		__GEEKPRESENT_CONFIG__: JSON.stringify(resolveConfig(user, envSiteUrl, defaultLibImport()))
	};
}

/** Settings only — for a vitest config, which has no use for the dev endpoints. */
export function geekpresentConfig(user: GeekPresentConfig = {}): Plugin {
	return {
		name: 'geekpresent:config',
		config() {
			return { define: configDefine(user, process.env.GEEKPRESENT_SITE_URL) };
		}
	};
}

/** Everything a GeekPresent site needs from Vite. Place before sveltekit(). */
export function geekpresent(user: GeekPresentConfig = {}): Plugin[] {
	return [sourceStampPlugin(), geekpresentConfig(user), adjustSavePlugin(), sourceFilesPlugin()];
}
