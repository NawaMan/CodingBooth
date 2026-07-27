// codeDiffCore — the pure, total line-diff engine behind <CodeDiff>.
//
// Same discipline as drawCore / videoCore / tabsCore / qrCore: every function is
// total, so junk input (a null string, a lone marker, two versions that share
// nothing, a 10 000-line paste) yields a sane DiffLine[] — never a throw and never
// an out-of-range read. All the arithmetic that decides what a line IS lives here,
// so the component stays declarative and this logic is unit-tested without a DOM.
//
// A CodeDiff is authored one of two ways, and both land on the same DiffLine[]:
//   • `diffLines(before, after)` — hand it two versions and it computes the diff
//     (LCS over lines), so the author keeps no bookkeeping.
//   • `parseDiff(src)` — hand it a git-style `+`/`-`/space-prefixed block for exact
//     control over which lines read as added / removed / context.

/** Whether a line was added, removed, or is unchanged context around the change. */
export type DiffType = 'add' | 'del' | 'context';

/** One rendered row of a diff. `oldNo`/`newNo` are 1-based line numbers in the
    before/after files, or null where the line does not exist on that side (an
    added line has no old number; a removed line has no new number). */
export interface DiffLine {
	type: DiffType;
	text: string;
	oldNo: number | null;
	newNo: number | null;
}

/** Coerce anything to a string of lines. `null`/`undefined` → '', so a missing
    prop is an empty file rather than the literal word "undefined". A single
    trailing newline is dropped so `"a\n"` is one line, not two — the same shape a
    text editor shows and the shape Shiki tokenises to. */
function toLines(src: unknown): string[] {
	if (src === null || src === undefined) return [];
	const text = String(src);
	if (text === '') return [];
	const lines = text.split('\n');
	if (lines.length > 1 && lines[lines.length - 1] === '') lines.pop();
	return lines;
}

/** Number a finished list of typed rows: context advances both counters, an add
    advances only the new side, a del only the old side. Mutates and returns the
    same array (it is freshly built by every caller). */
function number(rows: Array<{ type: DiffType; text: string }>): DiffLine[] {
	let oldNo = 0;
	let newNo = 0;
	return rows.map((r) => {
		if (r.type === 'del') return { ...r, oldNo: ++oldNo, newNo: null };
		if (r.type === 'add') return { ...r, oldNo: null, newNo: ++newNo };
		return { ...r, oldNo: ++oldNo, newNo: ++newNo };
	});
}

// Above this many lines on either side the O(n·m) LCS table is skipped for a cheap
// prefix/suffix + block-replace diff. Real code slides are dozens of lines; this is
// only a guard so a pathological paste degrades to a coarse-but-correct diff instead
// of allocating a huge matrix — totality never depends on the input size.
const LCS_MAX = 600;

/** Longest-common-subsequence over two line arrays, returned as pairs of matched
    indices (i in `a`, j in `b`), in order. The classic DP; kept private because a
    caller only ever wants the diff built on top of it. */
function lcsPairs(a: string[], b: string[]): Array<[number, number]> {
	const n = a.length;
	const m = b.length;
	// dp[i][j] = LCS length of a[i..] and b[j..]. One extra row/col of zeros.
	const dp: number[][] = Array.from({ length: n + 1 }, () => new Array(m + 1).fill(0));
	for (let i = n - 1; i >= 0; i--) {
		for (let j = m - 1; j >= 0; j--) {
			dp[i][j] = a[i] === b[j] ? dp[i + 1][j + 1] + 1 : Math.max(dp[i + 1][j], dp[i][j + 1]);
		}
	}
	const pairs: Array<[number, number]> = [];
	let i = 0;
	let j = 0;
	while (i < n && j < m) {
		if (a[i] === b[j]) {
			pairs.push([i, j]);
			i++;
			j++;
		} else if (dp[i + 1][j] >= dp[i][j + 1]) {
			i++;
		} else {
			j++;
		}
	}
	return pairs;
}

/**
 * Diff two versions of a file, line by line, into typed + numbered rows.
 *
 * Common lines become `context`, lines only in `before` become `del`, lines only
 * in `after` become `add`, emitted in reading order (each del/add block sits where
 * the change is, deletions before insertions). Total: either side may be
 * empty/null; identical inputs give all-context; disjoint inputs give every old
 * line as del then every new line as add.
 */
export function diffLines(before: unknown, after: unknown): DiffLine[] {
	const a = toLines(before);
	const b = toLines(after);

	// Trim the shared head and tail first: those are always context, and stripping
	// them shrinks (usually empties) the quadratic core for the common "a few lines
	// changed in the middle" case.
	let head = 0;
	while (head < a.length && head < b.length && a[head] === b[head]) head++;
	let tail = 0;
	while (
		tail < a.length - head &&
		tail < b.length - head &&
		a[a.length - 1 - tail] === b[b.length - 1 - tail]
	) {
		tail++;
	}

	const aMid = a.slice(head, a.length - tail);
	const bMid = b.slice(head, b.length - tail);

	const rows: Array<{ type: DiffType; text: string }> = [];
	for (let k = 0; k < head; k++) rows.push({ type: 'context', text: a[k] });

	if (aMid.length === 0) {
		for (const t of bMid) rows.push({ type: 'add', text: t });
	} else if (bMid.length === 0) {
		for (const t of aMid) rows.push({ type: 'del', text: t });
	} else if (aMid.length > LCS_MAX || bMid.length > LCS_MAX) {
		// Guard path: too big for the DP table — emit the whole changed middle as a
		// delete block followed by an insert block. Coarse, but correct and total.
		for (const t of aMid) rows.push({ type: 'del', text: t });
		for (const t of bMid) rows.push({ type: 'add', text: t });
	} else {
		const pairs = lcsPairs(aMid, bMid);
		let ai = 0;
		let bi = 0;
		for (const [pi, pj] of pairs) {
			for (; ai < pi; ai++) rows.push({ type: 'del', text: aMid[ai] });
			for (; bi < pj; bi++) rows.push({ type: 'add', text: bMid[bi] });
			rows.push({ type: 'context', text: aMid[pi] });
			ai = pi + 1;
			bi = pj + 1;
		}
		for (; ai < aMid.length; ai++) rows.push({ type: 'del', text: aMid[ai] });
		for (; bi < bMid.length; bi++) rows.push({ type: 'add', text: bMid[bi] });
	}

	for (let k = b.length - tail; k < b.length; k++) rows.push({ type: 'context', text: b[k] });
	return number(rows);
}

/**
 * Parse a git-style unified block into typed + numbered rows. Each line's FIRST
 * character is the marker — `+` add, `-` del, space (or anything else) context —
 * and it is stripped from the text. A fully empty line is blank context. This is
 * the "I'll say exactly what changed" authoring path; the marker set matches what
 * `git diff` prints, minus the `@@` hunk headers.
 *
 * Total: a null/empty source is no rows; a marker with nothing after it is that
 * marker on an empty line, never a throw.
 */
export function parseDiff(src: unknown): DiffLine[] {
	if (src === null || src === undefined) return [];
	const text = String(src);
	if (text === '') return [];
	const raw = text.split('\n');
	if (raw.length > 1 && raw[raw.length - 1] === '') raw.pop();
	const rows = raw.map((line) => {
		const marker = line.charAt(0);
		if (marker === '+') return { type: 'add' as const, text: line.slice(1) };
		if (marker === '-') return { type: 'del' as const, text: line.slice(1) };
		// A leading space is the diff convention for context; strip exactly one so
		// unchanged lines keep their real indentation.
		return { type: 'context' as const, text: marker === ' ' ? line.slice(1) : line };
	});
	return number(rows);
}

/** How many lines each type contributes — used for a summary chip (e.g. "+3 −1")
    and to let the component skip work when there is nothing added or removed. */
export function diffStats(lines: DiffLine[]): { added: number; removed: number; context: number } {
	let added = 0;
	let removed = 0;
	let context = 0;
	for (const l of lines) {
		if (l.type === 'add') added++;
		else if (l.type === 'del') removed++;
		else context++;
	}
	return { added, removed, context };
}

/** The gutter glyph for a line type: `+` / `−` (a true minus, not a hyphen) /
    a hair space for context so the column stays a fixed width. */
export function signOf(type: DiffType): string {
	if (type === 'add') return '+';
	if (type === 'del') return '−';
	return ' ';
}
