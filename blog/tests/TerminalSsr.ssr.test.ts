// @vitest-environment node
//
// True server-side render of Terminal (svelte/server, no DOM). The component is
// deliberately declarative — no onMount, no timers, no rAF — because the typing is a
// pure CSS animation: the whole transcript comes from props alone, and the animation
// merely hides what is already in the markup.
//
// These tests are that contract: the text of every line ships, the schedule reaches the
// markup as plain ms, and no NaN ever does. It is what lets a `text` artifact serve the
// full session as static HTML. (A slide's markup never reaches the static build —
// SlideDeck gates its content behind `initialized` — so this is asserted here, against
// svelte/server, rather than against a built page.)
import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';
import Terminal from '../src/lib/components/Terminal.svelte';

const SESSION = [
	{ cmd: 'pnpm build' },
	{ out: 'vite v5.4.2 building...' },
	{ out: 'done', tone: 'ok' as const }
];

describe('Terminal (SSR)', () => {
	it('prerenders the full transcript — command text and output alike', () => {
		const { body } = render(Terminal, { props: { lines: SESSION } });
		expect(body).toContain('pnpm build');
		expect(body).toContain('vite v5.4.2 building...');
		expect(body).toContain('done');
	});

	it('a bare string is an output line; tones become classes', () => {
		const { body } = render(Terminal, { props: { lines: ['plain output', { out: 'x', tone: 'error' }] } });
		expect(body).toContain('plain output');
		expect(body).toContain('tone-plain');
		expect(body).toContain('tone-error');
	});

	it('carries the schedule as inline ms, and the step count for the typed span', () => {
		const { body } = render(Terminal, {
			props: { lines: [{ cmd: 'abc' }], charMs: 10, startMs: 100 }
		});
		expect(body).toContain('animation-delay:100ms');
		expect(body).toContain('--n:3');
		expect(body).toContain('steps(3, end)');
	});

	it('never emits NaN or undefined into the markup, however bad the input', () => {
		const { body } = render(Terminal, {
			// @ts-expect-error — the junk an author can type
			props: { lines: [{ cmd: 'x' }, null, 7, { out: 'y' }], charMs: 'fast', outMs: NaN }
		});
		expect(body).not.toContain('NaN');
		expect(body).not.toContain('undefined');
	});

	it('an empty command still gets steps(1) — steps(0) would drop the animation', () => {
		const { body } = render(Terminal, { props: { lines: [{ cmd: '' }] } });
		expect(body).toContain('steps(1, end)');
	});

	it('typing gates the anim class; without it the session is simply printed', () => {
		// Match the class TOKEN, not the substring: `animation-delay` contains "anim".
		// The scoped hash lands between the base and modifier classes, so `anim` is last.
		expect(render(Terminal, { props: { lines: SESSION } }).body).toContain('anim">');
		const still = render(Terminal, { props: { lines: SESSION, typing: false } }).body;
		expect(still).toContain('class="terminal ');
		expect(still).not.toContain('anim">');
		// ...and the text is still all there — that is the point of prerendering.
		expect(still).toContain('pnpm build');
	});

	it('the resting caret sits at the end of the envelope; per-command carets are gated on typing', () => {
		const { body } = render(Terminal, { props: { lines: [{ cmd: 'ab' }], charMs: 10, startMs: 100, pauseMs: 50 } });
		expect(body).toContain('rest-gate');
		expect(body).toContain('animation-delay:170ms'); // 100 start + 20 typing + 50 pause

		// typing off → no window carets to open, but the resting one stays.
		const still = render(Terminal, { props: { lines: [{ cmd: 'ab' }], typing: false } }).body;
		expect(still).toContain('rest-gate');
		expect(still.match(/class="[^"]*\bgate\b/g)?.length).toBe(1);
	});

	it('ships no transport: the clock is a browser thing, and a dead play button is a lie', () => {
		// `ready` is false until getAnimations() finds a clock, which only happens on mount.
		// A server-rendered play button would be a control that cannot control anything.
		const { body } = render(Terminal, { props: { lines: SESSION, keys: 'global' } });
		expect(body).not.toContain('transport');
		expect(body).not.toContain('overlay');
		expect(body).not.toContain('class="tick');
	});

	it('caret={false} drops every caret; chrome/title/prompt are opt-out too', () => {
		const bare = render(Terminal, {
			props: { lines: [{ cmd: 'ls' }], caret: false, chrome: false, prompt: '' }
		}).body;
		expect(bare).not.toContain('gate');
		expect(bare).not.toContain('class="bar"');
		expect(bare).not.toContain('prompt');

		const dressed = render(Terminal, { props: { lines: [], title: 'zsh — geekpresent' } }).body;
		expect(dressed).toContain('zsh — geekpresent');
	});
});
