// The arithmetic behind <Typewriter>: cutting a string into the units a reader
// perceives as "characters", and giving each one a window on the timeline.
//
// Kept pure and DOM-free (terminalCore / drawCore / connectorCore discipline) so the
// component is left with nothing but markup and CSS, and so the interesting cases — a
// negative speed, an emoji built from four code units, a string that is only spaces —
// are testable without a browser.
//
// Every function is total: bad input yields a harmless value (a default, an empty
// list), never a throw. A slide must not blow up because someone typed charMs="fast".
//
// The schedule is milliseconds, consumed as plain CSS animation-delay /
// animation-duration. That is the whole trick behind "the text rides the AnimationBar
// clock": a CSS @keyframes animation is also a Web Animations object, so the bar scrubs
// the typing without this module knowing it exists. Same bargain <Terminal> makes — but
// where Terminal clips a monospace span's width in whole `ch`, this schedules one
// animation PER CHARACTER, which is what lets it type a proportional headline, wrap
// like real text, and hold a caret between two letters.

/** The knobs on the typewriter. All in milliseconds. */
export interface TypewriterTiming {
	/** Per character. */
	charMs?: number;
	/** Dead air before the first character. */
	startMs?: number;
	/** Extra beat after a character that ends a clause — `,` `.` `?` `…` and friends. */
	punctuationMs?: number;
}

/** The defaults: an unhurried but not sleepy hand, matching <Terminal>'s. */
export const DEFAULT_TIMING: Required<TypewriterTiming> = {
	charMs: 55,
	startMs: 300,
	punctuationMs: 0
};

/**
 * Characters that earn an extra beat AFTER them when `punctuationMs` is set.
 *
 * Clause enders only. An apostrophe or a hyphen mid-word is not a pause anyone takes,
 * and stopping there reads as a stutter rather than as thought.
 */
const PUNCTUATION = new Set(['.', ',', '!', '?', ';', ':', '…', '—', '\n']);

/** One character, once it has a place on the timeline. */
export interface TypedChar {
	/** Position in the segmented string — the `{#each}` key. */
	index: number;
	/** The grapheme as authored: a letter, a space, a newline, a whole emoji. */
	text: string;
	/** When its window opens, in ms from the start of the animation. */
	delayMs: number;
	/** How long the window is. The character LANDS at the end of it. */
	durationMs: number;
}

/** A schedule: the placed characters plus the length of the whole envelope. */
export interface TypewriterSchedule {
	chars: TypedChar[];
	/** Total length in ms — where a resting caret belongs. */
	envelopeMs: number;
}

/**
 * A non-negative, finite duration, or the fallback. Zero is allowed and meaningful
 * (`charMs: 0` types instantly), which is why this is not a truthiness check.
 */
export function duration(value: unknown, fallback: number): number {
	return typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : fallback;
}

/**
 * Cut a string into what a READER counts as characters — grapheme clusters, not code
 * units and not even code points.
 *
 * This is the one place the naive `text.split('')` would be visibly wrong: it splits an
 * emoji into two lone surrogates (each rendered as a replacement box, and the first half
 * of a flag appearing a beat before the second), and it detaches a combining accent from
 * the letter it belongs to. `Intl.Segmenter` knows the real boundaries; `Array.from` —
 * which at least iterates code points — is the fallback where it is missing.
 *
 * Anything that is not a string segments to nothing, so a component handed `undefined`
 * renders an empty run rather than the word "undefined".
 */
export function segment(text: unknown): string[] {
	if (typeof text !== 'string' || text.length === 0) return [];

	const Segmenter = (Intl as { Segmenter?: new (l?: string, o?: object) => object }).Segmenter;
	if (typeof Segmenter === 'function') {
		try {
			const seg = new Segmenter(undefined, { granularity: 'grapheme' }) as {
				segment: (s: string) => Iterable<{ segment: string }>;
			};
			return Array.from(seg.segment(text), (piece) => piece.segment);
		} catch {
			// A locale/options rejection is not worth a blank slide — fall through.
		}
	}
	return Array.from(text);
}

/**
 * Lay the characters of `text` on one timeline.
 *
 * Each character owns a window of `charMs` and lands at the END of it (the CSS is
 * `steps(1, end)`), so character *n* is on screen at `startMs + (n + 1) * charMs` — a
 * hard cut per keystroke, never a fade. `punctuationMs` inserts a beat after a clause
 * ender, which is the difference between a machine emitting characters and a person
 * writing a sentence.
 *
 * The returned `envelopeMs` is where the text is complete — the moment a resting caret
 * should appear, and the end of this component's contribution to the slide's clock.
 */
export function scheduleChars(
	text: unknown,
	timing: TypewriterTiming = {}
): TypewriterSchedule {
	const charMs = duration(timing.charMs, DEFAULT_TIMING.charMs);
	const startMs = duration(timing.startMs, DEFAULT_TIMING.startMs);
	const punctuationMs = duration(timing.punctuationMs, DEFAULT_TIMING.punctuationMs);

	let clock = startMs;
	const chars = segment(text).map((piece, index) => {
		const char: TypedChar = { index, text: piece, delayMs: clock, durationMs: charMs };
		clock += charMs + (punctuationMs > 0 && PUNCTUATION.has(piece) ? punctuationMs : 0);
		return char;
	});

	return { chars, envelopeMs: clock };
}

/**
 * How much of `text` is on screen at `t` — the plain-text answer the CSS gives visually.
 *
 * Not used to drive the animation (the browser does that from the delays), but it is the
 * definition the tests hold the schedule to, and it is what any future stepping control
 * would ask. A character counts as typed once its window has CLOSED, matching
 * `steps(1, end)`.
 */
export function typedAt(schedule: TypewriterSchedule, t: number): string {
	if (!Number.isFinite(t)) return '';
	let out = '';
	for (const char of schedule.chars) {
		if (char.delayMs + char.durationMs > t) break;
		out += char.text;
	}
	return out;
}
