import { describe, expect, it } from 'vitest';
import {
	checkpointsOf,
	DEFAULT_TIMING,
	duration,
	markersOf,
	nextCheckpoint,
	normalizeLines,
	percentOf,
	prevCheckpoint,
	reachedCount,
	scheduleLines,
	snapTime,
	stepsFor
} from '../src/lib/utils/terminalCore';

describe('duration', () => {
	it('accepts any finite non-negative number, zero included', () => {
		expect(duration(0, 55)).toBe(0); // charMs: 0 means "type instantly", not "unset"
		expect(duration(12.5, 55)).toBe(12.5);
	});

	it('falls back on anything unusable', () => {
		for (const bad of [-1, NaN, Infinity, '30', null, undefined, {}]) {
			expect(duration(bad, 55)).toBe(55);
		}
	});
});

describe('stepsFor', () => {
	it('never returns 0 — steps(0) is invalid CSS and would drop the animation', () => {
		expect(stepsFor(0)).toBe(1);
		expect(stepsFor(1)).toBe(1);
		expect(stepsFor(NaN)).toBe(1);
		expect(stepsFor(-4)).toBe(1);
	});

	it('is the character count, floored, past one', () => {
		expect(stepsFor(12)).toBe(12);
		expect(stepsFor(12.7)).toBe(12);
	});
});

describe('normalizeLines', () => {
	it('reads a bare string as an output line', () => {
		expect(normalizeLines(['done'])).toEqual([{ kind: 'out', text: 'done', tone: 'plain' }]);
	});

	it('distinguishes commands from output and carries the tone', () => {
		expect(normalizeLines([{ cmd: 'ls' }, { out: 'boom', tone: 'error' }])).toEqual([
			{ kind: 'cmd', text: 'ls', tone: 'plain' },
			{ kind: 'out', text: 'boom', tone: 'error' }
		]);
	});

	it('a cmd wins over an out on the same entry (writing both is a typo)', () => {
		expect(normalizeLines([{ cmd: 'ls', out: 'ignored' }])).toEqual([
			{ kind: 'cmd', text: 'ls', tone: 'plain' }
		]);
	});

	it('drops entries that are neither, and unknown tones fall back to plain', () => {
		// @ts-expect-error — exactly the junk an author can type
		expect(normalizeLines([{}, null, undefined, 42, { tone: 'ok' }])).toEqual([]);
		// @ts-expect-error — 'purple' is not a Tone
		expect(normalizeLines([{ out: 'x', tone: 'purple' }])).toEqual([
			{ kind: 'out', text: 'x', tone: 'plain' }
		]);
	});

	it('keeps an empty command — a bare prompt is a legitimate beat', () => {
		expect(normalizeLines([{ cmd: '' }])).toEqual([{ kind: 'cmd', text: '', tone: 'plain' }]);
	});

	it('is total: nullish input is an empty session', () => {
		expect(normalizeLines(null)).toEqual([]);
		expect(normalizeLines(undefined)).toEqual([]);
	});
});

describe('scheduleLines', () => {
	const timing = { charMs: 10, startMs: 100, pauseMs: 50, outMs: 20 };

	it('types a command for charMs per character, starting after startMs', () => {
		const { lines } = scheduleLines([{ cmd: 'abc' }], timing);
		expect(lines[0]).toMatchObject({ chars: 3, delayMs: 100, durationMs: 30 });
	});

	it('pauses after a command, then cascades output one outMs at a time', () => {
		const { lines, envelopeMs } = scheduleLines(
			[{ cmd: 'ab' }, { out: 'one' }, { out: 'two' }],
			timing
		);
		// command: 100 → 120, then a 50ms beat
		expect(lines[0]).toMatchObject({ delayMs: 100, durationMs: 20 });
		// output cascades: 170, then 190
		expect(lines[1]).toMatchObject({ delayMs: 170, durationMs: 20, chars: 0 });
		expect(lines[2]).toMatchObject({ delayMs: 190, durationMs: 20 });
		// the envelope ends when the last line has finished
		expect(envelopeMs).toBe(210);
	});

	it('an empty session still has a finite envelope (where the resting caret goes)', () => {
		expect(scheduleLines([], timing).envelopeMs).toBe(100);
		expect(scheduleLines(null).envelopeMs).toBe(DEFAULT_TIMING.startMs);
	});

	it('an empty command costs no time but keeps its beat', () => {
		const { lines, envelopeMs } = scheduleLines([{ cmd: '' }], timing);
		expect(lines[0]).toMatchObject({ chars: 0, durationMs: 0 });
		expect(envelopeMs).toBe(150); // start + pause
	});

	it('is total: junk timing falls back to the defaults, never NaN', () => {
		// @ts-expect-error — a string speed is exactly what an author will write
		const { lines, envelopeMs } = scheduleLines([{ cmd: 'ab' }], { charMs: 'fast', startMs: -5 });
		expect(lines[0].durationMs).toBe(2 * DEFAULT_TIMING.charMs);
		expect(lines[0].delayMs).toBe(DEFAULT_TIMING.startMs);
		expect(Number.isFinite(envelopeMs)).toBe(true);
	});

	it('every emitted number is finite, whatever the input', () => {
		const { lines, envelopeMs } = scheduleLines(
			// @ts-expect-error — deliberately malformed
			[{ cmd: 'x' }, null, { out: 'y' }, 7, 'z'],
			{ charMs: NaN, outMs: Infinity }
		);
		for (const l of lines) {
			for (const n of [l.chars, l.delayMs, l.durationMs]) expect(Number.isFinite(n)).toBe(true);
		}
		expect(Number.isFinite(envelopeMs)).toBe(true);
	});
});

// The stepping arithmetic. A command is a marker: it `start`s typing and `end`s once its
// output has landed — and that end is the checkpoint Space plays to.
//
// Reference session (charMs 10, startMs 100, pauseMs 50, outMs 20):
//   t=100  cmd 'ab'  (20ms typing) → 120, +50 beat → 170
//   t=170  out 'one' (20ms)        → 190
//   t=190  cmd 'cd'  (20ms typing) → 210, +50 beat → 260
//   t=260  out 'two' (20ms)        → 280 = envelope
// So markers are [ {start:100, end:190}, {start:190, end:280} ].
const TIMING = { charMs: 10, startMs: 100, pauseMs: 50, outMs: 20 };
const SESSION = [{ cmd: 'ab' }, { out: 'one' }, { cmd: 'cd' }, { out: 'two' }];
const marks = markersOf(scheduleLines(SESSION, TIMING));

describe('markersOf', () => {
	it('makes a marker per command, spanning up to the next one', () => {
		expect(marks).toEqual([
			{ index: 0, label: 'ab', start: 100, end: 190 },
			{ index: 1, label: 'cd', start: 190, end: 280 }
		]);
	});

	it('the last command runs to the end of the session, output included', () => {
		expect(marks.at(-1)!.end).toBe(scheduleLines(SESSION, TIMING).envelopeMs);
	});

	it('a session of pure output has no markers — nothing to step to', () => {
		expect(markersOf(scheduleLines(['just output'], TIMING))).toEqual([]);
	});
});

describe('nextCheckpoint', () => {
	it('walks command by command, then reports spent', () => {
		expect(nextCheckpoint(marks, 0)).toBe(190); // from the top → end of the 1st command
		expect(nextCheckpoint(marks, 190)).toBe(280); // standing on one → the next
		expect(nextCheckpoint(marks, 280)).toBeNull(); // spent → Space pages the deck
	});

	it('does not step onto the checkpoint it is already standing on', () => {
		// The playhead is sampled from a real clock, so it lands a hair past its target.
		expect(nextCheckpoint(marks, 190.4)).toBe(280);
	});

	it('is total: no markers, or a NaN playhead, is simply spent', () => {
		expect(nextCheckpoint([], 0)).toBeNull();
		expect(nextCheckpoint(marks, NaN)).toBeNull();
	});
});

describe('prevCheckpoint', () => {
	it('steps back through the same stops Space stepped forward through', () => {
		expect(prevCheckpoint(marks, 280)).toBe(190);
		// From the FIRST checkpoint, back to the beginning — NOT the first command's start
		// (a state no forward step produces) and emphatically not off the slide.
		expect(prevCheckpoint(marks, 190)).toBe(0);
	});

	it('back and forward walk one identical set of stops', () => {
		const stops: number[] = [];
		for (let t = 0; ; ) {
			const next = nextCheckpoint(marks, t);
			if (next === null) break;
			stops.push((t = next));
		}
		const back: number[] = [];
		for (let t = stops.at(-1)!; ; ) {
			const prev = prevCheckpoint(marks, t);
			if (prev === null) break;
			back.push((t = prev));
		}
		// Forward: 190, 280. Backward from 280: 190, 0. Same states, reversed.
		expect(stops).toEqual([190, 280]);
		expect(back).toEqual([190, 0]);
	});

	it('a scrubbed playhead rewinds to the last stop behind it', () => {
		expect(prevCheckpoint(marks, 100)).toBe(0); // mid-first-command
		expect(prevCheckpoint(marks, 250)).toBe(190); // mid-second-command
	});

	it('null only at the very top, so Shift+Space pages back from a rewound console', () => {
		expect(prevCheckpoint(marks, 0)).toBeNull();
		// ...and the sampling slack cannot strand it a hair past zero.
		expect(prevCheckpoint(marks, 0.4)).toBeNull();
	});

	it('is total: no markers still offers the beginning; a NaN playhead does not', () => {
		expect(prevCheckpoint([], 500)).toBe(0);
		expect(prevCheckpoint([], 0)).toBeNull();
		expect(prevCheckpoint(marks, NaN)).toBeNull();
	});
});

describe('checkpointsOf', () => {
	it('is exactly the ladder Space walks — the ticks are drawn at these', () => {
		expect(checkpointsOf(marks)).toEqual([190, 280]);

		// The invariant the ticks depend on: stepping forward from 0 visits precisely these.
		const walked: number[] = [];
		for (let t = 0; ; ) {
			const next = nextCheckpoint(marks, t);
			if (next === null) break;
			walked.push((t = next));
		}
		expect(walked).toEqual(checkpointsOf(marks));
	});

	it('is NOT the commands\' starts — that mismatch made Space look like it skipped a tick', () => {
		expect(checkpointsOf(marks)).not.toEqual(marks.map((m) => m.start));
	});

	it('no commands, no stops', () => {
		expect(checkpointsOf([])).toEqual([]);
	});
});

describe('reachedCount', () => {
	it('counts the stops behind the playhead, so the ticks light as they are passed', () => {
		expect(reachedCount(marks, 0)).toBe(0);
		expect(reachedCount(marks, 189)).toBe(0);
		expect(reachedCount(marks, 190)).toBe(1); // parked ON the first stop → it is reached
		expect(reachedCount(marks, 190.4)).toBe(1); // clock overshoot must not skip ahead
		expect(reachedCount(marks, 279)).toBe(1);
		expect(reachedCount(marks, 280)).toBe(2);
		expect(reachedCount(marks, 9999)).toBe(2);
	});

	it('is total', () => {
		expect(reachedCount(marks, NaN)).toBe(0);
		expect(reachedCount([], 500)).toBe(0);
	});
});

describe('percentOf', () => {
	it('clamps, and never divides by a zero or NaN envelope', () => {
		expect(percentOf(140, 280)).toBe(50);
		expect(percentOf(-5, 280)).toBe(0);
		expect(percentOf(999, 280)).toBe(100);
		expect(percentOf(10, 0)).toBe(0);
		expect(percentOf(10, NaN)).toBe(0);
		expect(percentOf(NaN, 280)).toBe(0);
	});
});

describe('snapTime', () => {
	// The checkpoints — the times the ticks are drawn at: 190 and 280.
	const cps = checkpointsOf(marks);

	it('a seek near a tick lands exactly on that stop', () => {
		expect(snapTime(196, cps, 10)).toBe(190);
		expect(snapTime(184, cps, 10)).toBe(190);
		expect(snapTime(276, cps, 10)).toBe(280);
	});

	it('a seek away from every tick is left where the pointer put it', () => {
		expect(snapTime(150, cps, 10)).toBe(150);
		expect(snapTime(179, cps, 10)).toBe(179); // just outside the tolerance
	});

	it('the tolerance is exclusive, so a tick exactly one tolerance away does not pull', () => {
		expect(snapTime(180, cps, 10)).toBe(180);
	});

	it('picks the nearest tick when two are in range, earlier on a tie', () => {
		expect(snapTime(118, [100, 120], 50)).toBe(120);
		expect(snapTime(110, [100, 120], 50)).toBe(100); // tie → the earlier stop
	});

	it('is total: no ticks, junk tolerance, or a NaN time all pass through', () => {
		expect(snapTime(137, [], 10)).toBe(137);
		expect(snapTime(137, cps, 0)).toBe(137);
		expect(snapTime(137, cps, NaN)).toBe(137);
		expect(snapTime(NaN, cps, 10)).toBeNaN();
	});
});
