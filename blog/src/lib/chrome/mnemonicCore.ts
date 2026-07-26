// Pure helpers for chrome keyboard-mnemonic labels.
//
// When the mnemonic letter appears inside the visible word, mark it with an
// underline (PRESENT → P underlined). When it does not (FITTED + Z for zoom,
// ☰ + M for more), the caller keeps a trailing "(K)" chip instead.
//
// Total: empty letter or no match → null / plain escaped text, never throw.

export type MnemonicParts = { before: string; hit: string; after: string };

/**
 * Split `label` around the first case-insensitive match of `letter`.
 * Returns null when there is no letter, no label, or no hit.
 */
export function mnParts(label: string, letter: string): MnemonicParts | null {
	const L = String(letter ?? '').slice(0, 1);
	if (!L || !label) return null;
	const i = label.toLowerCase().indexOf(L.toLowerCase());
	if (i < 0) return null;
	return { before: label.slice(0, i), hit: label.slice(i, i + 1), after: label.slice(i + 1) };
}

/** Escape text for a trusted `{@html}` fragment (no tags from the label). */
export function escapeHtml(s: string): string {
	return String(s ?? '')
		.replace(/&/g, '&amp;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;')
		.replace(/"/g, '&quot;');
}

/**
 * Markup for a label with the mnemonic letter wrapped in `.chrome-mn`.
 *
 * Returned as one contiguous HTML string so Svelte cannot inject whitespace
 * between the letter and the rest of the word (which would turn "Table of
 * Contents" into the accessible name "T able of Contents").
 */
export function mnMarkup(label: string, letter: string): string {
	const p = mnParts(label, letter);
	if (!p) return escapeHtml(label);
	return `${escapeHtml(p.before)}<span class="chrome-mn">${escapeHtml(p.hit)}</span>${escapeHtml(p.after)}`;
}
