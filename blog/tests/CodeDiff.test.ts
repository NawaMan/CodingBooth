import { render } from '@testing-library/svelte';
import { tick } from 'svelte';
import { describe, expect, it, vi } from 'vitest';
import CodeDiff from '../src/lib/components/CodeDiff.svelte';

// The runtime half of CodeDiff (the static structure is in CodeDiffSsr.ssr.test.ts,
// the diff arithmetic in codeDiffCore.test.ts). What only a mounted component shows
// is the Shiki colour SWAP: it renders plain text first, then on mount replaces each
// line's text with token spans — the QuickCode contract. Shiki is mocked so the swap
// is deterministic (and so jsdom needs no real highlighter): highlightToLines returns
// one red token per line carrying the line's own text back, which lets us prove both
// that the swap happened AND that each line's colours landed on the right line.
vi.mock('$lib/utils/highlight', () => ({
	highlightToLines: (code: string) =>
		Promise.resolve(code.split('\n').map((line) => [{ content: line, color: '#ff0000' }]))
}));

const rows = (root: ParentNode) => Array.from(root.querySelectorAll('.row')) as HTMLElement[];

describe('CodeDiff (runtime)', () => {
	it('renders plain text first, then swaps in Shiki colour spans on mount', async () => {
		const { container } = render(CodeDiff, {
			props: { before: 'a\nOLD\nc', after: 'a\nNEW\nc' }
		});
		// Before the mount promise resolves, the code cells hold plain text and no
		// coloured spans.
		expect(container.querySelector('.code span[style*="color"]')).toBeNull();

		await tick();
		await Promise.resolve(); // let the highlight promise settle
		await tick();

		const coloured = container.querySelectorAll('.code span[style*="color"]');
		expect(coloured.length).toBeGreaterThan(0);
		// The 2nd row is the deletion (OLD); its coloured span carries OLD's text, not
		// a neighbour's — the per-line zip is aligned.
		const r = rows(container);
		expect(r[1].className).toContain('del');
		expect(r[1].querySelector('.code')?.textContent).toBe('OLD');
	});

	it('keeps the diff structure the core computed: context / del / add in order', async () => {
		const { container } = render(CodeDiff, {
			props: { before: 'a\nOLD\nc', after: 'a\nNEW\nc' }
		});
		await tick();
		const r = rows(container);
		expect(r.map((el) => el.className.match(/\b(add|del|context)\b/)?.[0])).toEqual([
			'context',
			'del',
			'add',
			'context'
		]);
	});
});
