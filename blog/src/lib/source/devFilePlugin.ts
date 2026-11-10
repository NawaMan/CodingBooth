import type { Plugin } from 'vite';
import { promises as fs } from 'node:fs';
import * as path from 'node:path';
import {
	EDITABLE_ROOTS,
	FILE_REFUSAL_TEXT,
	checkEditablePath,
	editableRootOf
} from './fileAccessCore';
import { importCandidates, isLocalSpecifier } from './importResolveCore';
import { fingerprint } from '../note/noteSourceCore';

// Dev-only endpoints behind the EDIT window's file tree and tabs. Like
// adjustSavePlugin they exist only under `vite dev` (apply: 'serve'): a built
// site has no Node process, so the editor there stays a read-only single file.
//
//   GET  /__geekpresent/file-tree                  — every editable file
//   GET  /__geekpresent/file-load?path=…           — content + fingerprint
//   POST /__geekpresent/file-save {path, content, fingerprint}
//                                                  — refused (409) if the file
//                                                    changed since it was loaded
//   GET  /__geekpresent/file-resolve?from=…&spec=… — the file an import names
//
// What is editable is fileAccessCore's allowlist, plus two checks only the disk
// can answer: the file already exists (nothing is created), and its real path —
// symlinks resolved — is still inside the root it claims to be under.

const TREE_ENDPOINT = '/__geekpresent/file-tree';
const LOAD_ENDPOINT = '/__geekpresent/file-load';
const SAVE_ENDPOINT = '/__geekpresent/file-save';
const RESOLVE_ENDPOINT = '/__geekpresent/file-resolve';

type Result = { status: number; payload: Record<string, unknown> };

/** Every editable file under the editable roots, sorted. Symlinks are skipped,
    not followed, so the walk can never leave the tree. */
export async function listEditableFiles(root: string): Promise<string[]> {
	const out: string[] = [];
	async function walk(rel: string) {
		let entries;
		try {
			entries = await fs.readdir(path.join(root, rel), { withFileTypes: true });
		} catch {
			return;
		}
		for (const e of entries) {
			if (e.name.startsWith('.') || e.name === 'node_modules' || e.isSymbolicLink()) continue;
			const child = `${rel}/${e.name}`;
			if (e.isDirectory()) await walk(child);
			else if (e.isFile() && checkEditablePath(child).ok) out.push(child);
		}
	}
	for (const r of EDITABLE_ROOTS) await walk(r);
	return out.sort();
}

/** Map a requested path to an existing, editable file on disk, or say why not. */
async function resolveEditable(
	root: string,
	requested: unknown
): Promise<{ ok: true; rel: string; abs: string } | { ok: false; result: Result }> {
	const checked = checkEditablePath(requested);
	if (!checked.ok) {
		return {
			ok: false,
			result: {
				status: 403,
				payload: { error: FILE_REFUSAL_TEXT[checked.reason], reason: checked.reason }
			}
		};
	}
	const abs = path.join(root, checked.path);
	let real: string;
	let realRoot: string;
	try {
		real = await fs.realpath(abs);
		realRoot = await fs.realpath(path.join(root, editableRootOf(checked.path)!));
	} catch {
		return {
			ok: false,
			result: { status: 404, payload: { error: `no such file: ${checked.path}` } }
		};
	}
	if (!real.startsWith(realRoot + path.sep)) {
		return {
			ok: false,
			result: { status: 403, payload: { error: FILE_REFUSAL_TEXT.outside, reason: 'outside' } }
		};
	}
	const stat = await fs.stat(real);
	if (!stat.isFile()) {
		return {
			ok: false,
			result: { status: 404, payload: { error: `not a file: ${checked.path}` } }
		};
	}
	return { ok: true, rel: checked.path, abs: real };
}

function query(url: string, name: string): string | null {
	try {
		return new URL(url, 'http://dev.local').searchParams.get(name);
	} catch {
		return null;
	}
}

export async function handleFileTree(root: string): Promise<Result> {
	return { status: 200, payload: { files: await listEditableFiles(root) } };
}

export async function handleFileLoad(root: string, url: string): Promise<Result> {
	const file = await resolveEditable(root, query(url, 'path'));
	if (!file.ok) return file.result;
	const content = await fs.readFile(file.abs, 'utf8');
	return { status: 200, payload: { file: file.rel, content, fingerprint: fingerprint(content) } };
}

export async function handleFileSave(root: string, body: string): Promise<Result> {
	let req: { path?: unknown; content?: unknown; fingerprint?: unknown };
	try {
		req = JSON.parse(body);
	} catch {
		return { status: 400, payload: { error: 'body must be JSON' } };
	}
	if (typeof req.content !== 'string' || typeof req.fingerprint !== 'string') {
		return { status: 400, payload: { error: 'path, content and fingerprint are required' } };
	}
	// Empty would wipe the file; refuse rather than write zero bytes.
	if (req.content.length === 0) {
		return { status: 400, payload: { error: 'refusing to write empty content' } };
	}
	const file = await resolveEditable(root, req.path);
	if (!file.ok) return file.result;
	const current = await fs.readFile(file.abs, 'utf8');
	const now = fingerprint(current);
	if (now !== req.fingerprint) {
		return {
			status: 409,
			payload: {
				error: `${file.rel} changed on disk since it was opened.`,
				reason: 'conflict',
				fingerprint: now
			}
		};
	}
	await fs.writeFile(file.abs, req.content, 'utf8');
	return { status: 200, payload: { file: file.rel, fingerprint: fingerprint(req.content) } };
}

export async function handleFileResolve(root: string, url: string): Promise<Result> {
	const spec = query(url, 'spec') ?? '';
	const from = checkEditablePath(query(url, 'from'));
	if (!from.ok) {
		return { status: 400, payload: { error: FILE_REFUSAL_TEXT[from.reason], reason: from.reason } };
	}
	if (!isLocalSpecifier(spec.split('?')[0])) {
		return { status: 404, payload: { error: `"${spec}" is a package, not a project file.` } };
	}
	for (const candidate of importCandidates(spec, from.path)) {
		const file = await resolveEditable(root, candidate);
		if (file.ok) return { status: 200, payload: { file: file.rel } };
	}
	return {
		status: 404,
		payload: { error: `"${spec}" is not an editable file under src/routes or src/lib.` }
	};
}

export function sourceFilesPlugin(): Plugin {
	return {
		name: 'geekpresent-source-files',
		apply: 'serve',
		configureServer(server) {
			server.middlewares.use(async (req, res, next) => {
				const url = req.url || '';
				const pathOnly = url.split('?')[0];
				const endpoints = [TREE_ENDPOINT, LOAD_ENDPOINT, SAVE_ENDPOINT, RESOLVE_ENDPOINT];
				if (!endpoints.includes(pathOnly)) return next();

				const root = server.config.root;
				const wantPost = pathOnly === SAVE_ENDPOINT;
				if (req.method !== (wantPost ? 'POST' : 'GET')) {
					res.statusCode = 405;
					res.end('method not allowed');
					return;
				}
				try {
					let result: Result;
					if (pathOnly === TREE_ENDPOINT) result = await handleFileTree(root);
					else if (pathOnly === LOAD_ENDPOINT) result = await handleFileLoad(root, url);
					else if (pathOnly === RESOLVE_ENDPOINT) result = await handleFileResolve(root, url);
					else result = await handleFileSave(root, await readBody(req, 5_000_000));
					res.statusCode = result.status;
					res.setHeader('content-type', 'application/json');
					res.end(JSON.stringify(result.payload));
				} catch (err) {
					res.statusCode = 500;
					res.setHeader('content-type', 'application/json');
					res.end(JSON.stringify({ error: err instanceof Error ? err.message : String(err) }));
				}
			});
		}
	};
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
