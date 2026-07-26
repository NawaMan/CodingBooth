import { describe, expect, it } from 'vitest';
import { escapeHtml, mnMarkup, mnParts } from '../src/lib/chrome/mnemonicCore';

describe('mnParts', () => {
	it('underlines the first case-insensitive hit', () => {
		expect(mnParts('PRESENT', 'P')).toEqual({ before: '', hit: 'P', after: 'RESENT' });
		expect(mnParts('PRESENT', 'p')).toEqual({ before: '', hit: 'P', after: 'RESENT' });
		expect(mnParts('ADJUST', 'J')).toEqual({ before: 'AD', hit: 'J', after: 'UST' });
		expect(mnParts('Table of Contents', 'T')).toEqual({
			before: '',
			hit: 'T',
			after: 'able of Contents'
		});
		// First match wins (ANNOTATE has two A's).
		expect(mnParts('ANNOTATE', 'A')).toEqual({ before: '', hit: 'A', after: 'NNOTATE' });
	});

	it('returns null when the letter is not in the label', () => {
		// Zoom / More chips stay as trailing "(Z)" / "(M)" — no in-word hit.
		expect(mnParts('FITTED', 'Z')).toBeNull();
		expect(mnParts('100%', 'Z')).toBeNull();
		expect(mnParts('☰', 'M')).toBeNull();
	});

	it('is total on garbage', () => {
		expect(mnParts('', 'P')).toBeNull();
		expect(mnParts('PRESENT', '')).toBeNull();
		expect(mnParts('PRESENT', 'PR')).toEqual({ before: '', hit: 'P', after: 'RESENT' });
	});
});

describe('mnMarkup', () => {
	it('emits one contiguous fragment so a11y does not see a space after the letter', () => {
		expect(mnMarkup('Table of Contents', 'T')).toBe(
			'<span class="chrome-mn">T</span>able of Contents'
		);
		expect(mnMarkup('ADJUST', 'J')).toBe('AD<span class="chrome-mn">J</span>UST');
	});

	it('escapes untrusted label text', () => {
		expect(escapeHtml('a<b>&"c')).toBe('a&lt;b&gt;&amp;&quot;c');
		expect(mnMarkup('A<B>', 'A')).toBe('<span class="chrome-mn">A</span>&lt;B&gt;');
	});
});
