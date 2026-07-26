// Stub for SvelteKit's `$app/paths` in the standalone vitest projects (no SvelteKit runtime
// there). Both are '' in this project's real config too — the site is served from the root —
// so a page that builds a URL from `base` gets the same string here that it gets in the build.
export const base = '';
export const assets = '';
