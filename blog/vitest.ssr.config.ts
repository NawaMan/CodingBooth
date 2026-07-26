import { svelte } from '@sveltejs/vite-plugin-svelte';
import { defineConfig } from 'vitest/config';

// SSR test project: node environment, NO svelteTesting() (that plugin
// prepends the `browser` resolve condition, which would pull in svelte's
// client runtime). Here components compile in server mode, so tests can
// render them via svelte/server and assert the prerendered markup —
// tests/*.ssr.test.ts. Run together with the dom project via
// vitest.workspace.ts.
export default defineConfig({
	plugins: [svelte()],
	// Same build-time global vite.config.ts injects (see $lib/seo/config.ts) — needed
	// by anything that renders <SlideDeck>, which pulls in <Seo>.
	define: {
		__GEEKPRESENT_SITE_URL__: JSON.stringify('https://example.test')
	},
	resolve: {
		alias: {
			$lib: new URL('./src/lib', import.meta.url).pathname,
			'$app/environment': new URL('./tests/stubs/app-environment.ts', import.meta.url).pathname,
			'$app/stores': new URL('./tests/stubs/app-stores.ts', import.meta.url).pathname,
			'$app/navigation': new URL('./tests/stubs/app-navigation.ts', import.meta.url).pathname,
			'$app/paths': new URL('./tests/stubs/app-paths.ts', import.meta.url).pathname
		}
	},
	test: {
		name: 'ssr',
		environment: 'node',
		include: ['tests/**/*.ssr.test.ts']
	}
});
