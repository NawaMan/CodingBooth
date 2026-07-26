// The arithmetic behind <Video>, tested without a media element — jsdom does not
// really have one. Every function here is total: the interesting cases are the bad
// ones (a typo'd bookmark, a duration that is still NaN, a click off the track),
// because a slide must not blow up over any of them.
import { describe, expect, it } from 'vitest';
import {
	activeBookmarkIndex,
	formatTime,
	normalizeBookmarks,
	parseTime,
	progressPercent,
	seekFraction
} from '../src/lib/utils/videoCore';

describe('parseTime', () => {
	it('reads colon groups right-to-left: s, m:s, h:m:s', () => {
		expect(parseTime('90')).toBe(90);
		expect(parseTime('1:14')).toBe(74);
		expect(parseTime('0:03')).toBe(3);
		expect(parseTime('1:02:03')).toBe(3723);
		expect(parseTime('0:01.5')).toBe(1.5);
	});

	it('passes a plain number through, rejecting the impossible ones', () => {
		expect(parseTime(74)).toBe(74);
		expect(parseTime(0)).toBe(0);
		expect(parseTime(-1)).toBeNaN(); // a negative bookmark means nothing
		expect(parseTime(Infinity)).toBeNaN();
		expect(parseTime(NaN)).toBeNaN();
	});

	it('is NaN for anything it cannot read, rather than a wrong number', () => {
		for (const bad of ['', '  ', ':', '1:', 'abc', '1:xx', '-5', '1:2:3:4', null, undefined, {}]) {
			expect(parseTime(bad as never)).toBeNaN();
		}
	});

	it('is lenient about out-of-range groups — a typo still lands somewhere sane', () => {
		expect(parseTime('0:75')).toBe(75);
	});
});

describe('formatTime', () => {
	it('shows m:ss, and grows an hour field only when there is one', () => {
		expect(formatTime(0)).toBe('0:00');
		expect(formatTime(3)).toBe('0:03');
		expect(formatTime(74)).toBe('1:14');
		expect(formatTime(74.9)).toBe('1:14'); // floors, never rounds up past the frame
		expect(formatTime(600)).toBe('10:00');
		expect(formatTime(3723)).toBe('1:02:03'); // minutes pad only once hours appear
	});

	it("an unloaded video's NaN duration reads as 0:00, not 'NaN:aN'", () => {
		expect(formatTime(NaN)).toBe('0:00');
		expect(formatTime(Infinity)).toBe('0:00'); // a live stream
		expect(formatTime(-5)).toBe('0:00');
	});
});

describe('normalizeBookmarks', () => {
	it('resolves times, and sorts — so chapters can be written in any order', () => {
		const marks = normalizeBookmarks([
			{ at: '1:14', label: 'last' },
			{ at: 0, label: 'first' },
			{ at: '0:10', label: 'middle' }
		]);
		expect(marks.map((m) => m.time)).toEqual([0, 10, 74]);
		expect(marks.map((m) => m.label)).toEqual(['first', 'middle', 'last']);
	});

	it('drops an unparseable time instead of seeking the video to nowhere', () => {
		const marks = normalizeBookmarks([{ at: 'oops' }, { at: 5 }, { at: -3 }]);
		expect(marks).toHaveLength(1);
		expect(marks[0].time).toBe(5);
	});

	it('keeps the tag, defaults the label, and survives an empty or absent list', () => {
		expect(normalizeBookmarks([{ at: 1, tag: 'HOST' }])[0]).toEqual({
			time: 1,
			label: '',
			tag: 'HOST'
		});
		expect(normalizeBookmarks([])).toEqual([]);
		expect(normalizeBookmarks(undefined)).toEqual([]);
	});

	it('keeps two bookmarks that share a time, in the order written', () => {
		const marks = normalizeBookmarks([
			{ at: 5, label: 'a' },
			{ at: 5, label: 'b' }
		]);
		expect(marks.map((m) => m.label)).toEqual(['a', 'b']); // Array.sort is stable
	});
});

describe('activeBookmarkIndex', () => {
	const marks = normalizeBookmarks([{ at: 3 }, { at: 10 }, { at: 27 }]);

	it('is the last chapter the playhead has passed', () => {
		expect(activeBookmarkIndex(marks, 3)).toBe(0); // exactly on the mark: it counts
		expect(activeBookmarkIndex(marks, 9.9)).toBe(0);
		expect(activeBookmarkIndex(marks, 10)).toBe(1);
		expect(activeBookmarkIndex(marks, 1000)).toBe(2); // past the last, it stays lit
	});

	it('is -1 before the first mark, and while the time is unknown', () => {
		expect(activeBookmarkIndex(marks, 0)).toBe(-1); // a video may open on unlabelled footage
		expect(activeBookmarkIndex(marks, NaN)).toBe(-1);
		expect(activeBookmarkIndex([], 5)).toBe(-1);
	});
});

describe('seekFraction', () => {
	const rect = { left: 100, width: 200 };

	it('maps a click along the track to 0..1', () => {
		expect(seekFraction(100, rect)).toBe(0);
		expect(seekFraction(200, rect)).toBe(0.5);
		expect(seekFraction(300, rect)).toBe(1);
	});

	it('clamps a drag that leaves the track, and cannot divide by a zero width', () => {
		expect(seekFraction(0, rect)).toBe(0);
		expect(seekFraction(9999, rect)).toBe(1);
		expect(seekFraction(150, { left: 100, width: 0 })).toBe(0); // never laid out
		expect(seekFraction(NaN, rect)).toBe(0);
	});
});

describe('progressPercent', () => {
	it('is the fraction played, as a percentage', () => {
		expect(progressPercent(12, 24)).toBe(50);
		expect(progressPercent(0, 24)).toBe(0);
		expect(progressPercent(24, 24)).toBe(100);
	});

	it('is 0 while the duration is unknown — never an Infinity CSS would drop', () => {
		expect(progressPercent(5, NaN)).toBe(0); // metadata not in yet
		expect(progressPercent(5, 0)).toBe(0);
		expect(progressPercent(5, Infinity)).toBe(0); // a live stream
		expect(progressPercent(NaN, 24)).toBe(0);
	});

	it('clamps, because currentTime can briefly exceed a rounded duration', () => {
		expect(progressPercent(25, 24)).toBe(100);
		expect(progressPercent(-1, 24)).toBe(0);
	});
});
