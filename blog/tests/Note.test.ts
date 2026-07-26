import { render } from '@testing-library/svelte';
import { tick } from 'svelte';
import { get } from 'svelte/store';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import NoteHighlightHost from './NoteHighlightHost.svelte';
import { presenterMode } from '../src/lib/stores/presenter';
import { highlightTarget, setHighlight } from '../src/lib/stores/highlightTarget';

// The note-driven highlight trigger: covering (hovering) a `data-highlight` line in
// the presenter console lights that Block on the audience slide. The checklist
// action only wires this up in presenter mode, so the test turns it on. (The
// overlay that renders the cue is Spotlight; here we assert only that the trigger
// drives the store the overlay reads.)
const lines = (root: ParentNode) => [...root.querySelectorAll('.note li')] as HTMLElement[];

beforeEach(() => {
	setHighlight(null);
	presenterMode.set(true);
});
afterEach(() => presenterMode.set(false));

describe('Note — data-highlight trigger', () => {
	it('marks only the lines that carry a data-highlight', async () => {
		const { container } = render(NoteHighlightHost);
		await tick();
		const [db, plain, cache] = lines(container);
		expect(db.classList.contains('gp-hl-line')).toBe(true);
		expect(cache.classList.contains('gp-hl-line')).toBe(true);
		expect(plain.classList.contains('gp-hl-line')).toBe(false);
	});

	it('lights the named Block on hover and clears on leave', async () => {
		const { container } = render(NoteHighlightHost);
		await tick();
		const [db] = lines(container);

		db.dispatchEvent(new Event('pointerenter'));
		expect(get(highlightTarget)).toBe('db');

		db.dispatchEvent(new Event('pointerleave'));
		expect(get(highlightTarget)).toBeNull();
	});

	it('a plain line drives no highlight', async () => {
		const { container } = render(NoteHighlightHost);
		await tick();
		const plain = lines(container)[1];
		// No listener was attached, but dispatching proves it does nothing.
		plain.dispatchEvent(new Event('pointerenter'));
		expect(get(highlightTarget)).toBeNull();
	});

	it('moving between lines lands on the last covered box', async () => {
		const { container } = render(NoteHighlightHost);
		await tick();
		const [db, , cache] = lines(container);

		db.dispatchEvent(new Event('pointerenter'));
		// Pointer moves off db onto cache: leave fires before the next enter.
		db.dispatchEvent(new Event('pointerleave'));
		cache.dispatchEvent(new Event('pointerenter'));
		expect(get(highlightTarget)).toBe('cache');
	});
});
