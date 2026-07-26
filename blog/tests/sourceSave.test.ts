import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { savePageSource, loadPageSource } from '../src/lib/stores/sourceSave';

// Client half of ViewSource SAVE / REFRESH — what it POSTs/GETs, what it refuses,
// and how server errors surface. No Vite server; fetch is mocked.

const originalFetch = globalThis.fetch;
const originalPathname = window.location.pathname;

beforeEach(() => {
	// @ts-expect-error — jsdom allows redefining pathname via history in some setups;
	// assign a stub location shape when needed.
	Object.defineProperty(window, 'location', {
		configurable: true,
		value: { ...window.location, pathname: '/slides/title.html' }
	});
});

afterEach(() => {
	globalThis.fetch = originalFetch;
	Object.defineProperty(window, 'location', {
		configurable: true,
		value: { ...window.location, pathname: originalPathname }
	});
	vi.restoreAllMocks();
});

describe('savePageSource', () => {
	it('refuses empty content without calling the server', async () => {
		const fetchSpy = vi.fn();
		globalThis.fetch = fetchSpy as unknown as typeof fetch;
		const r = await savePageSource('');
		expect(r.ok).toBe(false);
		expect(r.error).toMatch(/empty/i);
		expect(fetchSpy).not.toHaveBeenCalled();
	});

	it('POSTs route + content to the source-save endpoint', async () => {
		globalThis.fetch = vi.fn(async () =>
			new Response(JSON.stringify({ file: 'src/routes/slides/title.html/+page.svelte' }), {
				status: 200,
				headers: { 'content-type': 'application/json' }
			})
		) as unknown as typeof fetch;

		const r = await savePageSource('<script></script>');
		expect(r.ok).toBe(true);
		expect(r.file).toContain('+page.svelte');

		expect(globalThis.fetch).toHaveBeenCalledWith(
			'/__geekpresent/source-save',
			expect.objectContaining({
				method: 'POST',
				headers: { 'content-type': 'application/json' }
			})
		);
		const body = JSON.parse((globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls[0][1].body);
		expect(body).toEqual({ route: '/slides/title.html', content: '<script></script>' });
	});

	it('uses an explicit slide route (popup must not POST /_source-edit)', async () => {
		globalThis.fetch = vi.fn(async () =>
			new Response(JSON.stringify({ file: 'x' }), {
				status: 200,
				headers: { 'content-type': 'application/json' }
			})
		) as unknown as typeof fetch;

		const r = await savePageSource('<p/>', '/slides/viewsource-edit.html');
		expect(r.ok).toBe(true);
		const body = JSON.parse((globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls[0][1].body);
		expect(body.route).toBe('/slides/viewsource-edit.html');
	});

	it('refuses to save when the only route is the editor page itself', async () => {
		const fetchSpy = vi.fn();
		globalThis.fetch = fetchSpy as unknown as typeof fetch;
		Object.defineProperty(window, 'location', {
			configurable: true,
			value: { ...window.location, pathname: '/_source-edit' }
		});
		const r = await savePageSource('<p/>');
		expect(r.ok).toBe(false);
		expect(r.error).toMatch(/slide route/i);
		expect(fetchSpy).not.toHaveBeenCalled();
	});

	it('surfaces HTTP errors from the server', async () => {
		globalThis.fetch = vi.fn(async () =>
			new Response(JSON.stringify({ error: 'no +page.svelte for route' }), {
				status: 404,
				headers: { 'content-type': 'application/json' }
			})
		) as unknown as typeof fetch;

		const r = await savePageSource('x');
		expect(r.ok).toBe(false);
		expect(r.error).toMatch(/no \+page/);
	});

	it('surfaces network failures', async () => {
		globalThis.fetch = vi.fn(async () => {
			throw new Error('offline');
		}) as unknown as typeof fetch;

		const r = await savePageSource('x');
		expect(r.ok).toBe(false);
		expect(r.error).toBe('offline');
	});
});

describe('loadPageSource (REFRESH)', () => {
	it('GETs the source-load endpoint with the slide route', async () => {
		globalThis.fetch = vi.fn(async () =>
			new Response(
				JSON.stringify({
					file: 'src/routes/slides/title.html/+page.svelte',
					content: '<script></script>\n'
				}),
				{ status: 200, headers: { 'content-type': 'application/json' } }
			)
		) as unknown as typeof fetch;

		const r = await loadPageSource('/slides/title.html');
		expect(r.ok).toBe(true);
		expect(r.content).toContain('<script>');
		expect(globalThis.fetch).toHaveBeenCalledWith(
			'/__geekpresent/source-load?route=%2Fslides%2Ftitle.html',
			expect.objectContaining({ method: 'GET' })
		);
	});

	it('refuses the editor page as a route', async () => {
		const fetchSpy = vi.fn();
		globalThis.fetch = fetchSpy as unknown as typeof fetch;
		Object.defineProperty(window, 'location', {
			configurable: true,
			value: { ...window.location, pathname: '/_source-edit' }
		});
		const r = await loadPageSource();
		expect(r.ok).toBe(false);
		expect(fetchSpy).not.toHaveBeenCalled();
	});

	it('surfaces HTTP errors', async () => {
		globalThis.fetch = vi.fn(async () =>
			new Response(JSON.stringify({ error: 'no +page.svelte for route' }), {
				status: 404,
				headers: { 'content-type': 'application/json' }
			})
		) as unknown as typeof fetch;

		const r = await loadPageSource('/slides/missing.html');
		expect(r.ok).toBe(false);
		expect(r.error).toMatch(/no \+page/);
	});
});
