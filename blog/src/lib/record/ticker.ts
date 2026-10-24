// A steady tick for the Recorder window, from a Worker.
//
// The Recorder usually sits BEHIND the slides window it is filming, and browsers throttle
// timers in a background page (to once a second, and worse after a while) — a replay
// clocked by setInterval there would fire its lines late and in clumps. A dedicated
// Worker's timers are not throttled that way, so it ticks and the page reacts to the
// message. Falls back to setInterval where a Worker cannot be made.

import { base } from '$app/paths';

/** Call `cb` every `ms` until the returned stop is called. */
export function startTicker(ms: number, cb: () => void): () => void {
	try {
		const src = `let h=setInterval(()=>postMessage(0),${Math.max(4, Math.round(ms))});onmessage=()=>{clearInterval(h);close()}`;
		const url = URL.createObjectURL(new Blob([src], { type: 'text/javascript' }));
		const worker = new Worker(url);
		URL.revokeObjectURL(url);
		worker.onmessage = () => cb();
		return () => {
			worker.postMessage('stop');
			worker.terminate();
		};
	} catch {
		const h = window.setInterval(cb, ms);
		return () => window.clearInterval(h);
	}
}

/** Open (or focus) the Recorder window for a deck. Call from a click. */
export function openRecorderWindow(deckKey: string): Window | null {
	if (typeof window === 'undefined') return null;
	const url = `${base}/_recorder?deck=${encodeURIComponent(deckKey)}`;
	return window.open(url, `gp-recorder:${deckKey}`, 'popup,width=560,height=820');
}
