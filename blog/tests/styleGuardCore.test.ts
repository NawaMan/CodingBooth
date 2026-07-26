import { describe, expect, it } from 'vitest';
import { guardStyle } from '../src/lib/adjust/styleGuardCore';

describe('guardStyle — the props own the geometry', () => {
	it('strips a reserved property and reports it', () => {
		const g = guardStyle('left: 40px');
		expect(g.safe).toBe('');
		expect(g.reserved).toEqual(['left']);
	});

	it('keeps cosmetics while stripping geometry, in source order', () => {
		const g = guardStyle('stroke-dasharray: 4 2; left: 40px; color: red');
		expect(g.safe).toBe('stroke-dasharray: 4 2; color: red');
		expect(g.reserved).toEqual(['left']);
	});

	it('reserves every property a Block writes, plus the inset shorthands', () => {
		const g = guardStyle(
			'left: 1px; top: 2px; width: 3px; height: 4px; position: static; inset: 0; inset-inline-start: 5px'
		);
		expect(g.safe).toBe('');
		expect(g.reserved).toEqual([
			'left',
			'top',
			'width',
			'height',
			'position',
			'inset',
			'inset-inline-start',
		]);
	});

	it('reserves the SVG geometry properties that outrank a <rect>’s attributes', () => {
		const g = guardStyle('x: 10px; y: 20px; fill: none');
		expect(g.safe).toBe('fill: none');
		expect(g.reserved).toEqual(['x', 'y']);
	});

	it('de-duplicates a property declared twice', () => {
		expect(guardStyle('left: 1px; left: 2px').reserved).toEqual(['left']);
	});

	it('is case- and whitespace-insensitive about the property name', () => {
		const g = guardStyle('  LEFT :  40px  ');
		expect(g.safe).toBe('');
		expect(g.reserved).toEqual(['left']);
	});

	it('strips a reserved property carrying !important — it wins even harder', () => {
		expect(guardStyle('left: 40px !important').reserved).toEqual(['left']);
	});
});

describe('guardStyle — what it must NOT touch', () => {
	it('leaves a style with no geometry entirely alone', () => {
		const s = 'stroke: red; stroke-width: 3; stroke-dasharray: 4 2';
		const g = guardStyle(s);
		expect(g.safe).toBe(s);
		expect(g.reserved).toEqual([]);
		expect(g.offsets).toEqual([]);
	});

	it('keeps rotate/scale — decorative transforms are real authoring, not a collision', () => {
		const g = guardStyle('transform: rotate(3deg) scale(1.1)');
		expect(g.safe).toBe('transform: rotate(3deg) scale(1.1)');
		expect(g.reserved).toEqual([]);
		expect(g.offsets).toEqual([]);
	});

	it('keeps right/bottom — CSS already ignores them against left+width', () => {
		const g = guardStyle('right: 0; bottom: 0');
		expect(g.safe).toBe('right: 0; bottom: 0');
		expect(g.reserved).toEqual([]);
	});

	it('keeps margin — `margin: 0` is common and harmless on an absolute box', () => {
		expect(guardStyle('margin: 0').reserved).toEqual([]);
	});

	it('keeps rx — it is Rect’s corner rounding, not Ellipse’s radius, and must survive', () => {
		expect(guardStyle('rx: 8px').reserved).toEqual([]);
	});

	it('does not mistake a custom property named after a reserved one', () => {
		const g = guardStyle('--left: 40px; --width: 2px');
		expect(g.safe).toBe('--left: 40px; --width: 2px');
		expect(g.reserved).toEqual([]);
	});

	it('does not mistake a reserved word appearing in a VALUE', () => {
		const g = guardStyle('background-position: left top; text-align: left');
		expect(g.safe).toBe('background-position: left top; text-align: left');
		expect(g.reserved).toEqual([]);
	});

	it('ignores a valueless declaration rather than badging it', () => {
		const g = guardStyle('left: ; color: red');
		expect(g.safe).toBe('color: red');
		expect(g.reserved).toEqual([]);
	});
});

describe('guardStyle — displacement is reported, not confiscated', () => {
	it('flags a translate-bearing transform but keeps it', () => {
		const g = guardStyle('transform: translateX(40px)');
		expect(g.safe).toBe('transform: translateX(40px)');
		expect(g.reserved).toEqual([]);
		expect(g.offsets).toEqual(['transform']);
	});

	it('flags a translate mixed in with a rotate', () => {
		expect(guardStyle('transform: rotate(3deg) translate(10px, 2px)').offsets).toEqual(['transform']);
	});

	it('flags the standalone translate property', () => {
		expect(guardStyle('translate: 40px 0').offsets).toEqual(['translate']);
	});

	it('flags matrix(), which translates too', () => {
		expect(guardStyle('transform: matrix(1, 0, 0, 1, 40, 0)').offsets).toEqual(['transform']);
	});

	it('does not flag a transform/translate that shifts nothing', () => {
		expect(guardStyle('transform: none').offsets).toEqual([]);
		expect(guardStyle('translate: none').offsets).toEqual([]);
	});
});

describe('guardStyle — total on garbage', () => {
	it('survives null, undefined and empty', () => {
		for (const input of [null, undefined, '', '   ']) {
			const g = guardStyle(input as string);
			expect(g).toEqual({ safe: '', reserved: [], offsets: [] });
		}
	});

	it('does not split on a semicolon inside quotes or parens', () => {
		const g = guardStyle('background: url("a;b.png"); transform: translate(1px, 2px); left: 5px');
		expect(g.safe).toBe('background: url("a;b.png"); transform: translate(1px, 2px)');
		expect(g.reserved).toEqual(['left']);
		expect(g.offsets).toEqual(['transform']);
	});

	it('tolerates unbalanced parens and stray text without throwing or inventing', () => {
		const g = guardStyle('color: red; transform: translate(1px; left: 9px');
		// The unbalanced paren swallows the rest — nothing is invented, nothing throws.
		expect(g.reserved).toEqual([]);
		expect(g.safe).toContain('color: red');
	});

	it('keeps a colon-less fragment verbatim rather than silently eating it', () => {
		expect(guardStyle('garbage; color: red').safe).toBe('garbage; color: red');
	});

	it('tolerates trailing semicolons and blank declarations', () => {
		expect(guardStyle('color: red;;;').safe).toBe('color: red');
	});
});
