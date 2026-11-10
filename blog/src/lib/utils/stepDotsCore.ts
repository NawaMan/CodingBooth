// Pure maths for <StepDots> — the "this slide is a build, and here is how far in"
// indicator. No DOM, no stores: the component hands in the build's `index` / `total`
// (from the activeSteps store) and draws whatever comes back.

/** One dot: a step already taken, the step just taken, or one still to come. */
export type StepDotState = 'done' | 'current' | 'todo';

/** Above this many steps the dots turn into one segmented bar — a Terminal with
    thirty commands should not grow a string of beads across the slide. */
export const STEP_DOTS_MAX = 12;

export type StepDotsView =
	/** Nothing to draw: no build, or one that doesn't say how long it is. */
	| { kind: 'none' }
	| {
			kind: 'dots';
			dots: StepDotState[];
			index: number;
			total: number;
			/** Every step taken — the next Space pages the deck. */
			spent: boolean;
	  }
	| {
			kind: 'bar';
			/** 0..1, how much of the bar is filled. */
			fraction: number;
			index: number;
			total: number;
			spent: boolean;
	  };

/**
 * What to draw for a build at `index` of `total` steps. Total — junk in (NaN, a
 * negative, a fraction, an index past the end) still yields a usable view, since
 * the numbers come from three different components.
 */
export function stepDotsView(
	index: number | undefined,
	total: number | undefined,
	max: number = STEP_DOTS_MAX
): StepDotsView {
	if (typeof total !== 'number' || !Number.isFinite(total)) return { kind: 'none' };
	const n = Math.floor(total);
	if (n < 1) return { kind: 'none' };

	const raw = typeof index === 'number' && Number.isFinite(index) ? Math.floor(index) : 0;
	const at = Math.max(0, Math.min(n, raw));
	const spent = at >= n;

	if (n > max) return { kind: 'bar', fraction: at / n, index: at, total: n, spent };

	const dots: StepDotState[] = [];
	for (let i = 0; i < n; i++) dots.push(i < at - 1 ? 'done' : i === at - 1 ? 'current' : 'todo');
	return { kind: 'dots', dots, index: at, total: n, spent };
}

/** The "your turn" cue: the slide is waiting for Space. */
export type StepCue =
	/** No cue: no build, a step still playing, not settled yet, or nowhere to go. */
	| 'none'
	/** A step remains — blink the next dot, "SPACE for next step". */
	| 'next'
	/** Every step taken — "SPACE for next slide". */
	| 'spent';

/** How long the build must sit still before the cue shows, so it does not flash while
    the speaker talks over the output they just revealed. */
export const STEP_CUE_DELAY_MS = 1000;

/** The cue's default wording. Overridable per deck (SlideDeck `stepCueNext` / `stepCueSpent`). */
export const STEP_CUE_NEXT = 'SPACE for next step';
export const STEP_CUE_SPENT = 'SPACE for next slide';

/**
 * Which cue to show. `busy` is the build's own report (a step still playing); `settled`
 * is whether it has sat still for the cue delay since the last change — the component
 * owns that timer, this only decides. A spent build cues only when there IS a next
 * slide to page to; on the deck's last one Space goes nowhere, so nothing is promised.
 */
export function stepCue(
	view: StepDotsView,
	state: { busy?: boolean; settled: boolean; hasNextSlide: boolean }
): StepCue {
	if (view.kind === 'none' || state.busy || !state.settled) return 'none';
	if (view.spent) return state.hasNextSlide ? 'spent' : 'none';
	return 'next';
}

/** The accessible name: "Step 2 of 5". */
export function stepDotsLabel(view: StepDotsView): string {
	return view.kind === 'none' ? '' : `Step ${view.index} of ${view.total}`;
}

/** Where the indicator sits on the canvas: an edge's midpoint or a corner. */
export type StepDotsPosition =
	| 'top'
	| 'bottom'
	| 'left'
	| 'right'
	| 'top-left'
	| 'top-right'
	| 'bottom-left'
	| 'bottom-right';

export const STEP_DOTS_POSITIONS: readonly StepDotsPosition[] = [
	'top',
	'bottom',
	'left',
	'right',
	'top-left',
	'top-right',
	'bottom-left',
	'bottom-right'
];

/** One axis of the anchor: hugging the near edge, centred, or hugging the far edge. */
export type StepDotsAlign = 'start' | 'center' | 'end';

export type StepDotsPlacement = {
	position: StepDotsPosition;
	x: StepDotsAlign;
	y: StepDotsAlign;
	/** On the left or right EDGE the row stands up, so it runs along that edge. */
	vertical: boolean;
};

/**
 * Where to anchor the row for `position`. Unknown values (a typo in pages.ts) fall
 * back to 'bottom' rather than hiding the indicator.
 */
export function stepDotsPlacement(position: unknown): StepDotsPlacement {
	const p: StepDotsPosition = STEP_DOTS_POSITIONS.includes(position as StepDotsPosition)
		? (position as StepDotsPosition)
		: 'bottom';
	const x: StepDotsAlign = p.includes('left') ? 'start' : p.includes('right') ? 'end' : 'center';
	const y: StepDotsAlign = p.startsWith('top') ? 'start' : p.startsWith('bottom') ? 'end' : 'center';
	return { position: p, x, y, vertical: p === 'left' || p === 'right' };
}

/**
 * The canvas-space anchor as CSS, `inset` in from the chosen edges (a CSS length,
 * normally the --stepdots-inset token). Left/top only — far-edge anchoring misprints —
 * and the translate pulls the row back so a corner row stays inside the canvas.
 */
export function stepDotsAnchorStyle(
	placement: StepDotsPlacement,
	canvasWidth: number,
	canvasHeight: number,
	inset: string = 'var(--stepdots-inset, 36px)'
): string {
	const at = (a: StepDotsAlign, size: number) =>
		a === 'start' ? inset : a === 'end' ? `calc(${size}px - ${inset})` : `${size / 2}px`;
	const shift = (a: StepDotsAlign) => (a === 'start' ? '0' : a === 'end' ? '-100%' : '-50%');
	return (
		`left: ${at(placement.x, canvasWidth)}; top: ${at(placement.y, canvasHeight)}; ` +
		`transform: translate(${shift(placement.x)}, ${shift(placement.y)});`
	);
}
