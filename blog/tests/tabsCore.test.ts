// Unit tests for tabsCore — the pure index arithmetic behind <Tabs> / <Tab>.
// No DOM: every function is total, so the bad inputs (empty list, NaN start, a
// strip of all-disabled tabs) are as much the subject as the happy path.
import { describe, expect, it } from 'vitest';
import {
	alignClass,
	clampIndex,
	firstEnabled,
	initialIndex,
	lastEnabled,
	stepEnabled
} from '../src/lib/utils/tabsCore';
import type { TabMeta } from '../src/lib/utils/tabsCore';

const tab = (label: string, disabled = false): TabMeta => ({ label, disabled });

describe('clampIndex', () => {
	it('clamps into [0, n-1]', () => {
		expect(clampIndex(-3, 4)).toBe(0);
		expect(clampIndex(2, 4)).toBe(2);
		expect(clampIndex(9, 4)).toBe(3);
	});
	it('floors a fractional index', () => {
		expect(clampIndex(1.9, 4)).toBe(1);
	});
	it('non-finite input, or an empty list, → 0', () => {
		expect(clampIndex(NaN, 4)).toBe(0);
		expect(clampIndex(Infinity, 4)).toBe(0); // non-finite is treated as 0, not the top
		expect(clampIndex(2, 0)).toBe(0); // an empty list is always 0
		expect(clampIndex(2, -1)).toBe(0);
	});
});

describe('firstEnabled / lastEnabled', () => {
	const tabs = [tab('a', true), tab('b'), tab('c'), tab('d', true)];
	it('finds the first / last enabled index', () => {
		expect(firstEnabled(tabs)).toBe(1);
		expect(lastEnabled(tabs)).toBe(2);
	});
	it('all disabled (or empty) → 0', () => {
		expect(firstEnabled([tab('x', true), tab('y', true)])).toBe(0);
		expect(lastEnabled([tab('x', true), tab('y', true)])).toBe(0);
		expect(firstEnabled([])).toBe(0);
		expect(lastEnabled([])).toBe(0);
	});
});

describe('initialIndex', () => {
	const tabs = [tab('a'), tab('b', true), tab('c')];
	it('clamps start into range', () => {
		expect(initialIndex(tabs, 0)).toBe(0);
		expect(initialIndex(tabs, 2)).toBe(2);
		expect(initialIndex(tabs, 9)).toBe(2);
	});
	it('nudges off a disabled start to the first enabled tab', () => {
		expect(initialIndex(tabs, 1)).toBe(0); // start=1 is disabled → first enabled (0)
	});
	it('a NaN start settles on the first enabled tab', () => {
		expect(initialIndex([tab('a', true), tab('b')], NaN)).toBe(1);
	});
});

describe('stepEnabled', () => {
	const tabs = [tab('a'), tab('b', true), tab('c'), tab('d')];
	it('skips disabled tabs going forward', () => {
		expect(stepEnabled(tabs, 0, +1)).toBe(2); // 1 is disabled → 2
		expect(stepEnabled(tabs, 2, +1)).toBe(3);
	});
	it('skips disabled tabs going back', () => {
		expect(stepEnabled(tabs, 2, -1)).toBe(0); // 1 is disabled → 0
	});
	it('wraps past the ends (onto enabled tabs)', () => {
		expect(stepEnabled(tabs, 3, +1)).toBe(0); // last → first
		expect(stepEnabled(tabs, 0, -1)).toBe(3); // first → last
	});
	it('a single enabled tab (rest disabled) stays put rather than looping', () => {
		const one = [tab('a', true), tab('b'), tab('c', true)];
		expect(stepEnabled(one, 1, +1)).toBe(1);
		expect(stepEnabled(one, 1, -1)).toBe(1);
	});
	it('an empty list is 0', () => {
		expect(stepEnabled([], 0, +1)).toBe(0);
	});
});

describe('alignClass', () => {
	it('passes the known alignments through', () => {
		expect(alignClass('start')).toBe('start');
		expect(alignClass('center')).toBe('center');
		expect(alignClass('end')).toBe('end');
		expect(alignClass('stretch')).toBe('stretch');
	});
	it('an unknown value falls back to start', () => {
		expect(alignClass('sideways')).toBe('start');
		expect(alignClass('')).toBe('start');
	});
});
