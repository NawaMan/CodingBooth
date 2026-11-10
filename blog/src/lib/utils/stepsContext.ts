// The contract between <Steps> and the members of its build.
//
// A member is anything that takes steps in a Steps run: a <Fragment> takes one, a
// <StepTerminal> one per command. Each registers during init, in document order, and
// reads `revealed` — how many steps of the whole build have been taken — to decide
// what it shows. Steps owns the keyboard, the chrome and the count; a member only
// says how many steps it needs and, while one of them is still playing, that it is
// busy (what <StepDots> waits for before cueing the next Space).
//
// Outside a <Steps>, getStepsContext() is undefined and a member renders as if every
// step were taken (a Fragment shows; a StepTerminal is a plain Terminal).

import { getContext, setContext } from 'svelte';
import type { Readable } from 'svelte/store';

export type StepsContext = {
	/** Claim `n` consecutive steps (default 1) and get the index of the first. `n = 0`
	    claims none and returns where the next one would be — the step this member
	    rides along with. */
	register: (n?: number) => number;
	/** How many steps of the build have been taken. */
	revealed: Readable<number>;
	/** The run's default Fragment transition. */
	defaults: Readable<{ transition: string; duration: number }>;
	/** Report that one of this member's steps is (or is no longer) still playing. `token`
	    is any object unique to the member; pass `false` on destroy. */
	setBusy: (token: object, busy: boolean) => void;
	/** The slide was reached by paging BACK, so the build opens spent: a member should
	    land on its last state, not play into it. */
	arrivedAtEnd: boolean;
};

const KEY = 'steps';

export function setStepsContext(ctx: StepsContext): void {
	setContext(KEY, ctx);
}

export function getStepsContext(): StepsContext | undefined {
	return getContext<StepsContext | undefined>(KEY);
}
