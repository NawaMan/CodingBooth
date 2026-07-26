// Stub for SvelteKit's `$app/environment` in the standalone vitest projects
// (no SvelteKit runtime there). `browser` mirrors the real semantics per
// project: true under jsdom (dom project), false under node (ssr project).
export const browser = typeof window !== 'undefined';
export const building = false;
export const dev = false;
export const version = 'test';
