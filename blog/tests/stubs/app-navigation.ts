// Stub for SvelteKit's `$app/navigation` in the standalone vitest projects (no Kit
// runtime there). Components that page the deck (NavigationBar → utils/deckNav) or
// re-arm on navigation (AnimationBar, PresenterAnim) import this at module scope,
// so it has to resolve even in tests that never navigate. Both are inert no-ops:
// `goto` resolves without moving, `afterNavigate` never fires its callback.
/** Every href `goto` was called with, in order. Recorded so a test can assert that a
    component DID or DID NOT page — the cross-window slide relay's whole contract is
    "who may drive whom", and the only way to see a window being driven is to catch the
    navigation it makes. Additive: a test that ignores this sees the old inert stub. */
export const gotoCalls: string[] = [];

/** Empty the recording — call in a beforeEach, since it is module state shared by
    every test in the run. */
export function resetGoto(): void {
	gotoCalls.length = 0;
}

export function goto(href?: string): Promise<void> {
	if (typeof href === 'string') gotoCalls.push(href);
	return Promise.resolve();
}
export function afterNavigate(): void {}
export function beforeNavigate(): void {}
export function invalidateAll(): Promise<void> {
	return Promise.resolve();
}
