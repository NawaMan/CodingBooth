import * as path from 'node:path';
import { parse } from 'svelte/compiler';

// Which FILE a Block was written in — so ADJUST's SAVE can follow a Block out of
// the slide's +page.svelte into the component that holds it (a shared scene, say).
//
// The browser cannot know where a tag was authored: a Block in CameraScene.svelte
// and one in the slide look identical once mounted, and Svelte context can't tell
// either — slot content sees the context of the component that RENDERS the slot,
// not the file that wrote it. So the dev server says it at compile time instead:
// every Block-family tag in a route file gets `__file="<that file>"` stamped on
// before Svelte sees the source. The Block reports it with its change, and the
// save endpoint patches that file. Dev-only, like every other write here; a built
// deck carries no stamp and has no endpoint.
//
// Server-side (node) code: parse() is svelte/compiler, so never import this from
// a component.

/** The tags that report themselves to ADJUST's change registry. */
export const STAMPED_TAGS = ['Block', 'ImageBlock', 'TextBlock', 'SvgBlock'];

/** The prop a stamp rides in. Block declares it; the wrappers forward it. */
export const FILE_PROP = '__file';

type Node = { type?: string; name?: string; start?: number; [key: string]: unknown };

/** Insert `__file="file"` into every STAMPED_TAGS opening tag of the markup.
    Tags inside the script (a code sample in a string) are left alone — only
    markup is parsed. A tag that already carries the prop, or source that doesn't
    parse, is left exactly as it was: the stamp is a convenience, never a reason
    to fail a compile. */
export function stampSourceFile(code: string, file: string, tags: string[] = STAMPED_TAGS): string {
	let ast: { html?: Node };
	try {
		ast = parse(code) as unknown as { html?: Node };
	} catch {
		return code;
	}
	const wanted = new Set(tags);
	const at: number[] = [];
	const walk = (node: unknown) => {
		if (!node || typeof node !== 'object') return;
		if (Array.isArray(node)) {
			for (const n of node) walk(n);
			return;
		}
		const n = node as Node;
		if (n.type === 'InlineComponent' && n.name && wanted.has(n.name) && typeof n.start === 'number') {
			const open = `<${n.name}`;
			const stamped = Array.isArray(n.attributes) && n.attributes.some((a) => (a as Node).name === FILE_PROP);
			if (code.startsWith(open, n.start) && !stamped) at.push(n.start + open.length);
		}
		for (const [key, value] of Object.entries(n)) {
			if (key !== 'start' && key !== 'end') walk(value);
		}
	};
	walk(ast.html);
	if (!at.length) return code;
	const attr = ` ${FILE_PROP}=${JSON.stringify(file)}`;
	let out = code;
	// Back to front, so each insert leaves the earlier offsets valid.
	for (const i of at.sort((a, b) => b - a)) out = out.slice(0, i) + attr + out.slice(i);
	return out;
}

/** The root-relative path a module id is stamped with, or null when the file
    isn't a component under src/routes (a $lib component's tags belong to whoever
    uses it, and a `?raw` import is the bytes, not the module). */
export function stampPath(id: string, root: string): string | null {
	if (id.includes('?') || !id.endsWith('.svelte')) return null;
	const rel = path.relative(root, id).split(path.sep).join('/');
	return rel.startsWith('src/routes/') ? rel : null;
}

/** Resolve a stamp the BROWSER sent back into a file the save endpoint may
    write: root-relative, a .svelte file, inside src/routes — the same fence the
    route → +page.svelte mapping keeps. Anything else is null, never a guess. */
export function resolveStampedFile(stamp: string, root: string): string | null {
	if (typeof stamp !== 'string' || !stamp || path.isAbsolute(stamp) || stamp.includes('\0')) return null;
	if (!stamp.endsWith('.svelte')) return null;
	const routes = path.resolve(root, 'src/routes');
	const file = path.resolve(root, stamp);
	return file.startsWith(routes + path.sep) ? file : null;
}
