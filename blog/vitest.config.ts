import { svelte } from '@sveltejs/vite-plugin-svelte';
import { svelteTesting } from '@testing-library/svelte/vite';
import { defineConfig } from 'vitest/config';

// Test config for the datatable module (tests/). Kept separate from
// vite.config.ts so the SvelteKit build pipeline is untouched; the svelte()
// plugin still picks up svelte.config.js (vitePreprocess for lang="ts").
export default defineConfig({
	plugins: [svelte(), svelteTesting()],
	// The one build-time global vite.config.ts injects (see $lib/seo/config.ts).
	// Anything that pulls in <Seo> — which means anything that renders <SlideDeck> —
	// hits a bare ReferenceError without it. The value is irrelevant to the tests;
	// its presence is not.
	define: {
		__GEEKPRESENT_SITE_URL__: JSON.stringify('https://example.test')
	},
	resolve: {
		alias: {
			// SvelteKit aliases for the standalone test build: $lib as usual;
			// $app/environment stubbed (no Kit runtime under vitest).
			$lib: new URL('./src/lib', import.meta.url).pathname,
			'$app/environment': new URL('./tests/stubs/app-environment.ts', import.meta.url).pathname,
			'$app/stores': new URL('./tests/stubs/app-stores.ts', import.meta.url).pathname,
			'$app/navigation': new URL('./tests/stubs/app-navigation.ts', import.meta.url).pathname,
			'$app/paths': new URL('./tests/stubs/app-paths.ts', import.meta.url).pathname
		}
	},
	test: {
		name: 'dom',
		environment: 'jsdom',
		include: ['tests/**/*.test.ts'],
		// *.ssr.test.ts belongs to the ssr project (vitest.ssr.config.ts)
		exclude: ['tests/**/*.ssr.test.ts', '**/node_modules/**']
	}
});
