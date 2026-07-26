import { describe, expect, it } from 'vitest';
import {
	encodeSourceEditPayload,
	parseSourceEditPayload,
	isSourceEditMessage,
	SOURCE_EDIT_MSG,
	type SourceEditPayload
} from '../src/lib/source/sourceEditSession';

const sample: SourceEditPayload = {
	route: '/slides/viewsource-edit.html',
	path: 'src/routes/slides/viewsource-edit.html/+page.svelte',
	source: '<script></script>',
	language: 'html',
	canSave: true,
	ts: 1
};

describe('sourceEditSession', () => {
	it('round-trips a payload through JSON', () => {
		const raw = encodeSourceEditPayload(sample);
		expect(parseSourceEditPayload(raw)).toEqual(sample);
	});

	it('accepts an already-parsed object', () => {
		expect(parseSourceEditPayload(sample)).toEqual(sample);
	});

	it('refuses junk', () => {
		expect(parseSourceEditPayload(null)).toBeNull();
		expect(parseSourceEditPayload('not-json')).toBeNull();
		expect(parseSourceEditPayload({ route: '/x' })).toBeNull();
		expect(parseSourceEditPayload({ ...sample, canSave: 'yes' })).toBeNull();
	});

	it('recognises a postMessage envelope', () => {
		expect(isSourceEditMessage({ type: SOURCE_EDIT_MSG, ...sample })).toBe(true);
		expect(isSourceEditMessage({ type: 'other', ...sample })).toBe(false);
		expect(isSourceEditMessage(sample)).toBe(false);
	});
});
