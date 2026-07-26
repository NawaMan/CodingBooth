import { persisted } from '$lib/stores/persisted';
import { barPosCodec, type BarPos } from '$lib/annotate/annotateCore';

// Where the last (non-dismissed) <Hint> was dragged to — a canvas-px {x,y} translate
// from its resting spot, or null for "hasn't been moved". SHARED across every <Hint> on
// every slide, deliberately: a Hint is authored fresh per slide (each slide is its own
// prerendered document — see AGENTS.md), so there is no single component instance to
// remember a position FOR. What carries over instead is the viewer's last CHOICE, so
// paging to the next slide's Hint (a brand-new instance, same idea) still shows up
// already out of the way, instead of blocking the same spot the viewer just moved the
// last one off of.
//
// Reset the moment a Hint is DISMISSED (its ×): dismissal is a "done with this cue"
// signal, so the next one — this slide reloaded, or a later slide's — starts fresh at
// its resting spot rather than inheriting a position chosen for text that is now gone.
// See Hint.svelte's `close()`.
//
// `sync: false`: like the ANNOTATE bar, this is one viewer's own arrangement of their
// own window, not a property of the deck.
//
// Reuses annotateCore's BarPos shape/codec on purpose — a canvas-px {x,y} or null is
// exactly the same contract the pen's bar already validates and persists; no reason to
// grow a second copy of the same three lines of JSON parsing for a second widget.
export const hintOffset = persisted<BarPos>('hintOffset', null, {
	codec: barPosCodec(),
	sync: false
});
