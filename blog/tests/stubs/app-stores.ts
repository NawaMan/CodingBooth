// Stub for SvelteKit's `$app/stores` in the standalone vitest projects (no Kit runtime
// there). Components that read `$page` (e.g. Note.svelte) need a readable `page` with a
// `url`; for most tests the exact path is irrelevant.
//
// It is a WRITABLE, not a readable, so a test can drive the URL — which is the only way to
// reach the behaviour SlideDeck hangs off query flags (`?clean`, `?present`, `?shot`). The
// default is unchanged, so every existing test sees exactly what it saw before.
import { writable } from 'svelte/store';

const DEFAULT_URL = 'http://localhost/slides/stub.html';

export const page = writable({ url: new URL(DEFAULT_URL) });
export const navigating = writable(null);
export const updated = writable(false);

/** Point `$page` at a URL (absolute, or relative to the default slide). */
export function setPageUrl(href: string): void {
	page.set({ url: new URL(href, DEFAULT_URL) });
}

/** Back to the default slide — call in an afterEach, since this is module state shared by
    every test in the file. */
export function resetPageUrl(): void {
	page.set({ url: new URL(DEFAULT_URL) });
}
