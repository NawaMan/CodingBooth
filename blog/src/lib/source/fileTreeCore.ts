// The EDIT window's file tree and filter (pure). The server hands out a flat,
// sorted list of editable paths; the tree is built here so it can be tested.

export interface TreeNode {
	name: string;
	/** Project-relative path of this file or folder. */
	path: string;
	dir: boolean;
	children: TreeNode[];
}

/** Nest a flat list of file paths into folders. Folders first, then files, each
    alphabetical (case-insensitive). Duplicates and empty entries are ignored. */
export function buildTree(files: readonly string[]): TreeNode[] {
	const root: TreeNode = { name: '', path: '', dir: true, children: [] };
	for (const file of files) {
		if (typeof file !== 'string' || !file) continue;
		const parts = file.split('/').filter(Boolean);
		let node = root;
		parts.forEach((name, i) => {
			const path = parts.slice(0, i + 1).join('/');
			const dir = i < parts.length - 1;
			let child = node.children.find((c) => c.name === name && c.dir === dir);
			if (!child) {
				child = { name, path, dir, children: [] };
				node.children.push(child);
			}
			node = child;
		});
	}
	sortTree(root);
	return root.children;
}

function sortTree(node: TreeNode) {
	node.children.sort((a, b) =>
		a.dir !== b.dir
			? a.dir
				? -1
				: 1
			: a.name.localeCompare(b.name, undefined, { sensitivity: 'base' })
	);
	node.children.forEach(sortTree);
}

/** The folders that must be open for `file` to show: `a/b/c.ts` → `['a', 'a/b']`. */
export function ancestorsOf(file: string): string[] {
	const parts = file.split('/');
	return parts.slice(0, -1).map((_, i) => parts.slice(0, i + 1).join('/'));
}

/** One line of the tree as drawn: a node and how deep it sits. */
export interface TreeRow {
	node: TreeNode;
	depth: number;
}

/** The rows to draw: every top-level node, and the children of each folder
    whose path is in `expanded`, in order. */
export function visibleRows(tree: readonly TreeNode[], expanded: ReadonlySet<string>): TreeRow[] {
	const rows: TreeRow[] = [];
	const walk = (nodes: readonly TreeNode[], depth: number) => {
		for (const node of nodes) {
			rows.push({ node, depth });
			if (node.dir && expanded.has(node.path)) walk(node.children, depth + 1);
		}
	};
	walk(tree, 0);
	return rows;
}

/** Files whose path contains every space-separated word of `query`
    (case-insensitive), capped at `limit`. Empty query → none. */
export function filterFiles(files: readonly string[], query: string, limit = 200): string[] {
	const words = query.toLowerCase().split(/\s+/).filter(Boolean);
	if (!words.length) return [];
	const out: string[] = [];
	for (const f of files) {
		const lower = f.toLowerCase();
		if (words.every((w) => lower.includes(w))) {
			out.push(f);
			if (out.length >= limit) break;
		}
	}
	return out;
}
