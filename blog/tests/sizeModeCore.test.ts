import { describe, expect, it } from 'vitest';
import {
	currentChoiceIndex,
	nearFactor,
	sizeMenuChoices,
	stepChoiceIndex
} from '../src/lib/chrome/sizeModeCore';

describe('sizeMenuChoices', () => {
	it('always starts with FITTED then scale presets', () => {
		const noRes = sizeMenuChoices(false);
		expect(noRes[0]).toEqual({ id: 'fitted', kind: 'fitted' });
		expect(noRes.some((c) => c.kind === 'factor' && c.factor === 1)).toBe(true);
		expect(noRes.some((c) => c.id.startsWith('r-'))).toBe(false);
	});

	it('appends resolution presets when asked', () => {
		const withRes = sizeMenuChoices(true);
		expect(withRes.some((c) => c.id === 'r-720p')).toBe(true);
		expect(withRes.length).toBeGreaterThan(sizeMenuChoices(false).length);
	});
});

describe('currentChoiceIndex', () => {
	const choices = sizeMenuChoices(true);

	it('points at FITTED when fitted', () => {
		expect(currentChoiceIndex(choices, true, 1)).toBe(0);
	});

	it('points at the matching scale factor when scaled', () => {
		const i = currentChoiceIndex(choices, false, 1);
		const c = choices[i];
		expect(c?.kind).toBe('factor');
		if (c?.kind === 'factor') expect(nearFactor(c.factor, 1)).toBe(true);
	});

	it('falls back to 0 when the factor is unknown', () => {
		expect(currentChoiceIndex(choices, false, 3.14159)).toBe(0);
	});
});

describe('stepChoiceIndex', () => {
	it('wraps at both ends', () => {
		expect(stepChoiceIndex(0, -1, 5)).toBe(4);
		expect(stepChoiceIndex(4, 1, 5)).toBe(0);
		expect(stepChoiceIndex(2, 1, 5)).toBe(3);
	});

	it('is total on empty / garbage', () => {
		expect(stepChoiceIndex(0, 1, 0)).toBe(0);
		expect(stepChoiceIndex(NaN, 1, 3)).toBe(1);
	});
});
