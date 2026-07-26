// The QR encoder behind <QRCode>: text in, a matrix of dark/light modules out.
//
// Written from the spec (ISO/IEC 18004) rather than pulled from npm, because a
// slide QR is a handful of tables and some GF(256) arithmetic — and because a
// dependency here would buy nothing a `qrencode` shell-out (utils/prepare-youtube.sh)
// doesn't already buy, while costing the deck its no-dep grain.
//
// Kept pure and DOM-free (drawCore / connectorCore / videoCore / kbdCore
// discipline), so the component is left with nothing but an <svg>, and so the
// interesting cases — a payload one byte too long, a junk mask, a version that
// cannot hold the text — are testable without a browser.
//
// Every exported function is total: bad input yields `null` or a safe default,
// never a throw. A slide must not collapse because someone pasted a 3000-character
// URL.
//
// BYTE MODE ONLY. The spec's numeric and alphanumeric modes pack denser, but
// alphanumeric excludes lowercase, so a real URL (`https://geekpresent.dev/talk`)
// falls out of it on the first lowercase letter and lands back in byte mode
// anyway. One mode encodes anything, in UTF-8, and needs no segmentation pass to
// decide. A QR on a slide is read by a phone at four metres; the versions this
// saves are not the ones that matter.

/** Error-correction level: how much of the symbol may be obscured and still scan. */
export type Ecc = 'L' | 'M' | 'Q' | 'H';

/** A finished symbol. `modules[y][x]` is true where the module is dark. */
export interface QrMatrix {
	/** 1–40. The symbol is `size` × `size` modules, `size = version * 4 + 17`. */
	version: number;
	ecc: Ecc;
	/** The data mask actually applied, 0–7 (auto-chosen unless pinned). */
	mask: number;
	size: number;
	modules: boolean[][];
}

export interface QrOptions {
	/** Error correction. Defaults to 'M' — a slide QR is clean, not a shipping label. */
	ecc?: Ecc;
	/** Smallest version to consider (1–40). Raise it to hold a size across payloads. */
	minVersion?: number;
	/** Largest version to consider (1–40). Beyond it, `encodeQr` gives up and returns null. */
	maxVersion?: number;
	/** Pin the data mask (0–7). Anything else — including null — picks by penalty score. */
	mask?: number | null;
}

const MIN_VERSION = 1;
const MAX_VERSION = 40;

const ECC_LEVELS: readonly Ecc[] = ['L', 'M', 'Q', 'H'];

/** The 2-bit field a format string carries. Deliberately NOT the L<M<Q<H order. */
const ECC_FORMAT_BITS: Record<Ecc, number> = { L: 1, M: 0, Q: 3, H: 2 };

// The two tables the spec cannot derive: how a version's error-correction budget is
// split into blocks. Their PRODUCT (ecc-per-block × blocks) is pinned by the
// published byte-mode capacity table, and the split itself by the golden matrices —
// interleaving reorders the codewords, so a wrong split scrambles the symbol.
// Index by version; slot 0 is unused.
const ECC_CODEWORDS_PER_BLOCK: Record<Ecc, readonly number[]> = {
	L: [-1, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
	M: [-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28],
	Q: [-1, 13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26, 30, 28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
	H: [-1, 17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26, 28, 30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
};

const NUM_ERROR_CORRECTION_BLOCKS: Record<Ecc, readonly number[]> = {
	L: [-1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25],
	M: [-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49],
	Q: [-1, 1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21, 20, 23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68],
	H: [-1, 1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25, 25, 34, 30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74, 77, 81],
};

/** Clamp anything to an integer in [lo, hi]; junk yields `fallback`. */
function clampInt(value: unknown, lo: number, hi: number, fallback: number): number {
	if (typeof value !== 'number' || !Number.isFinite(value)) return fallback;
	const n = Math.trunc(value);
	return n < lo ? lo : n > hi ? hi : n;
}

/** Normalize an author's `ecc` prop. An unknown level is 'M', not a throw. */
export function normalizeEcc(ecc: unknown): Ecc {
	return typeof ecc === 'string' && (ECC_LEVELS as readonly string[]).includes(ecc.toUpperCase())
		? (ecc.toUpperCase() as Ecc)
		: 'M';
}

/**
 * UTF-8 bytes for a string, written out rather than delegated to `TextEncoder`.
 *
 * Not because the global is unavailable — it is, in a browser and in Node — but
 * because this module promises to be pure and environment-free, and fifteen lines
 * of well-understood bit-shuffling is a smaller thing to own than a caveat.
 *
 * Lone surrogates (a broken `\uD800` a slide pasted from somewhere) encode as
 * U+FFFD rather than emitting invalid UTF-8 that no scanner could decode.
 */
export function toUtf8Bytes(text: string): number[] {
	const bytes: number[] = [];
	for (let i = 0; i < text.length; i++) {
		let code = text.charCodeAt(i);

		if (code >= 0xd800 && code <= 0xdbff) {
			const low = text.charCodeAt(i + 1);
			if (low >= 0xdc00 && low <= 0xdfff) {
				code = 0x10000 + ((code - 0xd800) << 10) + (low - 0xdc00);
				i++;
			} else {
				code = 0xfffd;
			}
		} else if (code >= 0xdc00 && code <= 0xdfff) {
			code = 0xfffd;
		}

		if (code < 0x80) {
			bytes.push(code);
		} else if (code < 0x800) {
			bytes.push(0xc0 | (code >>> 6), 0x80 | (code & 0x3f));
		} else if (code < 0x10000) {
			bytes.push(0xe0 | (code >>> 12), 0x80 | ((code >>> 6) & 0x3f), 0x80 | (code & 0x3f));
		} else {
			bytes.push(
				0xf0 | (code >>> 18),
				0x80 | ((code >>> 12) & 0x3f),
				0x80 | ((code >>> 6) & 0x3f),
				0x80 | (code & 0x3f),
			);
		}
	}
	return bytes;
}

/**
 * Total module positions available to data + ECC codewords, in BITS.
 *
 * The whole symbol, minus the function patterns that never carry data. The
 * remainder bits (up to 7, which no codeword claims) are still counted here —
 * `Math.floor(… / 8)` is what turns this into codewords.
 */
function numRawDataModules(version: number): number {
	let result = (16 * version + 128) * version + 64;
	if (version >= 2) {
		const numAlign = Math.floor(version / 7) + 2;
		result -= (25 * numAlign - 10) * numAlign - 55;
		if (version >= 7) result -= 36; // the two 6×3 version-information blocks
	}
	return result;
}

/** Codewords left for the message once this version+level has paid for its ECC. */
export function numDataCodewords(version: number, ecc: Ecc): number {
	return (
		Math.floor(numRawDataModules(version) / 8) -
		ECC_CODEWORDS_PER_BLOCK[ecc][version] * NUM_ERROR_CORRECTION_BLOCKS[ecc][version]
	);
}

/** Bits the character-count field occupies in byte mode: 8 up to v9, 16 from v10. */
function countBits(version: number): number {
	return version <= 9 ? 8 : 16;
}

/**
 * How many UTF-8 bytes this version+level can carry in byte mode.
 *
 * The mode indicator (4 bits) and the count field come out of the data budget
 * first; what remains, floored to whole bytes, is the payload.
 */
export function byteCapacity(version: number, ecc: Ecc): number {
	const bits = numDataCodewords(version, ecc) * 8 - 4 - countBits(version);
	return bits < 0 ? 0 : Math.floor(bits / 8);
}

/** The smallest version in [min, max] that holds `length` bytes, or null if none does. */
export function chooseVersion(length: number, ecc: Ecc, min: number, max: number): number | null {
	for (let version = min; version <= max; version++) {
		if (byteCapacity(version, ecc) >= length) return version;
	}
	return null;
}

// ── GF(256) ─────────────────────────────────────────────────────────────────
// Reed-Solomon over the field the spec names: modulo x^8 + x^4 + x^3 + x^2 + 1
// (0x11D), generated by α = 2.

/** Multiply in GF(256). Russian-peasant, reducing as it goes — no log tables to seed. */
function gfMultiply(x: number, y: number): number {
	let z = 0;
	for (let i = 7; i >= 0; i--) {
		z = (z << 1) ^ ((z >>> 7) * 0x11d);
		z ^= ((y >>> i) & 1) * x;
	}
	return z & 0xff;
}

/** Coefficients of the divisor polynomial (x−α^0)(x−α^1)…(x−α^(degree−1)), high term implicit. */
function rsGeneratorPoly(degree: number): number[] {
	const result = new Array<number>(degree).fill(0);
	result[degree - 1] = 1;
	let root = 1;
	for (let i = 0; i < degree; i++) {
		for (let j = 0; j < degree; j++) {
			result[j] = gfMultiply(result[j], root);
			if (j + 1 < degree) result[j] ^= result[j + 1];
		}
		root = gfMultiply(root, 0x02);
	}
	return result;
}

/** The ECC codewords for one block: `data` divided by the generator, remainder kept. */
function rsRemainder(data: readonly number[], generator: readonly number[]): number[] {
	const result = new Array<number>(generator.length).fill(0);
	for (const b of data) {
		const factor = b ^ (result.shift() as number);
		result.push(0);
		for (let i = 0; i < generator.length; i++) result[i] ^= gfMultiply(generator[i], factor);
	}
	return result;
}

/**
 * Split the message into blocks, give each its ECC, then interleave the lot.
 *
 * Interleaving is what makes the error correction worth having: a scuff on the
 * printed symbol lands a few codewords into *every* block rather than wiping one
 * block out entirely. Short blocks come first and are one codeword lighter than
 * the long ones — the spec's own way of spending a data budget that does not
 * divide evenly.
 */
function addEccAndInterleave(data: readonly number[], version: number, ecc: Ecc): number[] {
	const numBlocks = NUM_ERROR_CORRECTION_BLOCKS[ecc][version];
	const blockEccLen = ECC_CODEWORDS_PER_BLOCK[ecc][version];
	const rawCodewords = Math.floor(numRawDataModules(version) / 8);
	const numShortBlocks = numBlocks - (rawCodewords % numBlocks);
	const shortBlockLen = Math.floor(rawCodewords / numBlocks);

	const generator = rsGeneratorPoly(blockEccLen);
	const blocks: Array<{ data: number[]; ecc: number[] }> = [];

	for (let i = 0, k = 0; i < numBlocks; i++) {
		const dataLen = shortBlockLen - blockEccLen + (i < numShortBlocks ? 0 : 1);
		const dat = data.slice(k, k + dataLen);
		k += dataLen;
		blocks.push({ data: dat, ecc: rsRemainder(dat, generator) });
	}

	const result: number[] = [];
	// Data columns: the extra codeword of every long block lands in the last pass,
	// where the short blocks have nothing left to contribute.
	for (let i = 0; i < shortBlockLen - blockEccLen + 1; i++) {
		for (const block of blocks) if (i < block.data.length) result.push(block.data[i]);
	}
	// Then the ECC columns, which every block has in equal measure.
	for (let i = 0; i < blockEccLen; i++) {
		for (const block of blocks) result.push(block.ecc[i]);
	}
	return result;
}

// ── Symbol construction ─────────────────────────────────────────────────────

/** Centre coordinates of the alignment patterns, on both axes. Empty for version 1. */
export function alignmentPatternPositions(version: number): number[] {
	if (version === 1) return [];
	const numAlign = Math.floor(version / 7) + 2;
	// Version 32 is the spec's one irregularity: the derived step would be 28, and
	// the published table says 26. Everywhere else the run is even and this holds.
	const step =
		version === 32
			? 26
			: Math.floor((version * 4 + numAlign * 2 + 1) / (numAlign * 2 - 2)) * 2;

	const result: number[] = [6];
	// Filled from the far edge inward, so any slack in the spacing falls in the FIRST
	// gap (next to the top-left finder) rather than being smeared across all of them.
	for (let pos = version * 4 + 10; result.length < numAlign; pos -= step) result.splice(1, 0, pos);
	return result;
}

/** The 15-bit format string: level + mask, BCH(15,5)-protected, then XOR-masked. */
export function formatBits(ecc: Ecc, mask: number): number {
	const data = (ECC_FORMAT_BITS[ecc] << 3) | mask;
	let rem = data;
	for (let i = 0; i < 10; i++) rem = (rem << 1) ^ ((rem >>> 9) * 0x537);
	// The XOR keeps an all-zero level+mask from producing an all-zero format string,
	// which would be indistinguishable from a blank region.
	return ((data << 10) | rem) ^ 0x5412;
}

/** The 18-bit version string (versions 7+ only): version + BCH(18,6). */
export function versionBits(version: number): number {
	let rem = version;
	for (let i = 0; i < 12; i++) rem = (rem << 1) ^ ((rem >>> 11) * 0x1f25);
	return (version << 12) | rem;
}

/** The eight data masks, as predicates on a module's position. */
const MASK_FUNCTIONS: ReadonlyArray<(x: number, y: number) => boolean> = [
	(x, y) => (x + y) % 2 === 0,
	(_x, y) => y % 2 === 0,
	(x) => x % 3 === 0,
	(x, y) => (x + y) % 3 === 0,
	(x, y) => (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0,
	(x, y) => ((x * y) % 2) + ((x * y) % 3) === 0,
	(x, y) => (((x * y) % 2) + ((x * y) % 3)) % 2 === 0,
	(x, y) => (((x + y) % 2) + ((x * y) % 3)) % 2 === 0,
];

type Grid = boolean[][];

function blankGrid(size: number): Grid {
	return Array.from({ length: size }, () => new Array<boolean>(size).fill(false));
}

/**
 * Draw everything a scanner locates the symbol by, and reserve what it reads first.
 *
 * `isFunction` is the real output here alongside the modules: it is what keeps the
 * data stream from overwriting a finder, and what keeps the mask from flipping one.
 */
function drawFunctionPatterns(modules: Grid, isFunction: Grid, version: number, size: number): void {
	const setFn = (x: number, y: number, dark: boolean) => {
		modules[y][x] = dark;
		isFunction[y][x] = true;
	};

	// Timing patterns: the alternating spine every scanner counts modules against.
	for (let i = 0; i < size; i++) {
		setFn(6, i, i % 2 === 0);
		setFn(i, 6, i % 2 === 0);
	}

	// Finders, drawn with their separators (the light ring at Chebyshev distance 4).
	for (const [cx, cy] of [
		[3, 3],
		[size - 4, 3],
		[3, size - 4],
	]) {
		for (let dy = -4; dy <= 4; dy++) {
			for (let dx = -4; dx <= 4; dx++) {
				const dist = Math.max(Math.abs(dx), Math.abs(dy));
				const x = cx + dx;
				const y = cy + dy;
				if (x >= 0 && x < size && y >= 0 && y < size) setFn(x, y, dist !== 2 && dist !== 4);
			}
		}
	}

	// Alignment patterns, at every crossing of the position list except the three
	// corners already occupied by a finder.
	const positions = alignmentPatternPositions(version);
	const last = positions.length - 1;
	for (let i = 0; i <= last; i++) {
		for (let j = 0; j <= last; j++) {
			if ((i === 0 && j === 0) || (i === 0 && j === last) || (i === last && j === 0)) continue;
			for (let dy = -2; dy <= 2; dy++) {
				for (let dx = -2; dx <= 2; dx++) {
					setFn(positions[j] + dx, positions[i] + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1);
				}
			}
		}
	}

	// Reserve the format area (drawn for real once the mask is known) and, from
	// version 7, the version blocks — which depend on nothing but the version.
	drawFormatBits(modules, isFunction, size, 'M', 0);
	if (version >= 7) drawVersionBits(modules, isFunction, size, version);
}

/** The two copies of the format string, around the finders. */
function drawFormatBits(modules: Grid, isFunction: Grid, size: number, ecc: Ecc, mask: number): void {
	const bits = formatBits(ecc, mask);
	const bit = (i: number) => ((bits >>> i) & 1) !== 0;
	const setFn = (x: number, y: number, dark: boolean) => {
		modules[y][x] = dark;
		isFunction[y][x] = true;
	};

	// First copy: down the left of the top-left finder, then right along its bottom.
	// The two jogs skip the timing pattern at index 6.
	for (let i = 0; i <= 5; i++) setFn(8, i, bit(i));
	setFn(8, 7, bit(6));
	setFn(8, 8, bit(7));
	setFn(7, 8, bit(8));
	for (let i = 9; i < 15; i++) setFn(14 - i, 8, bit(i));

	// Second copy: split across the other two finders, so a symbol torn in half at
	// one corner still yields a readable format string from the other.
	for (let i = 0; i < 8; i++) setFn(size - 1 - i, 8, bit(i));
	for (let i = 8; i < 15; i++) setFn(8, size - 15 + i, bit(i));

	setFn(8, size - 8, true); // the dark module — always set, in every symbol
}

/** The two 6×3 version blocks, above the bottom-left finder and left of the top-right. */
function drawVersionBits(modules: Grid, isFunction: Grid, size: number, version: number): void {
	const bits = versionBits(version);
	for (let i = 0; i < 18; i++) {
		const dark = ((bits >>> i) & 1) !== 0;
		const a = size - 11 + (i % 3);
		const b = Math.floor(i / 3);
		modules[b][a] = dark;
		isFunction[b][a] = true;
		modules[a][b] = dark;
		isFunction[a][b] = true;
	}
}

/**
 * Lay the codeword bits into the symbol.
 *
 * Two modules wide, snaking bottom-to-top then top-to-bottom, right to left,
 * stepping over column 6 (the vertical timing pattern) rather than counting it as
 * a column. Function modules are skipped, not overwritten. Any leftover remainder
 * modules keep their light default — no codeword owns them.
 */
function drawCodewords(modules: Grid, isFunction: Grid, size: number, data: readonly number[]): void {
	let i = 0; // bit index into `data`
	for (let right = size - 1; right >= 1; right -= 2) {
		if (right === 6) right = 5;
		for (let vert = 0; vert < size; vert++) {
			for (let j = 0; j < 2; j++) {
				const x = right - j;
				const upward = ((right + 1) & 2) === 0;
				const y = upward ? size - 1 - vert : vert;
				if (!isFunction[y][x] && i < data.length * 8) {
					modules[y][x] = ((data[i >>> 3] >>> (7 - (i & 7))) & 1) !== 0;
					i++;
				}
			}
		}
	}
}

/** XOR the mask pattern over every module the function patterns did not claim. */
function applyMask(modules: Grid, isFunction: Grid, size: number, mask: number): void {
	const fn = MASK_FUNCTIONS[mask];
	for (let y = 0; y < size; y++) {
		for (let x = 0; x < size; x++) {
			if (!isFunction[y][x] && fn(x, y)) modules[y][x] = !modules[y][x];
		}
	}
}

// The spec's four penalty weights (ISO/IEC 18004 §8.8.2, Table 24). A mask is chosen
// to minimize their sum, which is a proxy for "hard to mistake any part of this
// symbol for a finder pattern, and hard to lose your place while scanning it".
const PENALTY_N1 = 3;
const PENALTY_N2 = 3;
const PENALTY_N3 = 40;
const PENALTY_N4 = 10;

interface Run {
	dark: boolean;
	length: number;
}

/** One row or column as its runs of like-coloured modules. */
function runsOf(line: readonly boolean[]): Run[] {
	const runs: Run[] = [];
	for (const dark of line) {
		const last = runs[runs.length - 1];
		if (last && last.dark === dark) last.length++;
		else runs.push({ dark, length: 1 });
	}
	return runs;
}

/**
 * Score one row or column: rule 1 (long same-colour runs) and rule 3 (finder-alikes).
 *
 * Rule 3 hunts the finder's own 1:1:3:1:1 signature — dark:light:dark:light:dark —
 * **at any scale**, not just the 11-module version. A run of 6 dark flanked by 2s is
 * as misleading to a scanner as a run of 3 flanked by 1s, since a scanner reads
 * ratios, not module counts. So the centre dark run supplies the unit (`length / 3`)
 * and the other four runs must match it.
 *
 * The spec asks for four light modules "preceding OR following" the pattern — one
 * penalty per occurrence, not one per satisfied side. And the quiet zone beyond the
 * symbol's edge is light by definition and at least four modules wide, so a pattern
 * that runs into the border counts as flanked. (Both readings matter: they are where
 * conforming encoders diverge, and why two of them may pick different masks for the
 * same text. Harmless — the chosen mask is recorded in the format bits, so a decoder
 * never has to agree with us, only read us.)
 */
function penaltyLine(line: readonly boolean[]): number {
	let score = 0;
	const runs = runsOf(line);

	for (const run of runs) {
		if (run.length >= 5) score += PENALTY_N1 + (run.length - 5);
	}

	// The centre of a finder-alike needs two runs either side, so it can never be the
	// first or last two runs of the line.
	for (let i = 2; i <= runs.length - 3; i++) {
		const centre = runs[i];
		if (!centre.dark || centre.length % 3 !== 0) continue;

		const unit = centre.length / 3;
		if (
			runs[i - 1].length !== unit ||
			runs[i - 2].length !== unit ||
			runs[i + 1].length !== unit ||
			runs[i + 2].length !== unit
		) {
			continue;
		}

		// Off the end of the line is the quiet zone: light, and wide enough.
		const before = i - 3 >= 0 ? runs[i - 3].length : Infinity;
		const after = i + 3 < runs.length ? runs[i + 3].length : Infinity;
		if (before >= 4 * unit || after >= 4 * unit) score += PENALTY_N3;
	}

	return score;
}

/** The spec's four rules, summed. Lower is better; this is the only thing choosing a mask. */
export function penaltyScore(modules: Grid, size: number): number {
	let score = 0;

	for (let y = 0; y < size; y++) score += penaltyLine(modules[y]);
	for (let x = 0; x < size; x++) {
		const column = new Array<boolean>(size);
		for (let y = 0; y < size; y++) column[y] = modules[y][x];
		score += penaltyLine(column);
	}

	// Rule 2: every 2×2 block of one colour, counted once per top-left corner.
	for (let y = 0; y < size - 1; y++) {
		for (let x = 0; x < size - 1; x++) {
			const c = modules[y][x];
			if (c === modules[y][x + 1] && c === modules[y + 1][x] && c === modules[y + 1][x + 1]) {
				score += PENALTY_N2;
			}
		}
	}

	// Rule 4: drift away from a 50/50 dark ratio, in whole 5% steps. Both divisions
	// are integer, per the spec — a symbol at 52% dark is not penalized at all.
	let dark = 0;
	for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) if (modules[y][x]) dark++;
	const percent = Math.floor((100 * dark) / (size * size));
	score += Math.floor(Math.abs(percent - 50) / 5) * PENALTY_N4;

	return score;
}

/**
 * Encode `text` as a QR symbol, or `null` if it cannot be done.
 *
 * `null` — not a throw and not a blank grid — is the answer for an empty string, a
 * non-string, and a payload too long for `maxVersion`. The component renders
 * nothing at all in that case, because a QR that encodes nothing is a square of
 * noise the audience will point a phone at.
 */
export function encodeQr(text: unknown, options: QrOptions = {}): QrMatrix | null {
	if (typeof text !== 'string' || text.length === 0) return null;

	const ecc = normalizeEcc(options.ecc);
	const minVersion = clampInt(options.minVersion, MIN_VERSION, MAX_VERSION, MIN_VERSION);
	const maxVersion = clampInt(options.maxVersion, minVersion, MAX_VERSION, MAX_VERSION);

	const bytes = toUtf8Bytes(text);
	const version = chooseVersion(bytes.length, ecc, minVersion, maxVersion);
	if (version === null) return null;

	// ── the bit stream: mode, count, payload, terminator, padding ──
	const bits: number[] = [];
	const appendBits = (value: number, length: number) => {
		for (let i = length - 1; i >= 0; i--) bits.push((value >>> i) & 1);
	};

	appendBits(0x4, 4); // byte mode
	appendBits(bytes.length, countBits(version));
	for (const b of bytes) appendBits(b, 8);

	const dataCapacityBits = numDataCodewords(version, ecc) * 8;
	appendBits(0, Math.min(4, dataCapacityBits - bits.length)); // terminator
	appendBits(0, (8 - (bits.length % 8)) % 8); // pad to a whole codeword

	// The two alternating pad codewords the spec names. Their only job is to fill
	// the symbol with something that does not look like a finder.
	for (let pad = 0xec; bits.length < dataCapacityBits; pad ^= 0xec ^ 0x11) appendBits(pad, 8);

	const dataCodewords: number[] = [];
	for (let i = 0; i < bits.length; i += 8) {
		let codeword = 0;
		for (let j = 0; j < 8; j++) codeword = (codeword << 1) | bits[i + j];
		dataCodewords.push(codeword);
	}

	// ── the symbol ──
	const allCodewords = addEccAndInterleave(dataCodewords, version, ecc);
	const size = version * 4 + 17;
	const modules = blankGrid(size);
	const isFunction = blankGrid(size);

	drawFunctionPatterns(modules, isFunction, version, size);
	drawCodewords(modules, isFunction, size, allCodewords);

	// ── the mask ──
	const pinned = clampInt(options.mask, 0, 7, -1);
	let mask = pinned;
	if (mask < 0) {
		let best = Infinity;
		for (let candidate = 0; candidate < 8; candidate++) {
			applyMask(modules, isFunction, size, candidate);
			drawFormatBits(modules, isFunction, size, ecc, candidate);
			const score = penaltyScore(modules, size);
			if (score < best) {
				best = score;
				mask = candidate;
			}
			applyMask(modules, isFunction, size, candidate); // XOR is its own inverse
		}
	}

	applyMask(modules, isFunction, size, mask);
	drawFormatBits(modules, isFunction, size, ecc, mask);

	return { version, ecc, mask, size, modules };
}

/**
 * The dark modules as one SVG path, in module units, offset by the quiet zone.
 *
 * Horizontal runs are merged into a single rectangle each, which turns a version-10
 * symbol from ~1500 path commands into a few hundred. One `<path>` beats one
 * `<rect>` per module for the same reason: the browser lays out one element.
 *
 * `quiet` is the light margin, in modules, that the spec requires around the symbol
 * (four, by default) — without it a scanner cannot find the finders' outer edge.
 */
export function qrPath(matrix: QrMatrix | null, quiet: number = 4): string {
	if (!matrix) return '';
	const margin = clampInt(quiet, 0, 100, 4);
	const parts: string[] = [];

	for (let y = 0; y < matrix.size; y++) {
		let x = 0;
		while (x < matrix.size) {
			if (!matrix.modules[y][x]) {
				x++;
				continue;
			}
			let run = 1;
			while (x + run < matrix.size && matrix.modules[y][x + run]) run++;
			parts.push(`M${x + margin} ${y + margin}h${run}v1h-${run}z`);
			x += run;
		}
	}

	return parts.join('');
}

/** Total side of the rendered symbol in modules, quiet zone included. */
export function qrExtent(matrix: QrMatrix | null, quiet: number = 4): number {
	if (!matrix) return 0;
	return matrix.size + 2 * clampInt(quiet, 0, 100, 4);
}
