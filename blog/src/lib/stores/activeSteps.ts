import { writable } from 'svelte/store';

// The build currently driving this slide, published for the chrome.
//
// A "build" is anything Space walks through before the deck pages on: a <Steps> run
// of Fragments, or a <Video keys="global"> whose steps are its bookmarks. Both
// register here and both are arbitrated by the same `spaceIntent`, so the chrome
// need not know which kind it is holding — only whether a step remains.
//
// Steps sits inside the slide's content while NavigationBar is rendered by the
// page template (ContentPage/TitlePage) — they are SIBLINGS, so Svelte context
// can't reach from one to the other. This module-level store is the bridge, the
// same trick selectedBlock uses for the ADJUST-mode selection.
//
// A Steps with keyboard stepping on (keys='global') registers itself here and
// keeps `hasNext` in sync as the build advances; NavigationBar reads it to enable
// the CONTINUE button and to make clicking it do exactly what Space does. `null`
// = no build on this slide, so CONTINUE falls back to the slide's own onContinue
// hook (and stays disabled when there is none).
//
// One build at a time: `owner` identifies the registering instance so a build
// only clears the store on destroy if it is still the one holding it. (Which is
// also why a Video's Space-stepping is opt-in: two builds on one slide would fight
// over the store, and over Space.)
export type ActiveSteps = {
	/** Identity of the registering instance. */
	owner: object;
	/** Is there another step forward (a Fragment to reveal, a chapter to seek to)? */
	hasNext: boolean;
	/** Is there a step back (a Fragment to peel, an earlier chapter)? */
	hasPrev: boolean;
	/** Take the next step — the same action as pressing Space. */
	next: () => void;
};

export const activeSteps = writable<ActiveSteps | null>(null);
