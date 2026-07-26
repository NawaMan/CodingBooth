// @vitest-environment node
//
// Prerender safety for the presenter feature. A <Note> is shown only in SCALED
// display mode or in a presenter window (?present) — both are runtime, browser
// state. Server-side the defaults are FITTED + presenterMode=false, so the note
// must emit NOTHING. This proves speaker notes never leak into prerendered HTML,
// and that ?present adds no server output (it is browser-guarded in SlideDeck).
import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';
import NoteSsrHost from './NoteSsrHost.svelte';

describe('Note (SSR)', () => {
	it('renders nothing server-side — notes never appear in prerendered HTML', () => {
		const { body } = render(NoteSsrHost, { props: {} });
		expect(body).not.toContain('SPEAKER_NOTE_MARKER');
		expect(body).not.toContain('class="note');
	});
});
