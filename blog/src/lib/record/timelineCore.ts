// timelineCore — the pure half of the VOD recorder (see specs/VOD-RECORD-1.md).
//
// A recording is a video plus a TIMELINE: a plain text file, one deck action per line,
// stamped with the video clock. The speaker edits it by hand — nudges a time, deletes a
// slip, inserts a `shift +2` to hold a slide longer — and REPLAY drives the deck through
// it again. So the text is the interface, and this file is everything about it that can
// be decided without a browser: the grammar (format + parse, round-tripping), the paths
// the lines name, the ink diff the Recorder turns a changed ink book into, the partial
// stroke a replay draws mid-gesture, and the video settings (container, bitrate, size).
//
// Total in the house tradition: junk in yields a defined answer, never a throw — except
// that a timeline line which does not parse is REPORTED with its line number rather
// than skipped, because a silently dropped `goto` desynchronises everything after it.

import type { Point } from '$lib/draw/types';
import { sanitizeStrokes, type InkBook, type Stroke } from '$lib/annotate/annotateCore';

// --- Actions ----------------------------------------------------------------------------

/** One thing the deck did. The slides window reports these while recording (without a
    time — the Recorder's clock stamps them); a timeline line is one of these plus `t`. */
export type TimelineAction =
	/** The deck paged. `href` is relative to the deck (`intro.html`, `a.html?return=b.html`)
	    or an absolute path for a slide outside it. `back` = the backward transition;
	    `end` = land with the build spent (what PREV does). */
	| { kind: 'goto'; href: string; back?: boolean; end?: boolean }
	/** A build (Steps / Terminal / Video chapters) moved one step; `back` = peeled. */
	| { kind: 'step'; back?: boolean }
	/** The slide's own onContinue hook ran (a CONTINUE with no build to drive). */
	| { kind: 'continue' }
	/** The slide's animations were set to this state (AnimationBar or the console). */
	| { kind: 'anim'; playing: boolean; fraction: number }
	/** A named trigger fired (stores/triggers). */
	| { kind: 'trigger'; name: string }
	/** The spotlight moved to this Block, or `null` = off. */
	| { kind: 'highlight'; name: string | null }
	/** A stroke appeared (or changed) on `slide`, drawn over `dur` seconds. */
	| { kind: 'ink'; op: 'draw'; slide: string; dur: number; stroke: Stroke }
	/** Strokes were removed from `slide`. */
	| { kind: 'ink'; op: 'erase'; slide: string; ids: string[] }
	/** All ink on `slide` was removed; `slide` = '*' for every slide of the deck. */
	| { kind: 'ink'; op: 'clear'; slide: string }
	/** The recording stopped here. */
	| { kind: 'end' };

export type TimelineEvent = TimelineAction & { t: number };

export interface Timeline {
	/** `# key: value` comments from the top of the file (deck, canvas, recorded, …). */
	header: Record<string, string>;
	events: TimelineEvent[];
}

export interface TimelineError {
	/** 1-based line number in the text. */
	line: number;
	message: string;
	text: string;
}

export const TIMELINE_MAGIC = 'GeekPresent timeline v1';

// --- Numbers and clock ------------------------------------------------------------------

function fin(n: unknown, fallback = 0): number {
	return typeof n === 'number' && Number.isFinite(n) ? n : fallback;
}

/** A number with at most `digits` decimals and no trailing zeros ("0.84", "2", "0.125"). */
export function compactNumber(n: number, digits = 3): string {
	const v = fin(n);
	const s = v.toFixed(digits);
	return s.includes('.') ? s.replace(/0+$/, '').replace(/\.$/, '') : s;
}

/** Seconds as `mm:ss.mmm` — or `h:mm:ss.mmm` from an hour on. Negative clamps to 0. */
export function formatClock(seconds: number): string {
	const totalMs = Math.max(0, Math.round(fin(seconds) * 1000));
	const ms = totalMs % 1000;
	const totalS = Math.floor(totalMs / 1000);
	const s = totalS % 60;
	const totalM = Math.floor(totalS / 60);
	const pad = (n: number, w: number) => String(n).padStart(w, '0');
	const tail = `${pad(s, 2)}.${pad(ms, 3)}`;
	if (totalM >= 60) return `${Math.floor(totalM / 60)}:${pad(totalM % 60, 2)}:${tail}`;
	return `${pad(totalM, 2)}:${tail}`;
}

/** Parse `h:mm:ss.mmm`, `m:ss.mmm`, `ss.mmm` or plain seconds. null when it is not one. */
export function parseClock(text: string): number | null {
	const t = (text ?? '').trim();
	if (!/^\d+(:\d{1,2}){0,2}(\.\d+)?$/.test(t)) return null;
	const parts = t.split(':');
	let total = 0;
	for (let i = 0; i < parts.length; i++) {
		const v = Number(parts[i]);
		if (!Number.isFinite(v)) return null;
		// Every field but the first is a base-60 digit pair, so it must stay below 60.
		if (i > 0 && v >= 60) return null;
		total = total * 60 + v;
	}
	return total;
}

// --- Words ------------------------------------------------------------------------------

/** A name as one token: bare when it is safe, else a JSON string ("my name", "off"). */
function word(name: string, reserved: string[] = []): string {
	if (/^[^\s"#{}]+$/.test(name) && !reserved.includes(name)) return name;
	return JSON.stringify(name);
}

interface Token {
	text: string;
	/** Was it a "quoted" token (always a name, never a keyword)? */
	quoted: boolean;
	/** Was it a {…} JSON object? */
	json: boolean;
}

/** Split a line into tokens: whitespace separated, "quoted strings" and {balanced JSON}
    kept whole, and a `#` outside both ending the line. Returns null on an unterminated
    quote or brace. */
export function tokenize(line: string): Token[] | null {
	const out: Token[] = [];
	let i = 0;
	const n = line.length;
	while (i < n) {
		const c = line[i];
		if (/\s/.test(c)) {
			i++;
			continue;
		}
		if (c === '#') break; // comment to end of line
		if (c === '"') {
			let j = i + 1;
			while (j < n && line[j] !== '"') j += line[j] === '\\' ? 2 : 1;
			if (j >= n) return null;
			try {
				out.push({ text: JSON.parse(line.slice(i, j + 1)), quoted: true, json: false });
			} catch {
				return null;
			}
			i = j + 1;
			continue;
		}
		if (c === '{') {
			let depth = 0;
			let j = i;
			let inStr = false;
			for (; j < n; j++) {
				const d = line[j];
				if (inStr) {
					if (d === '\\') j++;
					else if (d === '"') inStr = false;
				} else if (d === '"') inStr = true;
				else if (d === '{') depth++;
				else if (d === '}' && --depth === 0) break;
			}
			if (j >= n) return null;
			out.push({ text: line.slice(i, j + 1), quoted: false, json: true });
			i = j + 1;
			continue;
		}
		let j = i;
		while (j < n && !/\s/.test(line[j]) && line[j] !== '#') j++;
		out.push({ text: line.slice(i, j), quoted: false, json: false });
		i = j;
	}
	return out;
}

// --- One action <-> text ----------------------------------------------------------------

/** The text of an action, without its time. */
export function formatAction(a: TimelineAction): string {
	switch (a.kind) {
		case 'goto':
			return ['goto', word(a.href), a.back ? 'back' : '', a.end ? 'end' : ''].filter(Boolean).join(' ');
		case 'step':
			return a.back ? 'step back' : 'step';
		case 'continue':
			return 'continue';
		case 'anim':
			return `anim ${a.playing ? 'play' : 'pause'} ${clamp01(a.fraction).toFixed(3)}`;
		case 'trigger':
			return `trigger ${word(a.name)}`;
		case 'highlight':
			return a.name ? `highlight ${word(a.name, ['off'])}` : 'highlight off';
		case 'ink': {
			const slide = a.slide === '*' ? '*' : word(a.slide, ['*']);
			if (a.op === 'draw') {
				const { ms: _ms, ...stroke } = a.stroke;
				return `ink ${slide} draw ${compactNumber(a.dur)} ${JSON.stringify(stroke)}`;
			}
			if (a.op === 'erase') return `ink ${slide} erase ${a.ids.map((id) => word(id)).join(' ')}`;
			return `ink ${slide} clear`;
		}
		case 'end':
			return 'end';
	}
}

function clamp01(n: number): number {
	return Math.max(0, Math.min(1, fin(n)));
}

/** Parse the action part of a line (the tokens after the time). An error message when
    it is not a valid action. */
export function parseAction(tokens: Token[]): TimelineAction | string {
	const [verb, ...rest] = tokens;
	if (!verb) return 'missing action';
	if (verb.quoted || verb.json) return `unknown action ${JSON.stringify(verb.text)}`;
	const arity = (min: number, max: number) =>
		rest.length < min || rest.length > max ? `"${verb.text}" takes ${min === max ? min : `${min}–${max}`} argument(s)` : '';

	switch (verb.text) {
		case 'goto': {
			const bad = arity(1, 3);
			if (bad) return bad;
			const [target, ...flags] = rest;
			if (!target.text || target.json) return 'goto needs a slide';
			const a: TimelineAction = { kind: 'goto', href: target.text };
			for (const f of flags) {
				if (f.quoted || f.json) return `unknown goto flag ${JSON.stringify(f.text)}`;
				if (f.text === 'back') a.back = true;
				else if (f.text === 'end') a.end = true;
				else return `unknown goto flag "${f.text}" (back, end)`;
			}
			return a;
		}
		case 'step': {
			const bad = arity(0, 1);
			if (bad) return bad;
			if (rest.length === 0) return { kind: 'step' };
			if (rest[0].text === 'back' && !rest[0].quoted) return { kind: 'step', back: true };
			return `unknown step direction "${rest[0].text}" (back)`;
		}
		case 'continue':
			return arity(0, 0) || { kind: 'continue' };
		case 'end':
			return arity(0, 0) || { kind: 'end' };
		case 'anim': {
			const bad = arity(2, 2);
			if (bad) return bad;
			const [mode, frac] = rest;
			if (mode.text !== 'play' && mode.text !== 'pause') return `anim takes play or pause, not "${mode.text}"`;
			const f = Number(frac.text);
			if (frac.quoted || frac.json || !Number.isFinite(f)) return `anim position "${frac.text}" is not a number`;
			return { kind: 'anim', playing: mode.text === 'play', fraction: clamp01(f) };
		}
		case 'trigger': {
			const bad = arity(1, 1);
			if (bad) return bad;
			if (!rest[0].text || rest[0].json) return 'trigger needs a name';
			return { kind: 'trigger', name: rest[0].text };
		}
		case 'highlight': {
			const bad = arity(1, 1);
			if (bad) return bad;
			const [n] = rest;
			if (n.json || !n.text) return 'highlight needs a name or off';
			return { kind: 'highlight', name: !n.quoted && n.text === 'off' ? null : n.text };
		}
		case 'ink': {
			if (rest.length < 2) return 'ink needs a slide and an operation';
			const [slideTok, opTok, ...args] = rest;
			if (slideTok.json || !slideTok.text) return 'ink needs a slide (or *)';
			const slide = slideTok.text;
			switch (opTok.text) {
				case 'clear':
					if (args.length) return 'ink … clear takes no arguments';
					return { kind: 'ink', op: 'clear', slide };
				case 'erase':
					if (slide === '*' && !slideTok.quoted) return 'ink * erase is not allowed — name the slide';
					if (args.length === 0) return 'ink … erase needs at least one stroke id';
					if (args.some((t) => t.json)) return 'ink … erase takes stroke ids';
					return { kind: 'ink', op: 'erase', slide, ids: args.map((t) => t.text) };
				case 'draw': {
					if (slide === '*' && !slideTok.quoted) return 'ink * draw is not allowed — name the slide';
					if (args.length !== 2) return 'ink … draw takes a duration and a {stroke}';
					const dur = Number(args[0].text);
					if (args[0].json || !Number.isFinite(dur) || dur < 0) return `ink draw duration "${args[0].text}" is not a number of seconds`;
					if (!args[1].json) return 'ink … draw needs the stroke as {json}';
					let raw: unknown;
					try {
						raw = JSON.parse(args[1].text);
					} catch {
						return 'ink stroke is not valid JSON';
					}
					const [stroke] = sanitizeStrokes([raw]);
					if (!stroke) return 'ink stroke has no drawable points';
					delete stroke.ms;
					return { kind: 'ink', op: 'draw', slide, dur, stroke };
				}
				default:
					return `unknown ink operation "${opTok.text}" (draw, erase, clear)`;
			}
		}
		default:
			return `unknown action "${verb.text}"`;
	}
}

// --- Whole file -------------------------------------------------------------------------

/** Order events by time, keeping the order of equal times (a stable sort). */
export function sortEvents(events: TimelineEvent[]): TimelineEvent[] {
	return events
		.map((e, i) => ({ e, i }))
		.sort((a, b) => a.e.t - b.e.t || a.i - b.i)
		.map(({ e }) => e);
}

const HEADER_ORDER = ['deck', 'canvas', 'recorded', 'video'];

/** The timeline as text: the magic line, the header, then one sorted line per event. */
export function formatTimeline(tl: Timeline): string {
	const keys = Object.keys(tl.header ?? {}).sort((a, b) => {
		const ia = HEADER_ORDER.indexOf(a), ib = HEADER_ORDER.indexOf(b);
		return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib) || a.localeCompare(b);
	});
	const lines = [`# ${TIMELINE_MAGIC}`];
	for (const k of keys) lines.push(`# ${k}: ${String(tl.header[k]).replace(/[\r\n]+/g, ' ')}`);
	for (const ev of sortEvents(tl.events ?? [])) lines.push(`${formatClock(ev.t)} ${formatAction(ev)}`);
	return lines.join('\n') + '\n';
}

/** Parse a timeline. Every line that is not blank, a comment, a `shift`, or a valid
    `<time> <action>` is an error — none is skipped quietly. Events come back sorted, with
    each `shift` already added to the lines after it. */
export function parseTimeline(text: string): { timeline: Timeline; errors: TimelineError[] } {
	const header: Record<string, string> = {};
	const events: TimelineEvent[] = [];
	const errors: TimelineError[] = [];
	let shift = 0;
	let seenEvent = false;

	const lines = String(text ?? '').split(/\r?\n/);
	lines.forEach((raw, idx) => {
		const line = raw.trim();
		const fail = (message: string) => errors.push({ line: idx + 1, message, text: raw });
		if (!line) return;
		if (line.startsWith('#')) {
			// Header: `# key: value` comments BEFORE the first event.
			const m = /^#\s*([A-Za-z][\w-]*)\s*:\s*(.*)$/.exec(line);
			if (m && !seenEvent) header[m[1].toLowerCase()] = m[2].trim();
			return;
		}
		const tokens = tokenize(line);
		if (!tokens) return fail('unterminated "quote" or {brace}');
		if (tokens.length === 0) return; // only a comment after whitespace
		const [first, ...rest] = tokens;

		if (first.text === 'shift' && !first.quoted) {
			if (rest.length !== 1) return fail('shift takes one number of seconds, e.g. shift +2');
			const by = Number(rest[0].text);
			if (rest[0].quoted || !Number.isFinite(by)) return fail(`shift "${rest[0].text}" is not a number of seconds`);
			shift += by;
			return;
		}

		const t = first.quoted || first.json ? null : parseClock(first.text);
		if (t === null) return fail(`"${first.text}" is not a time (mm:ss.mmm or seconds)`);
		const action = parseAction(rest);
		if (typeof action === 'string') return fail(action);
		seenEvent = true;
		events.push({ ...action, t: Math.max(0, t + shift) });
	});

	return { timeline: { header, events: sortEvents(events) }, errors };
}

/** Add an action stamped at `t` to a live recording's list. A run of animation commands
    closer than `animMergeS` (a scrub drags out dozens a second) collapses into its last
    one, so a scrub keeps its shape without flooding the file. */
export function appendEvent(events: TimelineEvent[], action: TimelineAction, t: number, animMergeS = 0.04): TimelineEvent[] {
	const ev = { ...action, t: Math.max(0, fin(t)) } as TimelineEvent;
	const last = events[events.length - 1];
	if (ev.kind === 'anim' && last?.kind === 'anim' && ev.t - last.t < animMergeS) {
		events[events.length - 1] = { ...ev, t: last.t };
		return events;
	}
	events.push(ev);
	return events;
}

// --- Slides and paths -------------------------------------------------------------------

/** URL flags that belong to a WINDOW, not to the slide, and so never go in a timeline. */
const WINDOW_FLAGS = ['present', 'clean', 'shot', 'adjust', 'annotate', 'bare', 'kiosk', 'capture'];

/** A slide address as the timeline names it: relative to the deck when it is in the deck
    (`intro.html?return=title.html`), else its absolute path. Window flags are dropped.
    `href` may be absolute or relative to `base` (the page navigating). */
export function relativeHref(href: string, deckKey: string, base = 'http://x/'): string {
	let url: URL;
	try {
		url = new URL(href, base);
	} catch {
		return String(href ?? '');
	}
	for (const f of WINDOW_FLAGS) url.searchParams.delete(f);
	const path = url.pathname.replace(/\/+$/, '');
	const search = url.searchParams.toString();
	const tail = (search ? `?${search}` : '') + url.hash;
	if (deckKey && path.startsWith(deckKey) && path.length > deckKey.length) return path.slice(deckKey.length) + tail;
	return (path || '/') + tail;
}

/** The inverse: the absolute path (from the site root) a timeline slide names. */
export function resolveHref(href: string, deckKey: string): string {
	const h = String(href ?? '');
	if (h.startsWith('/')) return h;
	return (deckKey.endsWith('/') ? deckKey : deckKey + '/') + h;
}

/** The pathname (no query, no trailing slash) a timeline slide lands on — what a `here`
    message is compared against when replay waits for the page. */
export function landingPath(href: string, deckKey: string): string {
	return resolveHref(href, deckKey).replace(/[?#].*$/, '').replace(/\/+$/, '');
}

/** The ink-book key (a full pathname) <-> the timeline's slide name. */
export function inkSlide(key: string, deckKey: string): string {
	return key.startsWith(deckKey) && key.length > deckKey.length ? key.slice(deckKey.length) : key;
}
export function inkKey(slide: string, deckKey: string): string {
	return landingPath(slide, deckKey);
}

// --- Ink --------------------------------------------------------------------------------

/** One ink change, and how far BEFORE the moment it was noticed it began — a stroke is
    committed when the pen lifts, but the timeline wants the moment it went down. */
export interface InkChange {
	action: TimelineAction;
	lead: number;
}

/** What changed in this deck's ink between two snapshots of the ink book. New strokes are
    `draw`s with their drawing time; changed ones (an edited label, a dragged mark) are
    instant `draw`s that replace by id; removed ones are `erase`s, or a `clear` when the
    slide was emptied — and `ink * clear` when every slide of the deck was emptied at once
    (RESET ALL). Slides of other decks are ignored. */
export function diffInk(prev: InkBook, next: InkBook, deckKey: string): InkChange[] {
	const inDeck = (k: string) => k.startsWith(deckKey);
	const before = Object.keys(prev ?? {}).filter(inDeck);
	const after = Object.keys(next ?? {}).filter(inDeck);
	if (before.length >= 2 && after.length === 0) {
		return [{ action: { kind: 'ink', op: 'clear', slide: '*' }, lead: 0 }];
	}

	const out: InkChange[] = [];
	for (const key of new Set([...before, ...after])) {
		const slide = inkSlide(key, deckKey);
		const was = prev?.[key]?.strokes ?? [];
		const now = next?.[key]?.strokes ?? [];
		if (was.length > 0 && now.length === 0) {
			out.push({ action: { kind: 'ink', op: 'clear', slide }, lead: 0 });
			continue;
		}
		const nowIds = new Set(now.map((s) => s.id));
		const gone = was.filter((s) => !nowIds.has(s.id)).map((s) => s.id);
		if (gone.length) out.push({ action: { kind: 'ink', op: 'erase', slide, ids: gone }, lead: 0 });

		const wasById = new Map(was.map((s) => [s.id, s]));
		for (const s of now) {
			const old = wasById.get(s.id);
			const { ms, ...stroke } = s;
			if (!old) {
				const dur = Math.max(0, fin(ms)) / 1000;
				out.push({ action: { kind: 'ink', op: 'draw', slide, dur, stroke }, lead: dur });
			} else {
				const { ms: _m, ...oldStroke } = old;
				if (JSON.stringify(oldStroke) !== JSON.stringify(stroke)) {
					out.push({ action: { kind: 'ink', op: 'draw', slide, dur: 0, stroke }, lead: 0 });
				}
			}
		}
	}
	return out;
}

/** The first `fraction` (0..1) of a polyline, by length, ending on an interpolated point —
    what a stroke being replayed looks like partway through its drawing. Never empty for a
    non-empty input. */
export function partialPoints(points: Point[], fraction: number): Point[] {
	if (!Array.isArray(points) || points.length === 0) return [];
	const f = clamp01(fraction);
	if (f >= 1 || points.length === 1) return points.slice();
	const seg: number[] = [];
	let total = 0;
	for (let i = 1; i < points.length; i++) {
		const d = Math.hypot(points[i][0] - points[i - 1][0], points[i][1] - points[i - 1][1]);
		seg.push(d);
		total += d;
	}
	if (total <= 0) return [points[0]];
	let left = total * f;
	const out: Point[] = [points[0]];
	for (let i = 1; i < points.length; i++) {
		const d = seg[i - 1];
		if (left >= d) {
			out.push(points[i]);
			left -= d;
			continue;
		}
		const k = d > 0 ? left / d : 0;
		const a = points[i - 1], b = points[i];
		out.push([a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k]);
		break;
	}
	return out;
}

// --- Video ------------------------------------------------------------------------------

/** The container/codec to record in: MP4 (H.264 + AAC) where the browser can, which
    YouTube and every editor take as-is; WebM otherwise. '' = let the browser pick. */
export function pickMime(isSupported: (type: string) => boolean, withAudio: boolean): string {
	const candidates = withAudio
		? [
				'video/mp4;codecs=avc1.640028,mp4a.40.2',
				'video/mp4;codecs=avc1.4d0028,mp4a.40.2',
				'video/mp4;codecs=avc1,mp4a.40.2',
				'video/mp4',
				'video/webm;codecs=vp9,opus',
				'video/webm;codecs=vp8,opus',
				'video/webm'
			]
		: [
				'video/mp4;codecs=avc1.640028',
				'video/mp4;codecs=avc1.4d0028',
				'video/mp4;codecs=avc1',
				'video/mp4',
				'video/webm;codecs=vp9',
				'video/webm;codecs=vp8',
				'video/webm'
			];
	for (const c of candidates) {
		try {
			if (isSupported(c)) return c;
		} catch {
			/* a throwing probe is a no */
		}
	}
	return '';
}

/** File extension for a recorded MIME type. */
export function extensionFor(mime: string): string {
	return /^video\/mp4/.test(mime ?? '') ? 'mp4' : 'webm';
}

/** Video bitrate in bits/s — YouTube's recommended upload rate for SDR: 8 Mbps at
    1080p30, 12 Mbps at 1080p60, scaled by pixel count for other sizes. */
export function videoBitrate(width: number, height: number, fps: number): number {
	const pixels = Math.max(1, fin(width, 1920) * fin(height, 1080));
	const base = 8_000_000 * (pixels / (1920 * 1080));
	const rate = base * (fin(fps, 30) > 30 ? 1.5 : 1);
	return Math.round(Math.max(2_500_000, Math.min(68_000_000, rate)));
}

/** The output sizes on offer for a canvas, all keeping its aspect: 2/3 (720p for a stock
    deck), 1× (the canvas — the default), 4/3 (1440p) and 2× (4K). Even numbers, which
    H.264 requires. */
export function outputSizes(canvasW: number, canvasH: number): { width: number; height: number; label: string }[] {
	const w = fin(canvasW, 1920) > 0 ? fin(canvasW, 1920) : 1920;
	const h = fin(canvasH, 1080) > 0 ? fin(canvasH, 1080) : 1080;
	const even = (n: number) => Math.max(2, Math.round(n / 2) * 2);
	return [2 / 3, 1, 4 / 3, 2].map((k) => {
		const width = even(w * k), height = even(h * k);
		return { width, height, label: `${width}×${height}${k === 1 ? ' (canvas)' : ''}` };
	});
}

/** Where a `srcW×srcH` frame lands inside a `dstW×dstH` one: scaled to fit, centred,
    the rest black (letterbox / pillarbox). */
export function letterbox(srcW: number, srcH: number, dstW: number, dstH: number): { x: number; y: number; width: number; height: number } {
	const sw = fin(srcW), sh = fin(srcH), dw = fin(dstW), dh = fin(dstH);
	if (sw <= 0 || sh <= 0 || dw <= 0 || dh <= 0) return { x: 0, y: 0, width: Math.max(0, dw), height: Math.max(0, dh) };
	const k = Math.min(dw / sw, dh / sh);
	const width = sw * k, height = sh * k;
	return { x: (dw - width) / 2, y: (dh - height) / 2, width, height };
}

/** Does a captured frame have the canvas's shape (within 1%)? If not, the video gets bars. */
export function sameAspect(aW: number, aH: number, bW: number, bH: number): boolean {
	if (!(aW > 0 && aH > 0 && bW > 0 && bH > 0)) return false;
	return Math.abs(aW / aH / (bW / bH) - 1) < 0.01;
}

/** A file-name-safe stamp for a recording: `<deck>-2026-10-22-1405`. */
export function recordingName(deckKey: string, now: Date): string {
	const deck = String(deckKey ?? '').replace(/^\/+|\/+$/g, '').replace(/[^\w-]+/g, '-') || 'deck';
	const p = (n: number) => String(n).padStart(2, '0');
	const d = now instanceof Date && !isNaN(now.getTime()) ? now : new Date(0);
	return `${deck}-${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
}

// --- The ink book, as replay writes it -----------------------------------------------------

/** Put `stroke` on the slide at `key` — replacing the stroke with its id, else appended. */
export function bookPut(book: InkBook, key: string, stroke: Stroke, ts: number): InkBook {
	const strokes = book[key]?.strokes ?? [];
	const i = strokes.findIndex((s) => s.id === stroke.id);
	const next = i >= 0 ? strokes.map((s, j) => (j === i ? stroke : s)) : [...strokes, stroke];
	return { ...book, [key]: { strokes: next, ts } };
}

/** Remove strokes by id from the slide at `key` (the slide's entry goes when it empties). */
export function bookErase(book: InkBook, key: string, ids: string[], ts: number): InkBook {
	const drop = new Set(ids);
	const strokes = (book[key]?.strokes ?? []).filter((s) => !drop.has(s.id));
	const copy = { ...book };
	if (strokes.length) copy[key] = { strokes, ts };
	else delete copy[key];
	return copy;
}

/** Remove the slide at `key` — or, with `key` = null, every slide under `deckKey`. */
export function bookClear(book: InkBook, key: string | null, deckKey: string): InkBook {
	const copy = { ...book };
	for (const k of Object.keys(copy)) if (key === null ? k.startsWith(deckKey) : k === key) delete copy[k];
	return copy;
}

/** Every stroke already on the deck, as `draw` lines at 0 — how a take that KEEPS the ink
    on the slides writes it down, so its replay starts from the same page. */
export function inkSnapshot(book: InkBook, deckKey: string): TimelineAction[] {
	const out: TimelineAction[] = [];
	for (const [key, ink] of Object.entries(book ?? {})) {
		if (!key.startsWith(deckKey)) continue;
		for (const s of ink.strokes) {
			const { ms: _ms, ...stroke } = s;
			out.push({ kind: 'ink', op: 'draw', slide: inkSlide(key, deckKey), dur: 0, stroke });
		}
	}
	return out;
}
