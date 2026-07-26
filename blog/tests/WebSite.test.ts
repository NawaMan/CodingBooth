import { render } from '@testing-library/svelte';
import { tick } from 'svelte';
import { afterEach, describe, expect, it, vi } from 'vitest';
import WebSite from '../src/lib/components/WebSite.svelte';

// The interactive half of WebSite (the SSR half — what prerendering emits — is in
// WebSiteSsr.ssr.test.ts). Two behaviours carry the component:
//
//   SHIELD — an iframe swallows clicks, scrolls and keys, so on a slide it would eat
//   the presenter's paging keys. The frame stays `pointer-events: none` behind a
//   shield until clicked, and the next click anywhere outside hands control back.
//
//   LAZY MOUNT — the iframe is created only once the box scrolls into view, so a
//   prerendered slide makes no third-party request until a reader actually looks at
//   it. Where IntersectionObserver is missing we mount eagerly rather than show a
//   placeholder that never resolves.

const SRC = 'https://svelte.dev/docs';

const frame = (root: ParentNode) => root.querySelector('iframe');
const shield = (root: ParentNode) => root.querySelector('.shield') as HTMLElement | null;
const level = (root: ParentNode) => root.querySelector('.level') as HTMLButtonElement;
const btn = (root: ParentNode, aria: string) =>
	root.querySelector(`[aria-label="${aria}"]`) as HTMLButtonElement;
/** The frame's scale, read back off the inline transform (absent at 1:1). */
const scaleOf = (root: ParentNode) =>
	Number(frame(root)!.getAttribute('style')?.match(/scale\(([\d.]+)\)/)?.[1] ?? 1);

/** Install a fake IntersectionObserver; returns a trigger for the intersection. */
function stubObserver() {
	let fire: () => void = () => {};
	const disconnect = vi.fn();
	class FakeIO {
		constructor(cb: (entries: Array<{ isIntersecting: boolean }>) => void) {
			fire = () => cb([{ isIntersecting: true }]);
		}
		observe() {}
		disconnect = disconnect;
	}
	vi.stubGlobal('IntersectionObserver', FakeIO);
	return { enterView: () => fire(), disconnect };
}

afterEach(() => vi.unstubAllGlobals());

describe('WebSite — lazy mount', () => {
	it('holds the placeholder until the box scrolls into view, then mounts once', async () => {
		const { enterView, disconnect } = stubObserver();
		const { container } = render(WebSite, { props: { src: SRC } });

		expect(frame(container)).toBeNull();
		expect(container.querySelector('.placeholder a')).toHaveProperty('href', SRC);

		enterView();
		await tick();

		expect(frame(container)).not.toBeNull();
		expect(disconnect).toHaveBeenCalled(); // one-shot: stop observing after mount
	});

	it('mounts eagerly where IntersectionObserver is absent — never a dead placeholder', async () => {
		vi.stubGlobal('IntersectionObserver', undefined);
		const { container } = render(WebSite, { props: { src: SRC } });
		await tick();
		expect(frame(container)).not.toBeNull();
	});

	it('lazy={false} mounts the frame immediately, without observing anything', () => {
		const { disconnect } = stubObserver();
		const { container } = render(WebSite, { props: { src: SRC, lazy: false } });
		expect(frame(container)).not.toBeNull();
		expect(disconnect).not.toHaveBeenCalled();
	});
});

describe('WebSite — reload', () => {
	it('re-keys the iframe, because a cross-origin frame cannot be reloaded in place', async () => {
		const { container } = render(WebSite, { props: { src: SRC, lazy: false } });
		const before = frame(container);

		btn(container, 'Reload the page').click();
		await tick();

		const after = frame(container);
		expect(after).not.toBeNull();
		expect(after).not.toBe(before); // a NEW element — that is the refetch
		expect(after!.getAttribute('src')).toBe(SRC);
	});

	it('survives a reload with the viewer\'s zoom intact', async () => {
		const { container } = render(WebSite, { props: { src: SRC, lazy: false } });
		btn(container, 'Zoom in').click();
		await tick();

		btn(container, 'Reload the page').click();
		await tick();
		expect(level(container).textContent).toBe('110%');
		expect(scaleOf(container)).toBe(1.1);
	});
});

describe('WebSite — live zoom', () => {
	const opts = { props: { src: SRC, lazy: false } };

	it('steps along the ladder, one stop at a time', async () => {
		const { container } = render(WebSite, { props: { ...opts.props, zoom: 0.9 } });
		expect(level(container).textContent).toBe('90%');

		btn(container, 'Zoom in').click();
		await tick();
		expect(level(container).textContent).toBe('100%');
		expect(scaleOf(container)).toBe(1); // 1:1 → no transform at all

		btn(container, 'Zoom out').click();
		await tick();
		expect(level(container).textContent).toBe('90%');
		expect(scaleOf(container)).toBe(0.9);
	});

	it('an off-ladder authored zoom moves to its neighbours, not to itself', async () => {
		// 0.6 sits between the 0.5 and 0.67 stops and is on neither.
		const { container } = render(WebSite, { props: { ...opts.props, zoom: 0.6 } });
		expect(level(container).textContent).toBe('60%');

		btn(container, 'Zoom in').click();
		await tick();
		expect(level(container).textContent).toBe('67%');

		btn(container, 'Zoom out').click();
		btn(container, 'Zoom out').click();
		await tick();
		expect(level(container).textContent).toBe('33%'); // 0.67 → 0.5 → 0.33
	});

	it('a round trip lands exactly back on 1:1 — the ladder cannot drift', async () => {
		const { container } = render(WebSite, opts);
		for (let i = 0; i < 4; i++) btn(container, 'Zoom in').click();
		for (let i = 0; i < 4; i++) btn(container, 'Zoom out').click();
		await tick();
		expect(level(container).textContent).toBe('100%');
		expect(scaleOf(container)).toBe(1); // exactly 1, so the transform is dropped
	});

	it('the ladder ends ARE the clamp; the spent button disables', async () => {
		const { container } = render(WebSite, opts);

		for (let i = 0; i < 20; i++) btn(container, 'Zoom in').click();
		await tick();
		expect(level(container).textContent).toBe('400%');
		expect(btn(container, 'Zoom in').disabled).toBe(true);
		expect(btn(container, 'Zoom out').disabled).toBe(false);

		for (let i = 0; i < 40; i++) btn(container, 'Zoom out').click();
		await tick();
		expect(level(container).textContent).toBe('25%');
		expect(btn(container, 'Zoom out').disabled).toBe(true);
	});

	it('zoomLevels replaces the ladder — stops and clamp both follow it', async () => {
		const { container } = render(WebSite, {
			props: { ...opts.props, zoom: 0.5, zoomLevels: [0.5, 1, 2] }
		});
		expect(btn(container, 'Zoom out').disabled).toBe(true); // 0.5 is the floor now

		btn(container, 'Zoom in').click();
		await tick();
		expect(level(container).textContent).toBe('100%');

		btn(container, 'Zoom in').click();
		await tick();
		expect(level(container).textContent).toBe('200%');
		expect(btn(container, 'Zoom in').disabled).toBe(true); // ...and 2 the ceiling
	});

	it('sorts and de-dupes a hand-written ladder, and ignores junk in it', async () => {
		const { container } = render(WebSite, {
			props: { ...opts.props, zoom: 1, zoomLevels: [2, 0.5, 1, 2, NaN, -3, 0] }
		});
		btn(container, 'Zoom out').click();
		await tick();
		expect(level(container).textContent).toBe('50%'); // sorted: the stop below 1

		btn(container, 'Zoom in').click();
		btn(container, 'Zoom in').click();
		await tick();
		expect(level(container).textContent).toBe('200%'); // de-duped: one stop at 2, is the top
		expect(btn(container, 'Zoom in').disabled).toBe(true);
	});

	it('an empty or all-invalid ladder falls back to the default rather than freezing', async () => {
		const { container } = render(WebSite, { props: { ...opts.props, zoomLevels: [] } });
		btn(container, 'Zoom in').click();
		await tick();
		expect(level(container).textContent).toBe('110%'); // the default ladder's next stop
	});

	it('clicking the percentage snaps back to the zoom the slide author set', async () => {
		const { container } = render(WebSite, { props: { ...opts.props, zoom: 0.6 } });
		btn(container, 'Zoom in').click();
		await tick();
		expect(level(container).textContent).not.toBe('60%');

		level(container).click();
		await tick();
		expect(level(container).textContent).toBe('60%');
	});

	it('a viewer\'s zoom survives an unrelated prop change, but yields to a new `zoom`', async () => {
		const { container, rerender } = render(WebSite, { props: { ...opts.props, zoom: 1 } });
		btn(container, 'Zoom in').click();
		await tick();
		expect(level(container).textContent).toBe('110%');

		// Some other prop moves: the viewer's zoom must not be stomped.
		await rerender({ ...opts.props, zoom: 1, title: 'Renamed' });
		expect(level(container).textContent).toBe('110%');

		// The author's own zoom moves: that DOES re-seed.
		await rerender({ ...opts.props, zoom: 0.5, title: 'Renamed' });
		expect(level(container).textContent).toBe('50%');
	});

	it('controls={false} drops the cluster but keeps the bar', () => {
		const { container } = render(WebSite, { props: { ...opts.props, controls: false } });
		expect(container.querySelector('.zoom')).toBeNull();
		expect(btn(container, 'Reload the page')).toBeNull();
		expect(container.querySelector('.bar')).not.toBeNull();
	});
});

describe('WebSite — shield', () => {
	const opts = { props: { src: SRC, lazy: false } };

	it('starts inert: the frame is shielded and takes no pointer events', () => {
		const { container } = render(WebSite, opts);
		expect(shield(container)).not.toBeNull();
		expect(frame(container)!.classList.contains('live')).toBe(false);
	});

	it('the shield shows nothing — it explains itself with a tooltip, not a badge', () => {
		const { container } = render(WebSite, opts);
		const s = shield(container)!;
		expect(s.textContent!.trim()).toBe(''); // no "Click to interact" label on the site
		expect(s.getAttribute('title')).toBe('Click to interact with svelte.dev');
		expect(s.getAttribute('aria-label')).toBe('Click to interact with svelte.dev');
	});

	it('clicking the shield arms the frame; clicking outside hands control back', async () => {
		const { container } = render(WebSite, opts);

		shield(container)!.click();
		await tick();
		expect(shield(container)).toBeNull();
		expect(frame(container)!.classList.contains('live')).toBe(true);

		// A click on the surrounding slide — never one inside the iframe, which by
		// design never reaches this listener.
		document.body.dispatchEvent(new MouseEvent('pointerdown', { bubbles: true }));
		await tick();
		expect(shield(container)).not.toBeNull();
		expect(frame(container)!.classList.contains('live')).toBe(false);
	});

	it('a click INSIDE the component (e.g. the chrome bar) leaves it armed', async () => {
		const { container } = render(WebSite, opts);
		shield(container)!.click();
		await tick();

		container.querySelector('.bar')!.dispatchEvent(new MouseEvent('pointerdown', { bubbles: true }));
		await tick();
		expect(frame(container)!.classList.contains('live')).toBe(true);
	});

	it('the Release pill disarms without needing a click elsewhere', async () => {
		const { container } = render(WebSite, opts);
		shield(container)!.click();
		await tick();

		const release = [...container.querySelectorAll('button.pill')].find(
			(b) => b.textContent?.trim() === 'Release'
		) as HTMLButtonElement;
		release.click();
		await tick();
		expect(shield(container)).not.toBeNull();
	});

	it('interactive={true} drops the shield for good — no arming, no release pill', () => {
		const { container } = render(WebSite, { props: { src: SRC, lazy: false, interactive: true } });
		expect(shield(container)).toBeNull();
		expect(frame(container)!.classList.contains('live')).toBe(true);
		expect(container.textContent).not.toContain('Release');
	});

	it('the bar controls work WITHOUT arming — reachable while the frame is inert', async () => {
		const { container } = render(WebSite, opts);
		expect(shield(container)).not.toBeNull(); // still shielded throughout

		btn(container, 'Zoom in').click();
		await tick();
		expect(level(container).textContent).toBe('110%');
		expect(shield(container)).not.toBeNull();
	});

	it('stops listening for outside clicks once unmounted', async () => {
		const { container, unmount } = render(WebSite, opts);
		shield(container)!.click();
		await tick();

		const removeSpy = vi.spyOn(window, 'removeEventListener');
		unmount();
		expect(removeSpy).toHaveBeenCalledWith('pointerdown', expect.any(Function), true);
	});
});
