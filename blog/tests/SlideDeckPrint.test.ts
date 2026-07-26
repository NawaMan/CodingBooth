// Ctrl+P on a slide — the print render.
//
// A deck is a viewport: a canvas scaled to whatever window it found. Paper is not a window, and
// left to itself the browser photographs the viewport — which is how the slide used to come out
// chopped down the right-hand side of a portrait sheet. So printing takes the same deal the
// handout takes: the SHEET becomes the shape of the canvas, and the canvas is scaled onto it.
//
// Almost all of that is `@media print` CSS, which jsdom does not apply — so what CAN be pinned
// here is the part that isn't CSS, and it happens to be the part that carries the arithmetic:
// the `@page` rule the deck emits, and the `--print-scale` it hands the stylesheet. If either
// drifts from handoutCore, a printed slide and that slide inside a handout stop being the same
// size, and the only way to notice is to print both and measure them.
import { fireEvent, render } from '@testing-library/svelte';
import { tick } from 'svelte';
import { get } from 'svelte/store';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import SlideDeck from '$lib/components/SlideDeck.svelte';
import { DEFAULT_BASE_FONT, pageRule, sheetMetrics } from '$lib/handout/handoutCore';
import { printNotes } from '$lib/stores/printNotes';
import { overviewOpen } from '$lib/stores/overviewOpen';
import { setPageUrl, resetPageUrl } from './stubs/app-stores';

const pages = [{ path: 'stub.html', title: 'Stub' }];

async function mount(props: Record<string, unknown> = {}) {
	setPageUrl('/slides/stub.html');
	const { container } = render(SlideDeck, { props: { pages, ...props } });
	await tick();
	await tick();
	return container;
}

afterEach(() => resetPageUrl());

const styles = () =>
	Array.from(document.head.querySelectorAll('style'))
		.map((s) => s.textContent ?? '')
		.join('\n');

describe('SlideDeck — printing one slide', () => {
	it('gives the paper the shape of the canvas', async () => {
		await mount();
		// The standard 16:9 slide page — the same one the handout prints on, because it is the
		// same function that decided it.
		expect(styles()).toContain('@page { size: 13.333in 7.937in; margin: 0.5in; }');
	});

	it('transposes for a portrait deck, from the same arithmetic', async () => {
		await mount({ width: 1080, height: 1920 });
		expect(styles()).toContain('@page { size: 7.937in 13.333in; margin: 0.5in; }');
	});

	it('hands the stylesheet the scale, because CSS cannot divide inches by pixels', async () => {
		const root = await mount();
		const frame = root.querySelector('.container') as HTMLElement;
		// Not a number this file chose: the one handoutCore chose, so a printed slide is exactly
		// the size that slide is on a handout sheet.
		const expected = String(sheetMetrics({ width: 1920, height: 1080 }).scale);
		expect(frame.style.getPropertyValue('--print-scale')).toBe(expected);
	});

	it('`?notes` grows the paper by the notes band, and arms the note to render', async () => {
		// The same flag the handout takes, and the same three inches. It reaches <Note> through a
		// store rather than context, because a slide is the ADJUST's slot content and cannot see
		// anything the shell sets — the same reason setPages() lives in each deck's layout.
		setPageUrl('/slides/stub.html?notes');
		const { container } = render(SlideDeck, { props: { pages } });
		await tick();
		await tick();

		expect(styles()).toContain('@page { size: 13.333in 10.937in; margin: 0.5in; }');
		expect(get(printNotes)).toBe(true);
		const frame = container.querySelector('.container') as HTMLElement;
		expect(frame.classList.contains('print-notes')).toBe(true);
		expect(frame.style.getPropertyValue('--print-notes-h')).toBe('288px'); // 3in x 96
	});

	it('agrees with handoutCore about the em lever — the one thing nothing else can catch', async () => {
		// SlideDeck's `baseFontSize` default and handoutCore's DEFAULT_BASE_FONT are the SAME
		// number written in two places, and they have to be: the handout never mounts SlideDeck,
		// so it cannot read the prop's default and has to restate it. Let them drift and the deck
		// presents at one size and prints at another — legible either way, so nothing looks broken.
		const root = await mount();
		const frame = root.querySelector('.container') as HTMLElement;
		expect(frame.style.getPropertyValue('--base-font')).toBe(DEFAULT_BASE_FONT);
	});

	it('leaves the note alone when nobody asked for it', async () => {
		const root = await mount();
		expect(get(printNotes)).toBe(false);
		expect((root.querySelector('.container') as HTMLElement).style.getPropertyValue('--print-notes-h')).toBe('0px');
	});

	it('never emits NaN into the page size — a bad @page takes the whole print job with it', async () => {
		await mount({ width: 0, height: -1 });
		const css = styles();
		expect(css).not.toContain('NaN');
		// A deck with no honest canvas falls back to 1920x1080 rather than to no paper at all.
		expect(css).toContain(pageRule(sheetMetrics({ width: 1920, height: 1080 })));
	});
});

describe('SlideDeck — the PRINT menu', () => {
	// jsdom has no window.print; the menu's "this slide" items call it, so give it a spy.
	// The OVERVIEW test opens the grid, which reaches for Resize/IntersectionObserver.
	class FakeObs {
		observe() {}
		unobserve() {}
		disconnect() {}
	}
	beforeEach(() => {
		window.print = vi.fn();
		vi.stubGlobal('ResizeObserver', FakeObs);
		vi.stubGlobal('IntersectionObserver', FakeObs);
	});
	afterEach(() => vi.unstubAllGlobals());

	// Match the tool, not its decorated label: the chrome may underline a mnemonic
	// letter and add a "▸" submenu marker (e.g. "PRINT ▸", "OVERVIEW"), so find by prefix.
	const printButton = (root: ParentNode) =>
		[...root.querySelectorAll('.annot-tool')].find(
			(b) => b.textContent?.trim().startsWith('PRINT')
		) as HTMLElement;

	it('PRINT opens a flyout of the honest destinations', async () => {
		// The button no longer prints on click — the browser's own dialog cannot ask "this slide
		// or the whole deck? one per page, a grid, with notes or without?", so the flyout does.
		const root = await mount({ annotate: true });
		expect(root.querySelector('.print-sub')).toBeNull();

		await fireEvent.click(printButton(root));
		const items = [...root.querySelectorAll('.print-sub .print-sub-label')].map((b) =>
			b.textContent?.trim()
		);
		expect(items).toEqual([
			'Current slide',
			'Current + notes',
			'Whole deck',
			'Whole + notes',
			'Thumbnail grid',
			'Notes grid'
		]);
	});

	it('"Current + notes" grows the paper and prints — WITHOUT navigating', async () => {
		// The notes toggle for a single slide is a local override, not a trip to `?notes`, so it
		// has to reach the DOM before the (blocking) print fires. Here: the frame is marked and the
		// paper has grown its band by the time print is called.
		const root = await mount({ annotate: true });
		await fireEvent.click(printButton(root));
		const notes = [...root.querySelectorAll('.print-sub button')].find((b) =>
			b.textContent?.includes('Current + notes')
		) as HTMLElement;
		await fireEvent.click(notes);
		await tick();
		await tick();

		expect((root.querySelector('.container') as HTMLElement).classList.contains('print-notes')).toBe(true);
		expect(styles()).toContain('@page { size: 13.333in 10.937in; margin: 0.5in; }');
		expect(window.print).toHaveBeenCalled();
	});

	it('closes on Escape, and on mouseleave off the flyout', async () => {
		const root = await mount({ annotate: true });

		await fireEvent.click(printButton(root));
		expect(root.querySelector('.print-sub')).not.toBeNull();
		await fireEvent.keyDown(window, { key: 'Escape' });
		expect(root.querySelector('.print-sub')).toBeNull();

		// The flyout is a nested hover menu now — no scrim; leaving it dismisses it.
		await fireEvent.click(printButton(root));
		expect(root.querySelector('.print-sub')).not.toBeNull();
		await fireEvent.mouseLeave(root.querySelector('.print-flyout') as HTMLElement);
		expect(root.querySelector('.print-sub')).toBeNull();
	});

	it('the OVERVIEW tool opens the all-slides grid, through the shared store', async () => {
		// OVERVIEW joins the flyout as the fourth tool. It has no grid of its own — it flips the
		// same `overviewOpen` store the `o` key does, so the two ways in cannot disagree.
		overviewOpen.set(false);
		const root = await mount({ annotate: true });
		const overview = [...root.querySelectorAll('.annot-tool')].find(
			(b) => b.textContent?.trim().startsWith('OVERVIEW')
		) as HTMLElement;
		expect(overview).toBeTruthy();
		expect(get(overviewOpen)).toBe(false);
		await fireEvent.click(overview);
		expect(get(overviewOpen)).toBe(true);
		overviewOpen.set(false);
	});
});
