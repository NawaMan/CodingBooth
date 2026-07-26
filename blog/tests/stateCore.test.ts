import { describe, expect, it } from 'vitest';
import {
	MAX_TEXT,
	booleanCodec,
	clamp,
	jsonCodec,
	numberCodec,
	parseNumber,
	parseText,
	readNumberParam,
	readTextParam,
	textCodec,
	writeNumber
} from '../src/lib/utils/stateCore';

const search = (query: string) => new URLSearchParams(query);

describe('clamp', () => {
	it('leaves a value inside the bounds alone', () => {
		expect(clamp(5, { min: 0, max: 10 })).toBe(5);
	});

	it('clamps to each end', () => {
		expect(clamp(-3, { min: 0, max: 10 })).toBe(0);
		expect(clamp(99, { min: 0, max: 10 })).toBe(10);
	});

	it('treats an absent end as no bound at all', () => {
		expect(clamp(1e6, { min: 0 })).toBe(1e6);
		expect(clamp(-1e6, { max: 10 })).toBe(-1e6);
		expect(clamp(42)).toBe(42);
	});

	it('ignores junk bounds rather than inventing a value', () => {
		expect(clamp(5, { min: NaN, max: NaN })).toBe(5);
	});

	it('lets max win when the bounds contradict each other', () => {
		// A min above its max is a caller bug; answering with the max is at least
		// inside one of the two stated ranges.
		expect(clamp(5, { min: 10, max: 0 })).toBe(0);
	});
});

describe('parseNumber — total, never NaN', () => {
	it('reads a plain number', () => {
		expect(parseNumber('42', 0)).toBe(42);
		expect(parseNumber('  7  ', 0)).toBe(7);
		expect(parseNumber('-3.5', 0)).toBe(-3.5);
	});

	it('keeps a stored zero rather than falling back', () => {
		// The bug this guards: `Number(raw) || fallback` turns a real 0 into the default.
		expect(parseNumber('0', 9)).toBe(0);
	});

	it('falls back for everything that is not a number', () => {
		expect(parseNumber(null, 9)).toBe(9);
		expect(parseNumber(undefined, 9)).toBe(9);
		expect(parseNumber('', 9)).toBe(9);
		expect(parseNumber('   ', 9)).toBe(9);
		expect(parseNumber('abc', 9)).toBe(9);
		expect(parseNumber('NaN', 9)).toBe(9);
		expect(parseNumber('Infinity', 9)).toBe(9);
	});

	it('refuses trailing garbage that parseInt would silently accept', () => {
		// `parseInt('12px')` is 12 — a corrupted key read as a plausible value.
		expect(parseNumber('12px', 9)).toBe(9);
		expect(parseNumber('1e999', 9)).toBe(9); // parseFloat → Infinity
	});

	it('clamps what it does accept', () => {
		expect(parseNumber('500', 0, { min: 0, max: 99 })).toBe(99);
		expect(parseNumber('-500', 0, { min: 0, max: 99 })).toBe(0);
	});
});

describe('writeNumber', () => {
	it('round-trips a finite value', () => {
		expect(parseNumber(writeNumber(12), 0)).toBe(12);
	});

	it('never writes a string its own reader would refuse', () => {
		// NaN/Infinity would serialize to "NaN"/"Infinity" and poison the key for the
		// next reader, so they are turned into the fallback on the way OUT.
		expect(writeNumber(NaN)).toBe('0');
		expect(writeNumber(Infinity)).toBe('0');
		expect(writeNumber(NaN, 5)).toBe('5');
	});
});

describe('parseText', () => {
	it('reads and trims ordinary text', () => {
		expect(parseText('  Ada ')).toBe('Ada');
	});

	it('falls back on absent or empty', () => {
		expect(parseText(null, 'world')).toBe('world');
		expect(parseText('', 'world')).toBe('world');
		expect(parseText('   ', 'world')).toBe('world');
	});

	it('strips control characters a crafted URL can carry', () => {
		expect(parseText('Ada\u007F')).toBe('Ada');
		expect(parseText('one\ntwo')).toBe('onetwo');
		expect(parseText('tab\there')).toBe('tabhere');
	});

	it('falls back when the input is nothing BUT control characters', () => {
		expect(parseText('\u0007\u0001', 'world')).toBe('world');
	});

	it('caps a hostile length', () => {
		expect(parseText('x'.repeat(5000))).toHaveLength(MAX_TEXT);
	});

	it('leaves markup inert rather than mangling it — Svelte escapes on render', () => {
		// Not an XSS guard, and it does not pretend to be: the characters survive, and
		// the framework is what makes them harmless.
		expect(parseText('<script>')).toBe('<script>');
	});
});

describe('readNumberParam / readTextParam', () => {
	it('reads from a query string', () => {
		expect(readNumberParam(search('count=7'), 'count', 0)).toBe(7);
		expect(readTextParam(search('name=Ada'), 'name', '')).toBe('Ada');
	});

	it('falls back on an absent param', () => {
		expect(readNumberParam(search('other=1'), 'count', 3)).toBe(3);
		expect(readTextParam(search(''), 'name', 'world')).toBe('world');
	});

	it('falls back on a missing URLSearchParams — the SSR shape', () => {
		expect(readNumberParam(null, 'count', 3)).toBe(3);
		expect(readTextParam(undefined, 'name', 'world')).toBe('world');
	});

	it('clamps and cleans what it reads', () => {
		expect(readNumberParam(search('count=999'), 'count', 0, { min: 0, max: 99 })).toBe(99);
		expect(readTextParam(search('name=a%07bc'), 'name', '')).toBe('abc');
	});
});

describe('codecs — null means "not mine", not "falsy"', () => {
	it('numberCodec round-trips, including zero', () => {
		const c = numberCodec({ min: 0, max: 99 });
		expect(c.read(c.write(0))).toBe(0);
		expect(c.read(c.write(42))).toBe(42);
	});

	it('numberCodec reports garbage as null, never NaN', () => {
		const c = numberCodec();
		expect(c.read('abc')).toBeNull();
		expect(c.read('')).toBeNull();
		expect(c.read('NaN')).toBeNull();
	});

	it('numberCodec clamps a hand-edited key back into range', () => {
		expect(numberCodec({ min: 0, max: 99 }).read('4000')).toBe(99);
	});

	it('textCodec treats the empty string as a real value', () => {
		expect(textCodec().read('')).toBe('');
	});

	it('jsonCodec round-trips a structure', () => {
		const c = jsonCodec<{ a: number[] }>();
		expect(c.read(c.write({ a: [1, 2] }))).toEqual({ a: [1, 2] });
	});

	it('jsonCodec reports a throw as null instead of exploding at module init', () => {
		expect(jsonCodec().read('{ not json')).toBeNull();
		expect(jsonCodec().read('null')).toBeNull();
	});
});

describe('booleanCodec — a flag fails closed', () => {
	it('round-trips both booleans', () => {
		expect(booleanCodec().write(true)).toBe('true');
		expect(booleanCodec().write(false)).toBe('false');
		expect(booleanCodec().read('true')).toBe(true);
		expect(booleanCodec().read('false')).toBe(false);
	});

	it('keeps a stored FALSE rather than reporting it as "nothing stored"', () => {
		// The `null` vs falsy distinction, in the case where it bites: `false` is a real
		// value a user chose, not an absent key.
		expect(booleanCodec().read('false')).not.toBeNull();
	});

	it('tolerates surrounding whitespace', () => {
		expect(booleanCodec().read('  true  ')).toBe(true);
	});

	it('refuses a JSON object, which jsonCodec would hand back as TRUTHY', () => {
		// The reason this codec exists rather than jsonCodec<boolean>(). A corrupt key must
		// not arm a flag: `Boolean({})` is `true`, and that would switch on authoring chrome.
		expect(jsonCodec().read('{"not":"a boolean"}')).toEqual({ not: 'a boolean' }); // the trap
		expect(booleanCodec().read('{"not":"a boolean"}')).toBeNull(); // the fix
	});

	it('refuses everything that is not exactly true or false', () => {
		for (const raw of ['1', '0', 'yes', 'TRUE', 'True', '', 'null', 'undefined', '[]']) {
			expect(booleanCodec().read(raw)).toBeNull();
		}
	});
});
