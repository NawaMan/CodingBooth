import type { Plugin, ViteDevServer } from 'vite';
import { promises as fs } from 'node:fs';
import * as path from 'node:path';
import { patchSlideSource, type LayoutChange } from './patchSource';
import { routeToPageFile } from './routeToPage';
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
//
// Tags ADJUST cannot confidently place come back as `unmatched` so the UI can
// tell the author to paste those by hand. Source SAVE writes the whole buffer.

const ADJUST_ENDPOINT = '/__geekpresent/adjust-save';
const SOURCE_SAVE_ENDPOINT = '/__geekpresent/source-save';
const SOURCE_LOAD_ENDPOINT = '/__geekpresent/source-load';
const PAGE_ADD_ENDPOINT = '/__geekpresent/page-add';
const PAGE_REMOVE_ENDPOINT = '/__geekpresent/page-remove';

interface AdjustSaveRequest {
	/** The slide's `location.pathname`, e.g. `/slides/title.html`. */
	route: string;
	changes: LayoutChange[];
}

interface SourceSaveRequest {
	route: string;
	/** Full new contents of the slide's `+page.svelte`. */
	content: string;
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

async function handleAdjustSave(server: ViteDevServer, body: string) {
	const { route, changes } = JSON.parse(body) as AdjustSaveRequest;
	if (!route || !Array.isArray(changes)) {
		return { status: 400, payload: { error: 'route and changes are required' } };
	}

	const loaded = await readPageFile(server, route);
	if (loaded.status !== 200) return loaded;

	const source = loaded.payload.content as string;
	const fileRel = loaded.payload.file as string;
	const root = server.config.root;
	const file = routeToPageFile(route, server.config.base, root)!;

	const { source: next, patched, unmatched } = patchSlideSource(source, changes);
	if (patched.length && next !== source) {
		await fs.writeFile(file, next, 'utf8');
	}

	return {
		status: 200,
		payload: {
			file: fileRel,
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
				if (!isAdjust && !isSourceSave && !isSourceLoad && !isPageAdd && !isPageRemove) {
					return next();
				}

				try {
					if (isSourceLoad) {
						if (req.method !== 'GET') {
							res.statusCode = 405;
							res.end('method not allowed');
							return;
						}
						const { status, payload } = await handleSourceLoad(server, req.url);
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
					const { status, payload } = isPageAdd
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
