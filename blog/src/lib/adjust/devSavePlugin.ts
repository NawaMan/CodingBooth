import type { Plugin, ViteDevServer } from 'vite';
import { promises as fs } from 'node:fs';
import * as path from 'node:path';
import { patchSlideSource, type LayoutChange } from './patchSource';
import { routeToPageFile } from './routeToPage';
import { resolveStampedFile, stampPath, stampSourceFile } from './sourceTag';
import { deckToPagesFile, deckToSlideDir } from '../deckEdit/routeToDeck';
import {
	insertPagesEntry,
	removePagesEntry,
	normalizeSlidePath,
	normalizeTemplate,
	scaffoldPage,
	LAYOUT_JS,
	listEntryPaths
} from '../deckEdit/pageEditCore';
import { fingerprint, readNote, writeNote, REFUSAL_TEXT } from '../note/noteSourceCore';

// Dev-only Vite plugin that lets authoring tools read/write a slide's source.
// It exists solely under `vite dev` (apply: 'serve'): a built site has no Node
// process and must stay read-only / copy-paste only, so there is deliberately
// no production counterpart.
//
// Endpoints share the route→file mapping:
//
//   POST /__geekpresent/adjust-save   — ADJUST mode: surgical Block/Draw patches
//   POST /__geekpresent/source-save   — ViewSource EDIT: full +page.svelte overwrite
//   GET  /__geekpresent/source-load   — ViewSource EDIT REFRESH: read +page.svelte
//   POST /__geekpresent/page-add      — Overview EDIT: new slide folder + pages.ts entry
//   POST /__geekpresent/page-remove   — Overview EDIT: unlist from pages.ts (folder stays)
//   GET  /__geekpresent/note-load     — presenter NOTE EDIT: the <Note>'s inner source
//   POST /__geekpresent/note-save     — presenter NOTE EDIT: splice it back (see noteSourceCore)
//
// Tags ADJUST cannot confidently place come back as `unmatched` so the UI can
// tell the author to paste those by hand. Source SAVE writes the whole buffer.

const ADJUST_ENDPOINT = '/__geekpresent/adjust-save';
const SOURCE_SAVE_ENDPOINT = '/__geekpresent/source-save';
const SOURCE_LOAD_ENDPOINT = '/__geekpresent/source-load';
const PAGE_ADD_ENDPOINT = '/__geekpresent/page-add';
const PAGE_REMOVE_ENDPOINT = '/__geekpresent/page-remove';
const NOTE_LOAD_ENDPOINT = '/__geekpresent/note-load';
const NOTE_SAVE_ENDPOINT = '/__geekpresent/note-save';

interface AdjustSaveRequest {
	/** The slide's `location.pathname`, e.g. `/slides/title.html`. */
	route: string;
	/** Each change may name the file its tag was WRITTEN in (the `__file` stamp,
	    see sourceTag.ts) — a Block in a shared scene component, say. Without
	    one, the change belongs to the slide's own +page.svelte. */
	changes: (LayoutChange & { file?: string })[];
}

interface SourceSaveRequest {
	route: string;
	/** Full new contents of the slide's `+page.svelte`. */
	content: string;
}

interface NoteSaveRequest {
	route: string;
	/** The edited inner source, dedented as note-load handed it out. */
	text: string;
	/** note-load's fingerprint of the file; a mismatch means it changed meanwhile. */
	fingerprint: string;
}

interface PageAddRequest {
	deck: string;
	path: string;
	title: string;
	template?: string;
	/** Insert after this path; null/omit = append. */
	after?: string | null;
}

interface PageRemoveRequest {
	deck: string;
	path: string;
}

function readBody(req: import('node:http').IncomingMessage, maxBytes: number): Promise<string> {
	return new Promise((resolve, reject) => {
		let data = '';
		req.on('data', (chunk) => {
			data += chunk;
			if (data.length > maxBytes) reject(new Error('payload too large'));
		});
		req.on('end', () => resolve(data));
		req.on('error', reject);
	});
}

function parseRouteQuery(url: string): string | null {
	try {
		// url may be path + query (no origin) — URL needs a base.
		const u = new URL(url, 'http://dev.local');
		const route = u.searchParams.get('route');
		return route && route.trim() ? route : null;
	} catch {
		return null;
	}
}

async function readPageFile(server: ViteDevServer, route: string) {
	const root = server.config.root;
	const file = routeToPageFile(route, server.config.base, root);
	if (!file) {
		return { status: 400 as const, payload: { error: `cannot map route "${route}" to a file` } };
	}
	try {
		const content = await fs.readFile(file, 'utf8');
		return {
			status: 200 as const,
			payload: { file: path.relative(root, file), content }
		};
	} catch {
		return {
			status: 404 as const,
			payload: {
				error: `no +page.svelte for route "${route}" (${path.relative(root, file)})`
			}
		};
	}
}

/** Exported for tests/sourceTag.test.ts, which drives it against a temp project. */
export async function handleAdjustSave(server: ViteDevServer, body: string) {
	const { route, changes } = JSON.parse(body) as AdjustSaveRequest;
	if (!route || !Array.isArray(changes)) {
		return { status: 400, payload: { error: 'route and changes are required' } };
	}

	const root = server.config.root;
	const pageFile = routeToPageFile(route, server.config.base, root);
	if (!pageFile) {
		return { status: 400, payload: { error: `cannot map route "${route}" to a file` } };
	}

	// Sort the changes by the file they belong to: the slide's own +page.svelte,
	// unless a change carries a stamp naming the component its tag was written in.
	// A stamp that resolves outside src/routes is refused, never guessed at.
	const byFile = new Map<string, LayoutChange[]>();
	for (const { file: stamp, ...change } of changes) {
		const target = stamp ? resolveStampedFile(stamp, root) : pageFile;
		if (!target) {
			return { status: 400, payload: { error: `refusing to write "${stamp}": not a .svelte file under src/routes` } };
		}
		if (!byFile.has(target)) byFile.set(target, []);
		byFile.get(target)!.push(change);
	}

	const patched: LayoutChange[] = [];
	const unmatched: ReturnType<typeof patchSlideSource>['unmatched'] = [];
	const written: string[] = [];
	for (const [file, fileChanges] of byFile) {
		let source: string;
		try {
			source = await fs.readFile(file, 'utf8');
		} catch {
			return { status: 404, payload: { error: `no such file: ${path.relative(root, file)}` } };
		}
		const result = patchSlideSource(source, fileChanges);
		patched.push(...result.patched);
		unmatched.push(...result.unmatched);
		if (result.patched.length && result.source !== source) {
			await fs.writeFile(file, result.source, 'utf8');
			written.push(file);
		}
	}

	if (written.length) {
		// Tell Vite each file changed. This is NOT belt-and-braces — without it the
		// write is invisible to the dev server: the watcher does not see writes made
		// through a bind mount (and would not be trusted to be prompt even when it
		// does), so the module graph keeps serving the transform it cached at first
		// request. The browser then reloads straight back into the OLD source, mounts
		// the OLD baseline, and every save after the first is refused as drift — with
		// the file on disk and the module being served disagreeing the whole time.
		// Emitting the change drives Vite's ordinary invalidate + HMR path.
		for (const file of written) server.watcher.emit('change', file);

		// Force the page to re-mount from what we just wrote.
		//
		// Every change describes itself relative to the source the browser MOUNTED
		// with — a Block's `before` box, a shape's `oldTag`. The patcher refuses
		// anything whose baseline no longer matches the file, which is what stops a
		// save from clobbering an edit made behind its back. That guard turns on
		// the saver itself the moment a page saves twice: after the first write the
		// file has moved on, the mounted baseline has not, and every later save is
		// rejected as drift. SAVE worked exactly once per page load.
		//
		// The client already assumed a reload closed this loop (see adjustSave.ts),
		// but Svelte's HMR update keeps the live component state that ADJUST is
		// editing, so the props — and with them the baseline — never refresh. Only a
		// full reload re-reads the source. It costs the current selection and scroll
		// position, which is the right trade for a dev-only authoring mode: a stale
		// baseline silently refuses every subsequent save.
		server.ws.send({ type: 'full-reload', path: '*' });
	}

	return {
		status: 200,
		payload: {
			file: path.relative(root, pageFile),
			// Every file this save wrote — the slide, and any component it reached into.
			files: written.map((f) => path.relative(root, f)),
			patched: patched.length,
			unmatched: unmatched.map((c) => ({
				label: c.name || (c.before ? `${c.kind}@${c.before.x},${c.before.y}` : c.kind),
				reason: c.reason
			}))
		}
	};
}

async function handleSourceSave(server: ViteDevServer, body: string) {
	const { route, content } = JSON.parse(body) as SourceSaveRequest;
	if (!route || typeof content !== 'string') {
		return { status: 400, payload: { error: 'route and content are required' } };
	}
	// Empty would wipe the slide; refuse rather than write zero bytes.
	if (content.length === 0) {
		return { status: 400, payload: { error: 'refusing to write empty content' } };
	}

	const root = server.config.root;
	const file = routeToPageFile(route, server.config.base, root);
	if (!file) {
		return { status: 400, payload: { error: `cannot map route "${route}" to a file` } };
	}

	// The file must already exist — never create a page from a bad route mapping.
	try {
		await fs.access(file);
	} catch {
		return {
			status: 404,
			payload: { error: `no +page.svelte for route "${route}" (${path.relative(root, file)})` }
		};
	}

	await fs.writeFile(file, content, 'utf8');

	return {
		status: 200,
		payload: { file: path.relative(root, file) }
	};
}

async function handleSourceLoad(server: ViteDevServer, url: string) {
	const route = parseRouteQuery(url);
	if (!route) {
		return { status: 400, payload: { error: 'route query parameter is required' } };
	}
	return readPageFile(server, route);
}

/** Exported for tests/noteEdit.test.ts, which drives it against a temp project. */
export async function handleNoteLoad(server: ViteDevServer, url: string) {
	const route = parseRouteQuery(url);
	if (!route) {
		return { status: 400, payload: { error: 'route query parameter is required' } };
	}
	const read = await readPageFile(server, route);
	if (read.status !== 200) return read;
	const { file, content } = read.payload as { file: string; content: string };
	const note = readNote(content);
	if (!note.ok) {
		return { status: 409, payload: { error: REFUSAL_TEXT[note.reason], reason: note.reason } };
	}
	return { status: 200, payload: { file, text: note.text, fingerprint: fingerprint(content) } };
}

/** Exported for tests/noteEdit.test.ts. */
export async function handleNoteSave(server: ViteDevServer, body: string) {
	const { route, text, fingerprint: seen } = JSON.parse(body) as NoteSaveRequest;
	if (!route || typeof text !== 'string' || typeof seen !== 'string') {
		return { status: 400, payload: { error: 'route, text and fingerprint are required' } };
	}
	const read = await readPageFile(server, route);
	if (read.status !== 200) return read;
	const { file, content } = read.payload as { file: string; content: string };
	if (fingerprint(content) !== seen) {
		return { status: 409, payload: { error: REFUSAL_TEXT.conflict, reason: 'conflict' } };
	}
	const next = writeNote(content, text);
	if (!next.ok) {
		return { status: 409, payload: { error: REFUSAL_TEXT[next.reason], reason: next.reason } };
	}
	if (next.source !== content) {
		await fs.writeFile(path.resolve(server.config.root, file), next.source, 'utf8');
	}
	return { status: 200, payload: { file, fingerprint: fingerprint(next.source) } };
}

async function handlePageAdd(server: ViteDevServer, body: string) {
	const req = JSON.parse(body) as PageAddRequest;
	const deck = String(req.deck ?? '').trim();
	const title = String(req.title ?? '').trim();
	const norm = normalizeSlidePath(String(req.path ?? ''));
	const template = normalizeTemplate(req.template);
	const after =
		req.after == null || req.after === ''
			? null
			: (normalizeSlidePath(String(req.after)) ?? String(req.after));

	if (!deck || !norm || !title) {
		return { status: 400, payload: { error: 'deck, path and title are required' } };
	}

	const root = server.config.root;
	const pagesFile = deckToPagesFile(deck, root);
	const slideDir = deckToSlideDir(deck, norm, root);
	if (!pagesFile || !slideDir) {
		return { status: 400, payload: { error: `invalid deck or path ("${deck}" / "${norm}")` } };
	}

	// Refuse if the folder already exists (any file inside).
	try {
		await fs.access(slideDir);
		return {
			status: 409,
			payload: { error: `slide folder already exists: ${path.relative(root, slideDir)}` }
		};
	} catch {
		// good — does not exist
	}

	let pagesSource: string;
	try {
		pagesSource = await fs.readFile(pagesFile, 'utf8');
	} catch {
		return {
			status: 404,
			payload: { error: `no pages.ts for deck "${deck}" (${path.relative(root, pagesFile)})` }
		};
	}

	if (listEntryPaths(pagesSource).includes(norm)) {
		return { status: 409, payload: { error: `pages.ts already lists "${norm}"` } };
	}

	const edited = insertPagesEntry(pagesSource, norm, title, after);
	if (!edited.ok) {
		return { status: 400, payload: { error: edited.error } };
	}

	const pageFile = path.join(slideDir, '+page.svelte');
	const layoutFile = path.join(slideDir, '+layout.js');

	await fs.mkdir(slideDir, { recursive: true });
	await fs.writeFile(layoutFile, LAYOUT_JS, 'utf8');
	await fs.writeFile(
		pageFile,
		scaffoldPage(template, title, { deck, path: norm }),
		'utf8'
	);
	await fs.writeFile(pagesFile, edited.source, 'utf8');

	return {
		status: 200,
		payload: {
			ok: true,
			path: norm,
			file: path.relative(root, pageFile),
			pages: path.relative(root, pagesFile)
		}
	};
}

async function handlePageRemove(server: ViteDevServer, body: string) {
	const req = JSON.parse(body) as PageRemoveRequest;
	const deck = String(req.deck ?? '').trim();
	const norm = normalizeSlidePath(String(req.path ?? '')) ?? String(req.path ?? '').trim();

	if (!deck || !norm) {
		return { status: 400, payload: { error: 'deck and path are required' } };
	}

	const root = server.config.root;
	const pagesFile = deckToPagesFile(deck, root);
	if (!pagesFile) {
		return { status: 400, payload: { error: `invalid deck "${deck}"` } };
	}

	let pagesSource: string;
	try {
		pagesSource = await fs.readFile(pagesFile, 'utf8');
	} catch {
		return {
			status: 404,
			payload: { error: `no pages.ts for deck "${deck}" (${path.relative(root, pagesFile)})` }
		};
	}

	const edited = removePagesEntry(pagesSource, norm);
	if (!edited.ok) {
		return { status: 400, payload: { error: edited.error } };
	}

	await fs.writeFile(pagesFile, edited.source, 'utf8');

	return {
		status: 200,
		payload: {
			ok: true,
			path: norm,
			pages: path.relative(root, pagesFile),
			// Phase 1: folder intentionally left on disk (unlist only).
			unlisted: true
		}
	};
}

/** Dev-only: stamp every Block-family tag in a route file with the file it was
    written in (`__file="src/routes/…"`), so ADJUST's SAVE can write a Block that
    lives in a component back into THAT component. See sourceTag.ts. Runs before
    the Svelte plugin, on the raw source; the insert stays on the tag's own line,
    so line numbers in errors are unchanged. */
export function sourceStampPlugin(): Plugin {
	let root = process.cwd();
	return {
		name: 'geekpresent-source-stamp',
		apply: 'serve',
		enforce: 'pre',
		configResolved(config) {
			root = config.root;
		},
		transform(code, id) {
			const file = stampPath(id, root);
			if (!file) return null;
			const stamped = stampSourceFile(code, file);
			return stamped === code ? null : { code: stamped, map: null };
		}
	};
}

export function adjustSavePlugin(): Plugin {
	return {
		name: 'geekpresent-adjust-save',
		apply: 'serve',
		configureServer(server) {
			server.middlewares.use(async (req, res, next) => {
				if (!req.url) return next();
				const pathOnly = req.url.split('?')[0];
				const isAdjust =
					pathOnly === ADJUST_ENDPOINT || pathOnly.startsWith(ADJUST_ENDPOINT + '/');
				const isSourceSave =
					pathOnly === SOURCE_SAVE_ENDPOINT ||
					pathOnly.startsWith(SOURCE_SAVE_ENDPOINT + '/');
				const isSourceLoad =
					pathOnly === SOURCE_LOAD_ENDPOINT ||
					pathOnly.startsWith(SOURCE_LOAD_ENDPOINT + '/');
				const isPageAdd =
					pathOnly === PAGE_ADD_ENDPOINT || pathOnly.startsWith(PAGE_ADD_ENDPOINT + '/');
				const isPageRemove =
					pathOnly === PAGE_REMOVE_ENDPOINT ||
					pathOnly.startsWith(PAGE_REMOVE_ENDPOINT + '/');
				const isNoteLoad = pathOnly === NOTE_LOAD_ENDPOINT;
				const isNoteSave = pathOnly === NOTE_SAVE_ENDPOINT;
				if (
					!isAdjust && !isSourceSave && !isSourceLoad && !isPageAdd && !isPageRemove &&
					!isNoteLoad && !isNoteSave
				) {
					return next();
				}

				try {
					if (isSourceLoad || isNoteLoad) {
						if (req.method !== 'GET') {
							res.statusCode = 405;
							res.end('method not allowed');
							return;
						}
						const { status, payload } = isNoteLoad
							? await handleNoteLoad(server, req.url)
							: await handleSourceLoad(server, req.url);
						res.statusCode = status;
						res.setHeader('content-type', 'application/json');
						res.end(JSON.stringify(payload));
						return;
					}

					if (req.method !== 'POST') {
						res.statusCode = 405;
						res.end('method not allowed');
						return;
					}
					// Source saves carry a whole file; structure edits and ADJUST patches are tiny.
					const maxBytes = isSourceSave ? 5_000_000 : 1_000_000;
					const body = await readBody(req, maxBytes);
					const { status, payload } = isNoteSave
						? await handleNoteSave(server, body)
						: isPageAdd
						? await handlePageAdd(server, body)
						: isPageRemove
							? await handlePageRemove(server, body)
							: isSourceSave
								? await handleSourceSave(server, body)
								: await handleAdjustSave(server, body);
					res.statusCode = status;
					res.setHeader('content-type', 'application/json');
					res.end(JSON.stringify(payload));
				} catch (err) {
					res.statusCode = 500;
					res.setHeader('content-type', 'application/json');
					res.end(JSON.stringify({ error: err instanceof Error ? err.message : String(err) }));
				}
			});
		}
	};
}
