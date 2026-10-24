import { get } from 'svelte/store';
import { persisted } from './persisted';
import { booleanCodec } from '$lib/utils/stateCore';

// Has this viewer found their way around a deck? (See onboard/onboardCore.ts.)
//
// One flag per ORIGIN, not per deck: → and Space are the same on every deck here, so a
// viewer who learned them once does not need telling again. `sync: true` so a second tab
// agrees the moment the first one explores. booleanCodec, so a corrupt key fails closed
// to "new" — the worst that does is show the hint once more.

/** True once the viewer has left the first slide, opened a bar, pressed a paging key or
    dismissed the hint. The first-visit hint never shows again after that. */
export const onboardDone = persisted<boolean>('geekpresent:onboard:done', false, {
	codec: booleanCodec(),
	sync: true
});

/** Record that the viewer knows the way. Idempotent — cheap to call on every bar hover. */
export function markOnboarded(): void {
	if (!get(onboardDone)) onboardDone.set(true);
}
