import { describe, expect, it } from 'vitest';
import { patchSlideSource, type LayoutChange } from '$lib/adjust/patchSource';

const change = (over: Partial<LayoutChange> = {}): LayoutChange => ({
	kind: 'Block',
	name: undefined,
	before: { x: 100, y: 200, width: 300, height: 400 },
	after: { x: 111, y: 222, width: 333, height: 444 },
	...over
});

describe('patchSlideSource', () => {
	it('rewrites geometry in a single-line tag matched by name', () => {
		const src = `<Block name="hero" x={100} y={200} width={300} height={400}>\n  <h2>hi</h2>\n</Block>`;
		const { source, patched, unmatched } = patchSlideSource(src, [change({ name: 'hero' })]);
		expect(unmatched).toHaveLength(0);
		expect(patched).toHaveLength(1);
		expect(source).toContain('<Block name="hero" x={111} y={222} width={333} height={444}>');
	});

	it('preserves multi-line layout and other attributes', () => {
		const src = [
			'<Block',
			'  name="card"',
			'  grid={10}',
			'  x={100}',
			'  y={200}',
			'  width={300}',
			'  height={400}',
			'  bounds="none"',
			'>'
		].join('\n');
		const { source } = patchSlideSource(src, [change({ name: 'card' })]);
		expect(source).toContain('grid={10}');
		expect(source).toContain('bounds="none"');
		expect(source).toContain('x={111}');
		expect(source).toContain('height={444}');
		// Structure kept (still multi-line).
		expect(source.split('\n')).toHaveLength(9);
	});

	it('falls back to old geometry when there is no name', () => {
		const src = `<Block x={100} y={200} width={300} height={400}><p/></Block>`;
		const { source, patched } = patchSlideSource(src, [change()]);
		expect(patched).toHaveLength(1);
		expect(source).toBe(`<Block x={111} y={222} width={333} height={444}><p/></Block>`);
	});

	it('only touches the tag it matched, not siblings of the same kind', () => {
		const src =
			`<Block name="a" x={100} y={200} width={300} height={400}></Block>\n` +
			`<Block name="b" x={10} y={20} width={30} height={40}></Block>`;
		const { source } = patchSlideSource(src, [change({ name: 'a' })]);
		expect(source).toContain('<Block name="b" x={10} y={20} width={30} height={40}>');
		expect(source).toContain('<Block name="a" x={111} y={222} width={333} height={444}>');
	});

	it('refuses a tag whose twin is a code sample of ITSELF — name and geometry both match', () => {
		// A slide that documents a Block often shows the tag in a <QuickCode> sample
		// living in the SAME file. patchSlideSource scans the raw source, so a sample
		// that spells out name AND x/y/width/height is indistinguishable from the real
		// tag: two candidates, both perfect. Guessing would rewrite the SAMPLE (and
		// silently lose the author's drag), so the change comes back unmatched instead.
		// This is why every Block sample in the deck elides its geometry with `…`.
		const src = [
			'<QuickCode lang="svelte" code={`',
			'<Block name="pinned" x={100} y={200} width={300} height={400} />`} />',
			'',
			'<Block name="pinned" x={100} y={200} width={300} height={400}>real</Block>'
		].join('\n');
		const { source, patched, unmatched } = patchSlideSource(src, [change({ name: 'pinned' })]);
		expect(patched).toHaveLength(0);
		expect(unmatched).toHaveLength(1);
		expect(unmatched[0].reason).toBe('ambiguous'); // a twin TIE, and the tooltip says so
		expect(source).toBe(src); // nothing written — and above all, the SAMPLE is untouched
	});

	it('places the real tag when the code sample elides its geometry (the house convention)', () => {
		const src = [
			'<QuickCode lang="svelte" code={`',
			'<Block name="pinned" … style="left: 40px" />`} />',
			'',
			'<Block name="pinned" x={100} y={200} width={300} height={400}>real</Block>'
		].join('\n');
		const { source, patched, unmatched } = patchSlideSource(src, [change({ name: 'pinned' })]);
		expect(unmatched).toHaveLength(0);
		expect(patched).toHaveLength(1);
		expect(source).toContain('<Block name="pinned" x={111} y={222} width={333} height={444}>real</Block>');
		expect(source).toContain('<Block name="pinned" … style="left: 40px" />'); // sample untouched
	});

	it('reports unmatched changes instead of guessing', () => {
		const src = `<Block name="hero" x={100} y={200} width={300} height={400}></Block>`;
		const { unmatched, patched } = patchSlideSource(src, [change({ name: 'ghost' })]);
		expect(patched).toHaveLength(0);
		expect(unmatched).toHaveLength(1);
		expect(unmatched[0].reason).toBe('not-found'); // absent ≠ ambiguous — different fix for the author
	});

	it('does not confuse ImageBlock with Block', () => {
		const src =
			`<Block name="x" x={100} y={200} width={300} height={400}></Block>\n` +
			`<ImageBlock name="x" x={100} y={200} width={300} height={400} />`;
		const { source } = patchSlideSource(src, [
			change({ kind: 'ImageBlock', name: 'x' })
		]);
		// Block untouched, ImageBlock patched.
		expect(source).toContain('<Block name="x" x={100} y={200} width={300} height={400}>');
		expect(source).toContain('<ImageBlock name="x" x={111} y={222} width={333} height={444} />');
	});

	it('inserts a geometry attribute that was absent from the tag', () => {
		const src = `<Block name="p" x={100} y={200} width={300} />`;
		// height missing on the tag; before matches on the three present attrs is not
		// enough (geomMatches needs all four) so match by name only.
		const { source, patched } = patchSlideSource(src, [
			change({ name: 'p', before: { x: 100, y: 200, width: 300, height: 0 } })
		]);
		expect(patched).toHaveLength(1);
		expect(source).toContain('height={444}');
		expect(source).toContain('<Block name="p" x={111} y={222} width={333} height={444} />');
	});

	it('applies a literal old→new tag swap for a Draw shape (Curve)', () => {
		const src =
			`<Curve name="hop" from={[900, 1010]} to={[1143, 992]} c1={[874, 844]} arrow="end" />\n` +
			`<Line name="x" from={[1, 2]} to={[3, 4]} />`;
		const oldTag = `<Curve name="hop" from={[900, 1010]} to={[1143, 992]} c1={[874, 844]} arrow="end" />`;
		const newTag = `<Curve name="hop" from={[900, 1010]} to={[1200, 950]} c1={[850, 800]} arrow="end" />`;
		const { source, patched, unmatched } = patchSlideSource(src, [
			{ kind: 'Curve', name: 'hop', oldTag, newTag }
		]);
		expect(unmatched).toHaveLength(0);
		expect(patched).toHaveLength(1);
		expect(source).toContain(newTag);
		expect(source).toContain('<Line name="x" from={[1, 2]} to={[3, 4]} />');
	});

	it('applies a literal old→new tag swap for a Polyline (points rewritten in place)', () => {
		// Polyline saves through the same literal-swap path as Line/Curve/Arc:
		// the tag carries no box geometry, so its whole canonical opening tag is
		// the match key. The author's other props (color/thickness/dash) ride
		// along untouched because they're part of the identical old→new tag.
		const src = `\t<Polyline name="route" points={[[100, 900], [500, 500], [900, 900]]} smooth color="#7f8c8d" thickness={3} dash />\n`;
		const oldTag = `<Polyline name="route" points={[[100, 900], [500, 500], [900, 900]]} smooth color="#7f8c8d" thickness={3} dash />`;
		const newTag = `<Polyline name="route" points={[[100, 900], [550, 450], [900, 900]]} smooth color="#7f8c8d" thickness={3} dash />`;
		const { source, patched, unmatched } = patchSlideSource(src, [
			{ kind: 'Polyline', name: 'route', oldTag, newTag }
		]);
		expect(unmatched).toHaveLength(0);
		expect(patched).toHaveLength(1);
		expect(source).toContain('[550, 450]');
		expect(source).toContain('color="#7f8c8d" thickness={3} dash'); // decoration survives
	});

	it("a Polyline tag whose attributes are in a NON-canonical order is 'not-found'", () => {
		// The exact trap: the shape serializes `smooth color thickness dash`, but
		// the author wrote `smooth dash thickness color`. Literal swap is byte-for-
		// byte, so the canonical old tag isn't in the file — SAVE must refuse and
		// say so (Copy/paste by hand), never silently miss.
		const src = `<Polyline name="route" points={[[100, 900], [500, 500]]} smooth dash thickness={3} color="#7f8c8d" />`;
		const oldTag = `<Polyline name="route" points={[[100, 900], [500, 500]]} smooth color="#7f8c8d" thickness={3} dash />`;
		const newTag = `<Polyline name="route" points={[[100, 900], [550, 450]]} smooth color="#7f8c8d" thickness={3} dash />`;
		const { patched, unmatched } = patchSlideSource(src, [
			{ kind: 'Polyline', name: 'route', oldTag, newTag }
		]);
		expect(patched).toHaveLength(0);
		expect(unmatched).toHaveLength(1);
		expect(unmatched[0].reason).toBe('not-found');
	});

	it('reports a literal change whose old tag is not in source', () => {
		const src = `<Curve name="hop" from={[1, 1]} to={[2, 2]} c1={[3, 3]} />`;
		const { patched, unmatched } = patchSlideSource(src, [
			{ kind: 'Curve', oldTag: `<Curve name="ghost" from={[9, 9]} to={[8, 8]} c1={[7, 7]} />`, newTag: `<Curve name="ghost" from={[0, 0]} to={[8, 8]} c1={[7, 7]} />` }
		]);
		expect(patched).toHaveLength(0);
		expect(unmatched).toHaveLength(1);
		expect(unmatched[0].reason).toBe('not-found');
	});

	it("a Draw tag written with EXPRESSION geometry is 'not-found', never 'ambiguous'", () => {
		// The sprite-curve slide's shape: the real <Curve> points at a shared
		// const (`from={curve.from}`), so the canonical literal tag the shape
		// serializes does not exist in the file. The old blanket message blamed a
		// code-sample twin for this; the reason must say the tag was NOT FOUND.
		const src = `<Curve name="road" from={curve.from} c1={curve.c1} c2={curve.c2} to={curve.to} />`;
		const { patched, unmatched } = patchSlideSource(src, [
			{
				kind: 'Curve',
				name: 'road',
				oldTag: `<Curve name="road" from={[170, 1010]} c1={[560, 770]} c2={[1330, 1100]} to={[1750, 830]} />`,
				newTag: `<Curve name="road" from={[170, 1010]} c1={[560, 770]} c2={[1330, 1100]} to={[1750, 700]} />`
			}
		]);
		expect(patched).toHaveLength(0);
		expect(unmatched).toHaveLength(1);
		expect(unmatched[0].reason).toBe('not-found');
	});

	it('mixes a geometry Block change and a literal shape change', () => {
		const src =
			`<Block name="client" x={180} y={700} width={320} height={140}></Block>\n` +
			`<Curve name="hop" from={[900, 1010]} to={[1143, 992]} c1={[874, 844]} />`;
		const { source, patched } = patchSlideSource(src, [
			change({ name: 'client', before: { x: 180, y: 700, width: 320, height: 140 }, after: { x: 200, y: 720, width: 320, height: 140 } }),
			{ kind: 'Curve', name: 'hop', oldTag: `<Curve name="hop" from={[900, 1010]} to={[1143, 992]} c1={[874, 844]} />`, newTag: `<Curve name="hop" from={[905, 1000]} to={[1143, 992]} c1={[874, 844]} />` }
		]);
		expect(patched).toHaveLength(2);
		expect(source).toContain('<Block name="client" x={200} y={720} width={320} height={140}>');
		expect(source).toContain('<Curve name="hop" from={[905, 1000]} to={[1143, 992]} c1={[874, 844]} />');
	});

	it('inserts z only when the new value is non-zero', () => {
		const src = `<Block name="hero" x={100} y={200} width={300} height={400}></Block>`;
		const { source } = patchSlideSource(src, [
			change({ name: 'hero', after: { x: 111, y: 222, width: 333, height: 444, z: 3 } })
		]);
		expect(source).toContain('<Block name="hero" x={111} y={222} width={333} height={444} z={3}>');
	});

	it('never inserts z={0} — a default-layer Block stays clean', () => {
		const src = `<Block name="hero" x={100} y={200} width={300} height={400}></Block>`;
		const { source } = patchSlideSource(src, [
			change({ name: 'hero', after: { x: 111, y: 222, width: 333, height: 444, z: 0 } })
		]);
		expect(source).toContain('<Block name="hero" x={111} y={222} width={333} height={444}>');
		expect(source).not.toContain('z={');
	});

	it('rewrites an existing z in place — including back down to 0', () => {
		const src = `<Block name="hero" x={100} y={200} width={300} height={400} z={5}></Block>`;
		const { source } = patchSlideSource(src, [
			change({ name: 'hero', before: { x: 100, y: 200, width: 300, height: 400, z: 5 }, after: { x: 100, y: 200, width: 300, height: 400, z: 0 } })
		]);
		expect(source).toContain('<Block name="hero" x={100} y={200} width={300} height={400} z={0}>');
	});

	it('leaves the source untouched when nothing (including z) changed', () => {
		const src = `<Block name="hero" x={100} y={200} width={300} height={400} z={2}></Block>`;
		const { source, patched } = patchSlideSource(src, [
			change({ name: 'hero', before: { x: 100, y: 200, width: 300, height: 400, z: 2 }, after: { x: 100, y: 200, width: 300, height: 400, z: 2 } })
		]);
		expect(patched).toHaveLength(1); // matched, nothing to write
		expect(source).toBe(src);
	});

	it('applies several changes across the file', () => {
		const src =
			`<Block name="a" x={100} y={200} width={300} height={400}></Block>\n` +
			`<ImageBlock name="pic" x={5} y={6} width={7} height={8} />`;
		const { source, patched } = patchSlideSource(src, [
			change({ name: 'a' }),
			change({
				kind: 'ImageBlock',
				name: 'pic',
				before: { x: 5, y: 6, width: 7, height: 8 },
				after: { x: 50, y: 60, width: 70, height: 80 }
			})
		]);
		expect(patched).toHaveLength(2);
		expect(source).toContain('<Block name="a" x={111} y={222} width={333} height={444}>');
		expect(source).toContain('<ImageBlock name="pic" x={50} y={60} width={70} height={80} />');
	});

	// Every component now takes `style` / `id` / `class`, and ADJUST knows nothing about
	// them — which is precisely why they are worth pinning here. SAVE is a surgical
	// rewrite of the geometry attributes ONLY, so a decorated tag must come out the far
	// side still decorated. (COPY is the other, blunter path: it emits a whole tag, which
	// is why draw/editing.ts has to emit these too — see drawEditingTag.test.ts.)
	it('leaves the author’s style, id and class untouched while moving the box', () => {
		const src = `<Block name="hero" id="hero-box" class="hot" style="opacity: 0.4" x={100} y={200} width={300} height={400}>\n</Block>`;
		const { source, unmatched } = patchSlideSource(src, [change({ name: 'hero' })]);

		expect(unmatched).toHaveLength(0);
		expect(source).toContain('id="hero-box"');
		expect(source).toContain('class="hot"');
		expect(source).toContain('style="opacity: 0.4"');
		expect(source).toContain('x={111} y={222} width={333} height={444}');
	});

	// A style can carry the very characters the patcher scans for — braces. It must not
	// mistake `style="--f: {x}"` for a geometry expression, nor corrupt it.
	it('is not confused by braces inside a style value', () => {
		const src = `<Rect name="api" style="width: calc(100% - 4px)" x={100} y={200} width={300} height={400} />`;
		const { source, unmatched } = patchSlideSource(src, [change({ kind: 'Rect', name: 'api' })]);

		expect(unmatched).toHaveLength(0);
		expect(source).toContain('style="width: calc(100% - 4px)"');
		expect(source).toContain('x={111} y={222} width={333} height={444}');
	});
});

// --- INSERT: FREEZE adding markup the slide has never had ---------------------
//
// Every other mode here finds a tag and rewrites it. An inserted shape has no tag to
// find, so the question is "where does a NEW shape go?" — and the answers have to be
// conservative in the same way the matcher is: one <Draw> is obvious, several is a
// genuine ambiguity and is never guessed at.
describe('patchSlideSource — insert (FREEZE)', () => {
	const POLY = '<Polyline points={[[10, 20], [30, 40]]} smooth />';
	const insert = (over: Partial<LayoutChange> = {}): LayoutChange => ({
		kind: 'Draw',
		insert: POLY,
		insertImports: ['Draw', 'Polyline'],
		...over
	});

	it('places the shape inside the slide’s existing <Draw>, indented to match', () => {
		const src = [
			'<script>',
			"\timport { Draw, Line } from '$lib/draw';",
			'</script>',
			'',
			'<Draw>',
			'\t<Line from={[0, 0]} to={[9, 9]} />',
			'</Draw>'
		].join('\n');
		const { source, patched, unmatched } = patchSlideSource(src, [insert()]);

		expect(unmatched).toHaveLength(0);
		expect(patched).toHaveLength(1);
		expect(source).toContain('\t<Line from={[0, 0]} to={[9, 9]} />\n\t' + POLY + '\n</Draw>');
		// The existing shape is untouched and the close tag keeps its own indentation.
		expect(source).toContain('<Line from={[0, 0]} to={[9, 9]} />');
	});

	it('appends a whole <Draw> when the slide has none', () => {
		const src = '<script>\n</script>\n\n<ContentPage title="x" />\n';
		const { source, unmatched } = patchSlideSource(src, [insert()]);

		expect(unmatched).toHaveLength(0);
		expect(source).toContain('<Draw>\n\t' + POLY + '\n</Draw>');
		// After the markup it belongs after, not before it.
		expect(source.indexOf('<ContentPage')).toBeLessThan(source.indexOf('<Draw>'));
	});

	it('puts a fresh <Draw> BEFORE the slide’s <style> block, not after it', () => {
		const src = '<script>\n</script>\n\n<ContentPage title="x" />\n\n<style>\n\t.a { color: red; }\n</style>\n';
		const { source } = patchSlideSource(src, [insert()]);

		expect(source.indexOf('<Draw>')).toBeLessThan(source.indexOf('<style>'));
		expect(source).toContain('.a { color: red; }');
	});

	it('refuses to guess when the slide has SEVERAL <Draw>s', () => {
		const src = '<Draw name="a">\n</Draw>\n<Draw name="b">\n</Draw>\n';
		const { source, patched, unmatched } = patchSlideSource(src, [insert()]);

		expect(patched).toHaveLength(0);
		expect(unmatched).toHaveLength(1);
		expect(unmatched[0].reason).toBe('ambiguous');
		expect(source).toBe(src); // and nothing was written
	});

	it('reports an empty insert rather than writing nothing and claiming success', () => {
		const { unmatched } = patchSlideSource('<Draw>\n</Draw>', [insert({ insert: '   ' })]);
		expect(unmatched[0].reason).toBe('not-found');
	});
});

// Without the import, an inserted <Polyline> is a build error rather than a shape — so the
// import half is as load-bearing as the markup half.
describe('patchSlideSource — insert brings its imports', () => {
	const insert = (imports: string[]): LayoutChange => ({
		kind: 'Draw',
		insert: '<Rect x={0} y={0} width={9} height={9} />',
		insertImports: imports
	});

	it('merges missing names into an existing $lib/draw import', () => {
		const src = "<script>\n\timport { Draw, Line } from '$lib/draw';\n</script>\n<Draw>\n</Draw>";
		const { source } = patchSlideSource(src, [insert(['Draw', 'Rect'])]);
		expect(source).toContain("import { Draw, Line, Rect } from '$lib/draw';");
	});

	it('leaves the import alone when everything is already imported', () => {
		const src = "<script>\n\timport { Draw, Rect } from '$lib/draw';\n</script>\n<Draw>\n</Draw>";
		const { source } = patchSlideSource(src, [insert(['Draw', 'Rect'])]);
		expect(source).toContain("import { Draw, Rect } from '$lib/draw';");
		// Not duplicated, and not re-sorted into a second line.
		expect(source.match(/\$lib\/draw/g)).toHaveLength(1);
	});

	it('adds the import to a script block that has no draw import at all', () => {
		const src = "<script>\n\timport Block from '$lib/components/Block.svelte';\n</script>\n<Draw>\n</Draw>";
		const { source } = patchSlideSource(src, [insert(['Draw', 'Rect'])]);
		expect(source).toContain("import { Draw, Rect } from '$lib/draw';");
		expect(source).toContain("import Block from '$lib/components/Block.svelte';");
	});

	it('gives a pure-markup slide a <script> block to hold the import', () => {
		const { source } = patchSlideSource('<ContentPage title="x" />\n', [insert(['Draw', 'Rect'])]);
		expect(source.startsWith('<script lang="ts">')).toBe(true);
		expect(source).toContain("import { Draw, Rect } from '$lib/draw';");
	});
});
