// The `?shot` render mode — the build-time screenshot view (utils/capture-slides.sh).
//
// It is the one mode that deliberately does NOT fit the slide to the window: the canvas at
// exactly 1:1, flush to the top-left, no frame border, no letterbox, no chrome. Point a
// headless browser at it with a window the size of the canvas and the VIEWPORT IS THE SLIDE,
// so the PNG needs no cropping and no rescaling.
//
// Everything below is a property the capture script silently depends on. If `?shot` quietly
// started fitting the slide again, or stopped implying `?clean`, nothing would throw — the
// script would just start emitting scaled-down PNGs with a nav bar in the corner, and the only
// way to notice would be to look at 65 images.
import { render } from '@testing-library/svelte';
import { tick } from 'svelte';
import { afterEach, describe, expect, it } from 'vitest';
import SlideDeck from '$lib/components/SlideDeck.svelte';
import { setPageUrl, resetPageUrl } from './stubs/app-stores';

const pages = [{ path: 'stub.html', title: 'Stub' }];

async function mount(query = '') {
	setPageUrl(`/slides/stub.html${query}`);
	const { container } = render(SlideDeck, { props: { pages } });
	await tick();
	await tick(); // onMount → initialized → the content and its chrome render
	return container;
}

const viewport = (root: ParentNode) => root.querySelector('.viewport') as HTMLElement;
const frame = (root: ParentNode) => root.querySelector('.container') as HTMLElement;
const content = (root: ParentNode) => root.querySelector('.content') as HTMLElement;

afterEach(resetPageUrl);

describe('?shot — the screenshot render', () => {
	it('marks the viewport and the frame, so the CSS can strip the border and the letterbox', async () => {
		const root = await mount('?shot');
		expect(viewport(root).classList.contains('shot')).toBe(true);
		expect(frame(root).classList.contains('shot')).toBe(true);
	});

	it('does NOT scale the slide to the window — the whole point', async () => {
		// adjustSize returns early in shot mode, so nothing sizes the frame and nothing
		// transforms the content. The canvas stays at its true 1:1, which is what makes a
		// window sized to the canvas produce a pixel-exact PNG with no cropping.
		const root = await mount('?shot');
		expect(content(root).style.transform).toBe('');
		expect(frame(root).style.width).toBe('');
		expect(frame(root).style.height).toBe('');
	});

	it('…whereas an ordinary slide IS fitted to the window', async () => {
		// The contrast that gives the test above its meaning: fitting is what a human wants,
		// and exactly what a screenshot must not do.
		const root = await mount();
		expect(content(root).style.transform).toMatch(/^scale\(/);
		expect(viewport(root).classList.contains('shot')).toBe(false);
		expect(frame(root).classList.contains('shot')).toBe(false);
	});

	it('implies ?clean — a screenshot never wants the chrome', async () => {
		const root = await mount('?shot');
		expect(frame(root).classList.contains('clean')).toBe(true);
		// The whole top-centre tool cluster (PRESENT anchor + the ANNOTATE/ADJUST/OVERVIEW/
		// CAPTURE/PRINT menu) is gone — it only renders while `chrome` is on, and ?shot (via
		// ?clean) turns chrome off.
		expect(root.querySelector('.annot-tools')).toBeNull();
	});

	it('leaves the chrome alone on an ordinary slide', async () => {
		// Otherwise the test above would pass for the wrong reason (chrome that never renders).
		const root = await mount();
		expect(frame(root).classList.contains('clean')).toBe(false);
		expect(root.querySelector('.annot-tools')).not.toBeNull();
	});

	it('is not the same thing as ?clean', async () => {
		// ?clean hides the chrome but still FITS the slide to the window, so it is not a
		// substitute — a screenshot taken in ?clean is scaled by whatever fraction the frame's
		// own border happens to cost.
		const root = await mount('?clean');
		expect(frame(root).classList.contains('clean')).toBe(true);
		expect(frame(root).classList.contains('shot')).toBe(false);
		expect(content(root).style.transform).toMatch(/^scale\(/);
	});
});
