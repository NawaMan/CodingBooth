import { describe, expect, it } from 'vitest';
import {
	aggregateMediaFraction,
	defaultMutedForAutoplay,
	effectiveMediaLoop,
	isLoopWrap,
	mediaHoldFraction,
	mediaHoldRemainingMs,
	normalizeAutoplay,
	shouldDriveChapterSteps,
	shouldHoldForKiosk,
	wantsAutoplay,
	wantsPlay
} from '../src/lib/utils/videoKioskCore';

describe('normalizeAutoplay / wantsAutoplay / wantsPlay', () => {
	it('normalizes loose truthy values and kiosk', () => {
		expect(normalizeAutoplay(true)).toBe(true);
		expect(normalizeAutoplay('kiosk')).toBe('kiosk');
		expect(normalizeAutoplay(false)).toBe(false);
		expect(normalizeAutoplay('nope')).toBe(false);
		expect(normalizeAutoplay(null)).toBe(false);
	});

	it('true always wants play; kiosk only when the session is active', () => {
		expect(wantsAutoplay(true, false)).toBe(true);
		expect(wantsAutoplay(true, true)).toBe(true);
		expect(wantsAutoplay('kiosk', false)).toBe(false);
		expect(wantsAutoplay('kiosk', true)).toBe(true);
		expect(wantsAutoplay(false, true)).toBe(false);
	});

	it('kioskHold drives play during kiosk even without autoplay (watch the tape)', () => {
		expect(
			wantsPlay({ autoplay: false, kioskActive: true, kioskHold: true, cycleDone: false })
		).toBe(true);
		expect(
			wantsPlay({ autoplay: false, kioskActive: true, kioskHold: true, cycleDone: true })
		).toBe(false);
		expect(
			wantsPlay({ autoplay: false, kioskActive: true, kioskHold: false, cycleDone: false })
		).toBe(false);
		expect(
			wantsPlay({ autoplay: false, kioskActive: false, kioskHold: true, cycleDone: false })
		).toBe(false);
	});

	it('default muted covers autoplay modes that can fire without a gesture', () => {
		expect(defaultMutedForAutoplay(true)).toBe(true);
		expect(defaultMutedForAutoplay('kiosk')).toBe(true);
		expect(defaultMutedForAutoplay(false)).toBe(false);
	});

	it('chapter steps are off while kiosk runs (no bookmark seeks on the step clock)', () => {
		expect(
			shouldDriveChapterSteps({ keysGlobal: true, hasMarks: true, kioskActive: false })
		).toBe(true);
		expect(
			shouldDriveChapterSteps({ keysGlobal: true, hasMarks: true, kioskActive: true })
		).toBe(false);
		expect(
			shouldDriveChapterSteps({ keysGlobal: true, hasMarks: false, kioskActive: false })
		).toBe(false);
	});
});

describe('shouldHoldForKiosk', () => {
	const base = {
		kioskHold: true,
		kioskActive: true,
		cycleDone: false,
		wantPlay: false,
		paused: true,
		currentTime: 0,
		duration: 30
	};

	it('does not hold when kiosk is off, hold is off, or the cycle is done', () => {
		expect(shouldHoldForKiosk({ ...base, kioskActive: false, wantPlay: true })).toBe(false);
		expect(shouldHoldForKiosk({ ...base, kioskHold: false, paused: false })).toBe(false);
		expect(shouldHoldForKiosk({ ...base, cycleDone: true, paused: false })).toBe(false);
	});

	it('holds while playing, paused mid-clip, or about to autoplay from the start', () => {
		expect(shouldHoldForKiosk({ ...base, paused: false })).toBe(true);
		expect(shouldHoldForKiosk({ ...base, currentTime: 5 })).toBe(true);
		expect(shouldHoldForKiosk({ ...base, wantPlay: true })).toBe(true);
	});

	it('does not freeze the booth on an unstarted non-autoplay poster', () => {
		expect(shouldHoldForKiosk({ ...base, wantPlay: false, paused: true, currentTime: 0 })).toBe(
			false
		);
	});

	it('releases once the playhead is at the end', () => {
		expect(
			shouldHoldForKiosk({ ...base, paused: false, currentTime: 30, duration: 30 })
		).toBe(false);
	});
});

describe('media hold maths', () => {
	it('fraction and remaining are total for junk duration', () => {
		expect(mediaHoldFraction(5, NaN)).toBe(0);
		expect(mediaHoldRemainingMs(5, NaN)).toBe(0);
		expect(mediaHoldFraction(15, 30)).toBe(0.5);
		expect(mediaHoldRemainingMs(10, 30)).toBe(20_000);
		expect(mediaHoldFraction(40, 30)).toBe(1);
	});

	it('aggregate uses the least-finished holder', () => {
		expect(aggregateMediaFraction([])).toBe(0);
		expect(aggregateMediaFraction([0.8, 0.2, 0.5])).toBe(0.2);
		expect(aggregateMediaFraction([1, 1])).toBe(1);
	});
});

describe('loop during kiosk hold', () => {
	it('strips loop while a hold cycle is in progress so ended can fire', () => {
		expect(
			effectiveMediaLoop({
				loop: true,
				kioskActive: true,
				kioskHold: true,
				cycleDone: false
			})
		).toBe(false);
		expect(
			effectiveMediaLoop({
				loop: true,
				kioskActive: true,
				kioskHold: true,
				cycleDone: true
			})
		).toBe(true);
		expect(
			effectiveMediaLoop({
				loop: true,
				kioskActive: false,
				kioskHold: true,
				cycleDone: false
			})
		).toBe(true);
		expect(
			effectiveMediaLoop({
				loop: false,
				kioskActive: true,
				kioskHold: true,
				cycleDone: false
			})
		).toBe(false);
	});

	it('detects a loop wrap when ended was suppressed', () => {
		expect(isLoopWrap(28, 0.1, 30)).toBe(true);
		expect(isLoopWrap(5, 6, 30)).toBe(false); // forward play
		expect(isLoopWrap(0.2, 0, 30)).toBe(false); // never started
		expect(isLoopWrap(3, 0.1, 30)).toBe(false); // early seek, not near end
	});
});
