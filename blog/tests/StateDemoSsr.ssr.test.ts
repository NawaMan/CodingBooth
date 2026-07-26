// @vitest-environment node
import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';
import StateSsrHost from './StateSsrHost.svelte';
import { persisted, reset } from '../src/lib/stores/persisted';
import { numberCodec, readNumberParam, readTextParam } from '../src/lib/utils/stateCore';
import { get } from 'svelte/store';

describe('state — the SSR boundary', () => {
	it('prerenders without a window or a localStorage in sight', () => {
		// The point of the whole exercise. In the node project there IS no `window` and no
		// `localStorage`; if `persisted` reached for either, this render would throw a
		// ReferenceError rather than fail an assertion — which is exactly how it fails a
		// real `vite build`.
		expect(typeof window).toBe('undefined');
		expect(() => render(StateSsrHost, { props: {} })).not.toThrow();
	});

	const { body } = render(StateSsrHost, { props: {} });

	it('shows the DEFAULTS, never a remembered value', () => {
		expect(body).toContain('SSR_STATE_MARKER');
		// The prerender happens ONCE at build time and is served to every visitor, so a
		// browser-specific value baked in here would be wrong for everyone but its author.
		expect(body).toContain('>0<');
		expect(body).toContain('>world<');
	});

	it('emits no NaN and no undefined into the served markup', () => {
		expect(body).not.toContain('NaN');
		expect(body).not.toContain('undefined');
	});
});

describe('persisted — degrades to plain memory on the server', () => {
	it('is an ordinary writable: it holds its initial value and still accepts writes', () => {
		const count = persisted('geekpresent:ssr:count', 3, { codec: numberCodec() });
		expect(get(count)).toBe(3);

		// A store that THREW on the server would make any slide that writes during init
		// unbuildable. It must simply forget instead.
		expect(() => count.set(8)).not.toThrow();
		expect(get(count)).toBe(8);

		reset(count, 3);
		expect(get(count)).toBe(3);
	});
});

describe('stateCore — pure enough to run anywhere', () => {
	it('reads params with no DOM at all', () => {
		const search = new URLSearchParams('name=Ada&count=7');
		expect(readTextParam(search, 'name', '')).toBe('Ada');
		expect(readNumberParam(search, 'count', 0, { min: 0, max: 99 })).toBe(7);
	});

	it('answers the SSR shape — no URL — with the fallback', () => {
		expect(readTextParam(null, 'name', 'world')).toBe('world');
		expect(readNumberParam(undefined, 'count', 0)).toBe(0);
	});
});
