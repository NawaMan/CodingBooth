// Which files the EDIT window may open and save (pure; the dev endpoints in
// devFilePlugin.ts add the filesystem half: the file must exist, and its REAL
// path — symlinks resolved — must still be under the same root).
//
// The rule is an allowlist, not a denylist: a project-relative path under one of
// EDITABLE_ROOTS, with an extension in EDITABLE_EXTENSIONS, and nothing hidden on
// the way. Every write endpoint is reachable by anything that can reach the dev
// server's port, so "what may be written" stays as narrow as the editor needs.

/** Project-relative folders the editor can see and write. */
export const EDITABLE_ROOTS = ['src/routes', 'src/lib'] as const;

/** Text files worth editing here. Images, fonts and the like are not. */
export const EDITABLE_EXTENSIONS = [
	'.svelte',
	'.ts',
	'.js',
	'.mjs',
	'.css',
	'.md',
	'.json',
	'.svg',
	'.html',
	'.txt'
] as const;

export type FileRefusal = 'empty' | 'absolute' | 'traversal' | 'hidden' | 'outside' | 'extension';

export type EditablePath = { ok: true; path: string } | { ok: false; reason: FileRefusal };

/** What each refusal tells the author. */
export const FILE_REFUSAL_TEXT: Record<FileRefusal, string> = {
	empty: 'No file was named.',
	absolute: 'Name the file relative to the project (src/…), not as an absolute path.',
	traversal: 'A path may not step out with "..".',
	hidden: 'Hidden files and folders (.git, .svelte-kit, …) are not editable here.',
	outside: 'Only files under src/routes and src/lib are editable here.',
	extension: 'Only text source files (.svelte, .ts, .js, .css, .md, …) are editable here.'
};

/** The file's extension, lower-cased, with the dot (`''` when none). */
export function extensionOf(file: string): string {
	const name = file.slice(file.lastIndexOf('/') + 1);
	const dot = name.lastIndexOf('.');
	return dot > 0 ? name.slice(dot).toLowerCase() : '';
}

/** Normalise and check a project-relative path. Total: junk yields a refusal. */
export function checkEditablePath(input: unknown): EditablePath {
	if (typeof input !== 'string' || !input.trim()) return { ok: false, reason: 'empty' };
	let p = input.trim().replace(/\\/g, '/');
	if (p.startsWith('/') || /^[a-z]:/i.test(p)) return { ok: false, reason: 'absolute' };
	while (p.startsWith('./')) p = p.slice(2);
	const segments = p.split('/');
	if (segments.some((s) => s === '..' || s === '.' || s === '')) {
		return { ok: false, reason: 'traversal' };
	}
	if (segments.some((s) => s.startsWith('.'))) return { ok: false, reason: 'hidden' };
	if (segments.includes('node_modules')) return { ok: false, reason: 'outside' };
	const under = EDITABLE_ROOTS.some((root) => p.startsWith(root + '/'));
	if (!under) return { ok: false, reason: 'outside' };
	if (!(EDITABLE_EXTENSIONS as readonly string[]).includes(extensionOf(p))) {
		return { ok: false, reason: 'extension' };
	}
	return { ok: true, path: p };
}

/** The editable root a checked path sits under (for the real-path check). */
export function editableRootOf(path: string): string | null {
	return EDITABLE_ROOTS.find((root) => path.startsWith(root + '/')) ?? null;
}

const LANGUAGE_BY_EXTENSION: Record<string, string> = {
	'.svelte': 'svelte',
	'.ts': 'typescript',
	'.js': 'javascript',
	'.mjs': 'javascript',
	'.css': 'css',
	'.md': 'markdown',
	'.json': 'json',
	'.svg': 'xml',
	'.html': 'html',
	'.txt': 'plaintext'
};

/** The Monaco language id for a file. */
export function languageFor(file: string): string {
	return LANGUAGE_BY_EXTENSION[extensionOf(file)] ?? 'plaintext';
}
