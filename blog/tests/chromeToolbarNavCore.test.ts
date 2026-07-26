import { describe, expect, it } from 'vitest';
import {
	arrowDir,
	focusIndexOf,
	nextNavIndex,
	stepWrap,
	toolbarNavZone
} from '../src/lib/chrome/chromeToolbarNavCore';

describe('arrowDir', () => {
	it('maps the four arrows and ignores the rest', () => {
		expect(arrowDir({ key: 'ArrowLeft' })).toBe('left');
		expect(arrowDir({ key: 'ArrowRight' })).toBe('right');
		expect(arrowDir({ key: 'ArrowUp' })).toBe('up');
		expect(arrowDir({ key: 'ArrowDown' })).toBe('down');
		expect(arrowDir({ key: 'a' })).toBe('');
		expect(arrowDir({})).toBe('');
	});
});

describe('stepWrap', () => {
	it('wraps at both ends', () => {
		expect(stepWrap(0, -1, 4)).toBe(3);
		expect(stepWrap(3, 1, 4)).toBe(0);
	});
});

describe('focusIndexOf', () => {
	it('finds by reference or containment', () => {
		const a = document.createElement('button');
		const b = document.createElement('button');
		const span = document.createElement('span');
		a.appendChild(span);
		expect(focusIndexOf([a, b], a)).toBe(0);
		expect(focusIndexOf([a, b], span)).toBe(0);
		expect(focusIndexOf([a, b], document.createElement('button'))).toBe(-1);
	});
});

describe('toolbarNavZone', () => {
	const base = {
		armed: false,
		moreOpen: false,
		printOpen: false,
		sizeMenuOpen: false,
		focusInPrint: false,
		focusInMoreDrop: false,
		focusOnHamburger: false,
		focusOnBar: false
	};

	it('yields to the SizeMode zoom menu', () => {
		expect(toolbarNavZone({ ...base, armed: true, sizeMenuOpen: true })).toBe('none');
	});

	it('prefers print when that flyout is open', () => {
		expect(
			toolbarNavZone({ ...base, moreOpen: true, printOpen: true, focusInPrint: true })
		).toBe('print');
	});

	it('uses more when the drop is open', () => {
		expect(toolbarNavZone({ ...base, moreOpen: true, focusInMoreDrop: true })).toBe('more');
		expect(toolbarNavZone({ ...base, moreOpen: true })).toBe('more');
	});

	it('uses bar when chrome is armed', () => {
		expect(toolbarNavZone({ ...base, armed: true })).toBe('bar');
		expect(toolbarNavZone({ ...base, armed: false })).toBe('none');
	});
});

describe('nextNavIndex', () => {
	it('bar: left/right only', () => {
		expect(nextNavIndex('bar', 'right', 0, 5)).toBe(1);
		expect(nextNavIndex('bar', 'left', 0, 5)).toBe(4);
		expect(nextNavIndex('bar', 'down', 0, 5)).toBeNull();
	});

	it('more: down from hamburger (-1) to first; up from first back to -1', () => {
		expect(nextNavIndex('more', 'down', -1, 3)).toBe(0);
		expect(nextNavIndex('more', 'up', 0, 3)).toBe(-1);
		expect(nextNavIndex('more', 'down', 0, 3)).toBe(1);
	});

	it('print: left signals leave (-1); up/down wrap', () => {
		expect(nextNavIndex('print', 'left', 2, 6)).toBe(-1);
		expect(nextNavIndex('print', 'down', 5, 6)).toBe(0);
	});
});
