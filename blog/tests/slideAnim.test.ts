import { describe, expect, it } from 'vitest';
import {
	applyState,
	endTimeOf,
	envelope,
	isPlaying,
	pauseGroup,
	playGroup,
	sampleFraction
} from '../src/lib/utils/slideAnim';

// The shared machinery for driving a slide's staggered CSS animations — used by
// AnimationBar, the presenter console (PresenterAnim / applyState) and Terminal.
//
// The case that matters, and the one that had no test: the animations on a slide do NOT
// share an end. `drawDelay` staggers a Draw/Connector reveal; each line of a Terminal
// session types on its own schedule. So at any playhead in the middle, some animations
// are finished and some are not — and per the Web Animations spec, `play()` on a finished
// animation REWINDS it to 0 and runs it again. A bare `for (const a of anims) a.play()`
// therefore redraws everything already drawn.

/** The observable surface of an Animation, with the spec's auto-rewind on play(). */
class FakeAnimation {
	currentTime = 0;
	playState: 'idle' | 'running' | 'paused' = 'idle';
	effect: { getComputedTiming: () => { endTime: number } };
	constructor(readonly endTime: number) {
		this.effect = { getComputedTiming: () => ({ endTime }) };
	}
	play() {
		if (this.currentTime >= this.endTime) this.currentTime = 0; // spec: auto-rewind
		this.playState = 'running';
	}
	pause() { this.playState = 'paused'; }
}

/** A staggered reveal: three shapes drawing one after another, as `drawDelay` produces. */
const stagger = () => [new FakeAnimation(100), new FakeAnimation(200), new FakeAnimation(300)];
const as = (anims: FakeAnimation[]) => anims as unknown as Animation[];

/** Park the group at time `t`, each animation clamped to its own end (what seek does). */
function seekTo(anims: FakeAnimation[], t: number) {
	for (const a of anims) a.currentTime = Math.min(t, a.endTime);
}

describe('playGroup', () => {
	it('leaves a finished animation exactly where it is — it must not rewind and replay', () => {
		const anims = stagger();
		seekTo(anims, 150); // shape 1 finished at 100; shapes 2 and 3 still going

		playGroup(as(anims));

		expect(anims[0].currentTime).toBe(100); // held at its final frame, not rewound to 0
		expect(anims[0].playState).toBe('idle'); // never attached to the clock again
		expect(anims[1].currentTime).toBe(150);
		expect(anims[1].playState).toBe('running');
		expect(anims[2].playState).toBe('running');
	});

	it('plays everything from a fresh start', () => {
		const anims = stagger();
		playGroup(as(anims));
		expect(anims.every((a) => a.playState === 'running')).toBe(true);
		expect(anims.every((a) => a.currentTime === 0)).toBe(true);
	});

	it('a group seeked back to 0 replays in full — nothing is finished any more', () => {
		const anims = stagger();
		seekTo(anims, 400); // everything finished
		seekTo(anims, 0); // ...then rewound, as a caller does before replaying
		playGroup(as(anims));
		expect(anims.every((a) => a.playState === 'running')).toBe(true);
	});

	it('a fully finished group left at its end plays nothing (the caller must seek first)', () => {
		const anims = stagger();
		seekTo(anims, 400);
		playGroup(as(anims));
		expect(anims.every((a) => a.playState === 'idle')).toBe(true);
		expect(anims.map((a) => a.currentTime)).toEqual([100, 200, 300]); // all held, none rewound
	});

	it('is total: an empty group is a no-op', () => {
		expect(() => playGroup([])).not.toThrow();
	});
});

describe('pauseGroup', () => {
	it('detaches every animation, finished ones included', () => {
		const anims = stagger();
		seekTo(anims, 150);
		pauseGroup(as(anims));
		expect(anims.every((a) => a.playState === 'paused')).toBe(true);
	});
});

describe('applyState', () => {
	it('relays a mid-timeline play without redrawing the finished shapes', () => {
		// The presenter presses Play half-way through a staggered reveal; the audience window
		// receives {playing, fraction} and must land in the same visual state, not restart.
		const anims = stagger();
		applyState(as(anims), { playing: true, fraction: 0.5 }); // 0.5 * 300 = 150ms

		expect(anims[0].currentTime).toBe(100); // finished shape stays finished
		expect(anims[0].playState).toBe('idle');
		expect(anims[1].currentTime).toBe(150);
		expect(anims[1].playState).toBe('running');
	});

	it('a paused relay parks the whole group at the fraction', () => {
		const anims = stagger();
		applyState(as(anims), { playing: false, fraction: 1 });
		expect(anims.map((a) => a.currentTime)).toEqual([100, 200, 300]);
		expect(anims.every((a) => a.playState === 'paused')).toBe(true);
	});

	it('clamps a fraction outside 0..1', () => {
		const anims = stagger();
		applyState(as(anims), { playing: false, fraction: 5 });
		expect(anims.map((a) => a.currentTime)).toEqual([100, 200, 300]);
		applyState(as(anims), { playing: false, fraction: -2 });
		expect(anims.map((a) => a.currentTime)).toEqual([0, 0, 0]);
	});
});

describe('the group readouts', () => {
	it('endTimeOf ignores an infinite or missing end (a looping animation is not seekable)', () => {
		expect(endTimeOf(new FakeAnimation(250) as unknown as Animation)).toBe(250);
		expect(endTimeOf(new FakeAnimation(Infinity) as unknown as Animation)).toBe(0);
	});

	it('envelope is the longest end; sampleFraction the furthest-advanced playhead', () => {
		const anims = stagger();
		expect(envelope(as(anims))).toBe(300);
		seekTo(anims, 150);
		// Each animation is capped at its own end, so the short finished one cannot peg it.
		expect(sampleFraction(as(anims))).toBeCloseTo(0.5);
		expect(sampleFraction([])).toBe(0);
	});

	it('isPlaying is true while any animation is attached to the clock', () => {
		const anims = stagger();
		expect(isPlaying(as(anims))).toBe(false);
		playGroup(as(anims));
		expect(isPlaying(as(anims))).toBe(true);
	});
});
