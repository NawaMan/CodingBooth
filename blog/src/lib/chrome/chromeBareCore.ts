// Pure decision behind BARE chrome — both window-edge bars (the top tool bar and the
// bottom ControlBar) hidden COMPLETELY, no peek strip, so nothing but the slide shows.
//
// The ordinary tuck leaves a strip at each edge, one flick of the mouse from the bars.
// That is right while rehearsing and wrong on the audience's screen, where the strips are
// noise and a stray pointer pops a bar over the slide. Bare mode removes both, PIN
// included: "nothing visible" is the whole request. Alt+. still raises them for a few
// seconds, which is the way back that cannot be triggered by accident.
//
// Highest authority first:
//
//   1. The speaker's own sticky `?bare` / `?bare=off`. They asked, so they outrank the
//      deck AND the console — `?bare=off` is how to keep the bars while a console runs.
//   2. A presenter console is live: this window is the audience's, so it goes bare.
//   3. The deck's `hideChrome` prop: a deck that is always shown bare.
//   4. Off — the ordinary tuck.
//
// Total, like the access cores it mirrors: junk in, plain boolean out.

import { readSticky, type Choice } from '$lib/adjust/adjustAccessCore';

export { readSticky };
export type { Choice };

/** localStorage key holding the sticky `?bare` choice. */
export const BARE_KEY = 'chromeBare';

/** Interpret a slide URL's `?bare` flag.

    `?bare`, `?bare=on`, `?bare=1` enable; `?bare=off`, `?bare=false`, `?bare=0` disable.
    An absent flag is `null`, NOT `false` — the nav links carry no query, so the next slide
    must not undo what the speaker chose on this one. */
export function readBareParam(search: URLSearchParams | null | undefined): Choice {
	if (!search || !search.has('bare')) return null;
	const v = (search.get('bare') ?? '').trim().toLowerCase();
	return v !== 'off' && v !== 'false' && v !== '0';
}

/** Are both bars hidden completely here? See the precedence above. */
export function resolveChromeBare(sticky: Choice, consoleLive: boolean, deckWide: boolean): boolean {
	if (sticky === true || sticky === false) return sticky;
	return consoleLive === true || deckWide === true;
}
