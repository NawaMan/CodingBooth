// Ctrl/Cmd+click on an import in the EDIT window opens the imported file (pure;
// the file-resolve endpoint in devFilePlugin.ts tries the candidates on disk).
//
// Two steps: find the module specifiers in a line (`importSpecifiersIn`, which
// also gives Monaco the ranges to underline), then turn one into project paths
// to try in order (`importCandidates`). Only LOCAL specifiers resolve — `$lib/…`
// and `./` / `../`; a package (`svelte`, `@geekpresent/core/…`) lives in
// node_modules, which the editor does not write.

import { checkEditablePath } from './fileAccessCore';

/** One quoted module specifier in a line; `start`/`end` index the text between
    the quotes (0-based, end exclusive). */
export interface SpecifierSpan {
	spec: string;
	start: number;
	end: number;
}

// A module specifier is the string right after `from`, `import` (a side-effect
// import) or `import(` — not any string on a line that mentions "import".
const BEFORE_SPECIFIER = /(?:\bfrom|\bimport)\s*\(?\s*$/;
const QUOTED = /(['"`])((?:(?!\1)[^\\\n]|\\.)*)\1/g;

/** True for a specifier this editor can follow: `$lib`, `$lib/…`, `./…`, `../…`. */
export function isLocalSpecifier(spec: string): boolean {
	return (
		spec === '$lib' || spec.startsWith('$lib/') || spec.startsWith('./') || spec.startsWith('../')
	);
}

/** Every local module specifier in `line`. A template string with `${` is not one. */
export function importSpecifiersIn(line: string): SpecifierSpan[] {
	const out: SpecifierSpan[] = [];
	for (const m of line.matchAll(QUOTED)) {
		const spec = m[2];
		if (spec.includes('${') || !isLocalSpecifier(spec)) continue;
		if (!BEFORE_SPECIFIER.test(line.slice(0, m.index))) continue;
		const start = (m.index ?? 0) + 1;
		out.push({ spec, start, end: start + spec.length });
	}
	return out;
}

/** `a/b/../c` → `a/c`. Null when the path climbs above its start. */
function normalise(path: string): string | null {
	const out: string[] = [];
	for (const seg of path.split('/')) {
		if (seg === '' || seg === '.') continue;
		if (seg === '..') {
			if (!out.length) return null;
			out.pop();
		} else out.push(seg);
	}
	return out.join('/');
}

const RESOLVE_SUFFIXES = ['.ts', '.js', '.svelte', '/index.ts', '/index.js'];

/** Editable project paths `spec` may mean, imported from `fromFile`, most likely
    first. Vite's `?raw` / `?url` and any `#hash` are dropped; a `.js` import may
    be a `.ts` file (TypeScript's ESM spelling); an extensionless one is tried with
    the usual suffixes. Empty for a package or anything outside the editable roots. */
export function importCandidates(spec: string, fromFile: string): string[] {
	const bare = spec.split('?')[0].split('#')[0];
	if (!isLocalSpecifier(bare)) return [];
	let joined: string | null;
	if (bare === '$lib' || bare.startsWith('$lib/')) {
		joined = normalise('src/lib/' + bare.slice('$lib'.length));
	} else {
		const dir = fromFile.includes('/') ? fromFile.slice(0, fromFile.lastIndexOf('/')) : '';
		joined = normalise(`${dir}/${bare}`);
	}
	if (!joined) return [];

	const tries = [joined];
	if (joined.endsWith('.js')) tries.push(joined.slice(0, -3) + '.ts');
	const last = joined.slice(joined.lastIndexOf('/') + 1);
	if (!last.includes('.')) tries.push(...RESOLVE_SUFFIXES.map((s) => joined + s));

	const out: string[] = [];
	for (const t of tries) {
		const checked = checkEditablePath(t);
		if (checked.ok && !out.includes(checked.path)) out.push(checked.path);
	}
	return out;
}
