// @vitest-environment node
//
// True server-side render of SlideToolbar (svelte/server, no DOM). Like <Annotate>, the toolbar
// is authoring chrome that must be SSR-INERT: it is `browser`-gated, so a prerendered slide ships
// no toolbar, no ANNOTATE toggle and no DISPLAY control — none of it belongs in the static HTML of
// a deck built on a dev machine, and shipping it would bake one author's window state into every
// visitor's page.
import { render } from 'svelte/server';
import { afterEach, describe, expect, it } from 'vitest';
import SlideToolbar from '../src/lib/components/SlideToolbar.svelte';
import { annotationMode, canAnnotate } from '../src/lib/stores/annotation';

// No onDestroy on the server, so module state survives between renders.
afterEach(() => {
	annotationMode.set(false);
	canAnnotate.set(false);
});

describe('SlideToolbar (SSR)', () => {
	it('prerenders NOTHING — no bar, no toggle, no DISPLAY control', () => {
		const { body } = render(SlideToolbar, { props: {} });
		expect(body).not.toContain('annot-tools');
		expect(body).not.toContain('annot-tab');
		expect(body).not.toContain('ANNOTATE');
		expect(body).not.toContain('class="mode');
	});

	it('stays inert even if the pen were somehow armed at prerender', () => {
		annotationMode.set(true);
		canAnnotate.set(true);
		const { body } = render(SlideToolbar, { props: {} });
		expect(body).not.toContain('annot-tools');
	});
});
