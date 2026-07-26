<!--
  Draw — the canvas-coordinate SVG surface for the drawing components.

  Renders one absolutely-positioned <svg> spanning the whole canvas with
  viewBox="0 0 1920 1080" (both overridable for portrait/custom decks), so
  SVG user units equal canvas pixels equal Block x/y — place <Draw> as a
  direct child of the slide, exactly like a bare <Block>, and the numbers
  match with no math:

      <Draw title="Request flow">
        <Line from={[300, 540]} to={[900, 540]} arrow="end" />
        <Rect x={860} y={480} width={400} height={120} rounded={12} />
        <circle cx="960" cy="540" r="8" fill="currentColor" />  (raw SVG passes through)
      </Draw>

  The surface never eats input: pointer-events none, so a full-canvas Draw
  never blocks clicks, drags, or text selection on content beneath it.
  (Phase 3 re-enables pointer events only on editing chrome, only in ADJUST.)

  Accessibility: role="img" with a required `title` (→ <title>) and optional
  `description` (→ <desc>); purely decorative surfaces opt out with
  `decorative` → aria-hidden="true" (then `title` is not required).

  Theme via --draw-* custom properties (--draw-stroke, --draw-thickness,
  --draw-fill, --draw-font-size), mirroring --chart-*/--dt-*; defaults
  inherit currentColor so shapes sit on light or dark slides unchanged.
-->
<script lang="ts">
	import type { Snippet } from 'svelte';
	import { getContext, setContext, onDestroy } from 'svelte';
	import { browser } from '$app/environment';
	import Block from '$lib/components/Block.svelte';
	import {
		adjustChanges,
		nextDrawInstanceId,
		reportShapeChanges,
		withdrawShapeChanges
	} from '$lib/stores/adjustChanges';
	import { canAdjust, adjustMode } from '$lib/stores/adjustMode';
	import { trackPointer } from '$lib/utils/drag';
	import { SvelteMap } from 'svelte/reactivity';
	import {
		DRAW_CONTEXT_KEY,
		SPRITE_ISOLATION_KEY,
		type BlockShapeRegistration,
		type DrawContext,
		type PathShape,
		type ShapeEditor,
		type SpriteIsolation
	} from './types';

	interface Props {
		/** The coordinate space, in canvas px (override for portrait decks). */
		width?: number;
		height?: number;
		/** Accessible name (SVG <title>). Required unless `decorative`. */
		title?: string;
		/** Optional longer description (SVG <desc>). */
		description?: string;
		/** Purely decorative surface: aria-hidden, no title required. */
		decorative?: boolean;
		/** Editing-toolbar title + localStorage key for its position (mirrors
		 *  KeyframeStudio's `name`), so two Draws on a page don't collide. */
		name?: string;
		children?: Snippet;
		/** Inline style for the root element, applied last so it wins. */
		style?: string;
		/** DOM id for the root element. */
		id?: string;
		/** Extra class(es) for the root element. NOTE: a slide's own scoped styles
		 *  will NOT match — use global CSS (global.css / roles.css / a :global(...)
		 *  block) or a utility class. See AGENTS.md. */
		class?: string;
	}

	let {
		width = 1920,
		height = 1080,
		title,
		description,
		decorative = false,
		name = '',
		children,
		style = '',
		id = '',
		class: klass = ''
	}: Props = $props();

	// ADJUST-mode editing (Phase 3): shapes read this gate + selection surface
	// from context. canAdjust keeps the published deck inert even if a stale
	// adjustMode=true lingers in localStorage — same rule as Block.
	// When nested inside a <Sprite> group, a Draw edits only while the group is
	// ISOLATED (double-clicked), so its chrome never lingers on the flying box.
	// A top-level Draw sees no isolation provider and edits normally.
	const iso = getContext<SpriteIsolation | undefined>(SPRITE_ISOLATION_KEY);
	const editing = $derived($canAdjust && $adjustMode && (iso ? iso.entered : true));
	// $state.raw: shapes check `ctx.selected === editor` by identity, so the
	// stored editor must not be wrapped in a reactive proxy.
	let selected = $state.raw<ShapeEditor | null>(null);
	// Path shapes register on mount (raw for the same identity reason).
	let editors = $state.raw<ShapeEditor[]>([]);

	// --- Select-to-front: the selected shape's editing chrome (guides +
	// handles) is re-parented into the top layer below, so its handles are
	// grabbable wherever they lie — even under a shape drawn after it. SVG has
	// no z-index, so this re-parenting is the only lever; moving the CHROME
	// rather than the shape's own <g> raises interaction while leaving the
	// visible overlap the author drew exactly as authored.
	//
	// `frozen` is the hold that makes it safe. A drag that begins on an
	// UNSELECTED handle selects and grabs in one gesture, and hoisting mid-drag
	// would re-create the very node under the pointer — dropping its pointer
	// capture, so a release outside the window is never seen and the drag sticks
	// to the cursor. So the hoist parks on whatever it showed when the gesture
	// began and catches up on release; a handle already in hand has no use for
	// being in front.
	//
	// A flag suffices — a second finger landing on another handle cannot strand
	// it. `trackPointer` listens for pointerup on the WINDOW and filters no
	// pointerId, so any release tears down every gesture in flight (and Esc
	// cancels them all likewise). Overlapping drags therefore always end
	// together: the deck is single-gesture by construction, here as in Block.
	let gesture = $state(false);
	let frozen = $state.raw<ShapeEditor | null>(null);
	const hoisted = $derived(gesture ? frozen : selected);
	// Box-geometry shapes (Rect/Ellipse) — Draw hosts one editing <Block> per
	// registration as an HTML sibling of the svg (HTML can't live inside it).
	let blocks = $state<BlockShapeRegistration[]>([]);

	// Named path sources: Line/Curve/Arc publish their live geometry by name so
	// a <Sprite path="name"> can ride them. A SvelteMap so a late-registering
	// shape still reaches a sprite that already looked its name up; each getter
	// reads the shape's reactive points, so a handle drag re-samples the flight.
	const pathSources = new SvelteMap<string, () => PathShape>();

	setContext<DrawContext>(DRAW_CONTEXT_KEY, {
		get width() {
			return width;
		},
		get height() {
			return height;
		},
		get editing() {
			return editing;
		},
		get selected() {
			return selected;
		},
		select(editor) {
			selected = editor;
		},
		get hoisted() {
			return hoisted;
		},
		beginGesture() {
			// Snapshot BEFORE the handle's own select() lands, so the chrome under
			// the pointer stays exactly where the pointer found it. Only the FIRST
			// live gesture may snapshot: a second finger landing on another handle
			// would otherwise re-snapshot to the shape the first grab just selected,
			// hoisting it mid-drag — re-homing the node under the first pointer,
			// which is the exact thing the hold exists to prevent.
			if (!gesture) frozen = selected;
			gesture = true;
		},
		endGesture() {
			gesture = false;
		},
		registerShape(editor) {
			editors = [...editors, editor];
			return () => {
				editors = editors.filter((e) => e.id !== editor.id);
				if (selected === editor) selected = null;
				// A shape that unmounts mid-gesture must not keep the hoist pinned
				// to an editor nobody renders any more.
				if (frozen === editor) frozen = null;
			};
		},
		registerBlock(shape) {
			blocks = [...blocks, shape];
			return () => {
				blocks = blocks.filter((b) => b.id !== shape.id);
			};
		},
		registerPathSource(name, get) {
			pathSources.set(name, get);
			return () => {
				// Only clear our own registration — a same-named late arrival
				// (HMR re-mount) must not be wiped by the old instance's teardown.
				if (pathSources.get(name) === get) pathSources.delete(name);
			};
		},
		pathSource(name) {
			return pathSources.get(name)?.() ?? null;
		}
	});

	// --- Floating Copy toolbar for the selected shape (the KeyframeStudio
	// panel pattern): draggable by its header, offset persisted in canvas px
	// per `name`. Nothing else is saved — the editor is a coordinate finder.
	// `name` is the canvas's identity, fixed for its lifetime — the init-time
	// capture is deliberate.
	// svelte-ignore state_referenced_locally
	const PANEL_KEY = `drawPanel:${name}`;
	function loadPanel(): { dx: number; dy: number } {
		if (!browser) return { dx: 0, dy: 0 };
		try {
			const s = JSON.parse(localStorage.getItem(PANEL_KEY) || 'null');
			if (s) return { dx: Number(s.dx) || 0, dy: Number(s.dy) || 0 };
		} catch {
			/* corrupt storage — fall through to the default */
		}
		return { dx: 0, dy: 0 };
	}
	const savedPanel = loadPanel();

	let panelEl = $state<HTMLElement>();
	let panelDX = $state(savedPanel.dx);
	let panelDY = $state(savedPanel.dy);
	$effect(() => {
		if (browser) localStorage.setItem(PANEL_KEY, JSON.stringify({ dx: panelDX, dy: panelDY }));
	});

	function startPanelDrag(event: PointerEvent) {
		event.preventDefault();
		const baseDX = panelDX;
		const baseDY = panelDY;
		trackPointer(event, {
			scaleFrom: panelEl,
			onMove: (dx, dy) => {
				panelDX = baseDX + dx;
				panelDY = baseDY + dy;
			}
		});
	}

	// Single selection, everywhere: grabbing anything that isn't this Draw's
	// editing chrome (another Block, slide content, empty canvas) deselects.
	// Handle drags stopPropagation and never get here; hit-stroke clicks land
	// inside the svg and are exempt, so shape→shape selection still swaps.
	let svgEl = $state<SVGSVGElement>();
	$effect(() => {
		if (!editing || !selected) return;
		const onDown = (e: PointerEvent) => {
			const t = e.target as Node | null;
			if (t && (svgEl?.contains(t) || panelEl?.contains(t))) return;
			// Keep the selection (and this toolbar) up while the author works the
			// AnimationBar — playing/scrubbing is exactly when the live draw
			// preview matters.
			if (t instanceof Element && t.closest('.anim-bar')) return;
			selected = null;
		};
		// Capture phase: Block's drag handler stopPropagation()s, so a bubbling
		// listener would never see a grab on a Block.
		window.addEventListener('pointerdown', onDown, true);
		return () => window.removeEventListener('pointerdown', onDown, true);
	});

	let copied = $state(false);
	async function copySnippet() {
		if (!selected) return;
		const snippet = selected.snippet;
		try {
			await navigator.clipboard.writeText(snippet);
			copied = true;
			setTimeout(() => (copied = false), 1200);
		} catch {
			// Clipboard blocked (insecure context / permission) — fall back to a
			// prompt so the author can still grab the text by hand.
			window.prompt('Copy this snippet:', snippet);
		}
	}

	// --- "Copy changed": everything whose live geometry differs from its
	// source form, as an OLD/NEW patch — this Draw's shapes (in markup order;
	// ids are handed out in mount order) plus every moved slide-level Block
	// from the page-wide registry (Blocks are siblings of the surface, so
	// context can't reach them). The OLD tag locates the source line without
	// assuming the tags sit together — hand the whole thing to an AI
	// assistant (or apply it by hand/sed) instead of pasting tag by tag.
	const dirtyShapes = $derived(
		[
			...editors.map((e) => ({ id: e.id, kind: e.kind, name: e.name, dirty: e.dirty, oldTag: e.sourceSnippet, newTag: e.snippet })),
			...blocks.map((b) => ({ id: b.id, kind: b.tag, name: b.name, dirty: b.dirty, oldTag: b.sourceSnippet, newTag: b.snippet }))
		]
			.filter((s) => s.dirty)
			.sort((a, b) => a.id - b.id)
	);
	const dirtyBlocks = $derived([...$adjustChanges.values()].filter((e) => e.dirty));
	const dirtyAll = $derived([...dirtyShapes, ...dirtyBlocks]);

	// Publish this Draw's shapes (curves/lines/arcs/boxes) to the page-level shape
	// registry so the top-right "Save" writes them too — they can't ride the
	// geometry registry (a Curve has no box), so they carry their whole old/new
	// opening tag for a literal source replacement. Keyed per Draw instance; the
	// registry is separate from adjustChanges, so dirtyShapes above never reads
	// these back and double-counts. onDestroy clears them when the slide unmounts.
	const drawInstance = nextDrawInstanceId();
	$effect(() => {
		reportShapeChanges(drawInstance, [
			...editors.map((e) => ({
				key: `${drawInstance}:e:${e.id}`,
				kind: e.kind,
				name: e.name,
				dirty: e.dirty,
				oldTag: e.sourceSnippet,
				newTag: e.snippet
			})),
			...blocks.map((b) => ({
				key: `${drawInstance}:b:${b.id}`,
				kind: b.tag,
				name: b.name,
				dirty: b.dirty,
				oldTag: b.sourceSnippet,
				newTag: b.snippet
			}))
		]);
	});
	onDestroy(() => withdrawShapeChanges(drawInstance));

	const patchText = $derived(
		[
			`Slide shape updates (${dirtyAll.length} changed) — apply to the slide's Svelte source.\n` +
				`For each entry, find the line with the OLD opening tag (match by component +\n` +
				`name, or by its old geometry) and replace that ONE line with the NEW tag,\n` +
				`exactly as given. Leave children, comments, and every other line untouched.`,
			...dirtyAll.map(
				(s, i) =>
					`${i + 1}) ${s.kind}${s.name ? ` "${s.name}"` : ''}\n` +
					`OLD: ${s.oldTag}\n` +
					`NEW: ${s.newTag}`
			)
		].join('\n\n')
	);

	let copiedPatch = $state(false);
	async function copyPatch() {
		const text = patchText;
		try {
			await navigator.clipboard.writeText(text);
			copiedPatch = true;
			setTimeout(() => (copiedPatch = false), 1200);
		} catch {
			window.prompt('Copy this patch:', text);
		}
	}

	// Live scrub preview: while an animated shape is selected, poll its
	// playhead % and interpolated draw-progress each frame so the panel
	// previews progress as the AnimationBar scrubs.
	let livePreview = $state<{ pct: number; drawn: number | null } | null>(null);
	$effect(() => {
		const read = selected?.anim?.preview;
		if (!browser || !editing || !read) {
			livePreview = null;
			return;
		}
		let raf = 0;
		const loop = () => {
			livePreview = read();
			raf = requestAnimationFrame(loop);
		};
		loop();
		return () => cancelAnimationFrame(raf);
	});
</script>

<svg
	bind:this={svgEl}
	id={id || undefined}
	class="draw {klass}"
	class:raised={editing}
	viewBox="0 0 {width} {height}"
	style="width:{width}px; height:{height}px; pointer-events:none;{style}"
	role={decorative ? undefined : 'img'}
	aria-hidden={decorative ? 'true' : undefined}
>
	{#if !decorative && title}<title>{title}</title>{/if}
	{#if !decorative && description}<desc>{description}</desc>{/if}
	{@render children?.()}
	{#if editing && hoisted?.chrome}
		<!-- The top chrome layer (select-to-front). Last child of the surface, so
		     the selected shape's guides and handles paint — and hit-test — above
		     every shape and every other shape's 24px-wide hit stroke. The shape
		     that owns this chrome renders none of its own inline, so it lives in
		     exactly one place. Hit strokes deliberately stay put: they only ever
		     compete with each other, and raising the selected shape's would seal
		     off the crossing band where a neighbour's stroke is the one you're
		     trying to click. -->
		{@render hoisted.chrome()}
	{/if}
</svg>

{#if editing}
	<!-- ADJUST-mode editing Blocks for the box-geometry shapes: rendered as
	     HTML siblings of the svg (same canvas coordinates — Draw must be a
	     direct child of the slide, like a bare Block), two-way bound so the
	     svg shape follows every drag. Block supplies move/resize/aspect/grid/
	     undo and a Copy that emits the shape's OWN tag. -->
	{#each blocks as b (b.id)}
		<Block
			tag={b.tag}
			selfClose
			attrs={b.attrs}
			name={b.name}
			grid={b.grid}
			aspect={b.aspect}
			bounds={b.bounds}
			canvasWidth={width}
			canvasHeight={height}
			track={false}
			drawEdit={b.drawEdit}
			hostStyle={b.style ?? ''}
			bind:x={b.x}
			bind:y={b.y}
			bind:width={b.width}
			bind:height={b.height}
		/>
	{/each}

	{#if selected || dirtyAll.length}
		<!-- Copy toolbar: the selected path shape's tag (Rect/Ellipse use their
		     Block's own chrome), plus a "Copy changed" patch of every dragged
		     shape. HTML, per-Draw, floating — never in SVG. -->
		<!-- svelte-ignore a11y_no_static_element_interactions -->
		<div
			class="draw-toolbar no-print"
			bind:this={panelEl}
			style="transform: translate({panelDX}px, {panelDY}px);"
		>
			<div class="tb-head" onpointerdown={startPanelDrag}>
				<span class="tb-title">Draw{name ? ` · ${name}` : ''}</span>
				{#if selected}
					<span class="tb-shape">{selected.name || selected.kind}</span>
					<button
						class="tb-close"
						type="button"
						aria-label="Deselect"
						onpointerdown={(e) => e.stopPropagation()}
						onclick={() => (selected = null)}>✕</button
					>
				{/if}
			</div>
			{#if selected}
				<div class="tb-readout">{selected.readout}</div>
				{#if selected.anim}
					<!-- Keyframe editor for the selected animated shape: one row per
					     stop (its % of the timeline), add into the widest gap, remove
					     (min 2). Retiming/adding is finder state — Copy to persist. -->
					<div class="tb-keyframes">
						<div class="tb-kftitle">
							keyframes{#if livePreview}<span class="tb-livedrawn"
									>▸ {livePreview.pct}%{#if livePreview.drawn != null} · {livePreview.drawn}% drawn{/if}</span
								>{/if}
						</div>
						{#each selected.anim.stops as st (st.id)}
							<div class="tb-kfrow">
								<input
									class="tb-pct"
									type="number"
									min="0"
									max="100"
									step="1"
									value={st.pct}
									aria-label="keyframe percent"
									onchange={(e) => selected?.anim?.setPct(st.id, +e.currentTarget.value)}
								/>
								<span class="tb-pctsign">%</span>
								{#if selected.anim.setDrawn}
									<!-- Reveal draw-progress at this keyframe (blank = no reveal
									     keyframe here; type a % to add one, clear to remove). -->
									<span class="tb-flabel tb-drawnlabel">drawn</span>
									<input
										class="tb-pct"
										type="number"
										min="0"
										max="100"
										step="1"
										placeholder="—"
										value={st.drawn ?? ''}
										aria-label="keyframe drawn percent"
										onchange={(e) =>
											selected?.anim?.setDrawn?.(
												st.id,
												e.currentTarget.value === '' ? null : +e.currentTarget.value
											)}
									/>
									<span class="tb-pctsign">%</span>
								{/if}
								{#if selected.anim.setEase}
									<!-- Easing for the segment starting at this keyframe. -->
									<select
										class="tb-ease"
										value={st.ease ?? ''}
										aria-label="keyframe easing"
										title="Easing of the segment starting here"
										onchange={(e) => selected?.anim?.setEase?.(st.id, e.currentTarget.value || null)}
									>
										<option value="">ease</option>
										<option value="linear">linear</option>
										<option value="ease-in">in</option>
										<option value="ease-out">out</option>
										<option value="ease-in-out">in-out</option>
									</select>
								{/if}
								{#if selected.anim.setPose}
									<!-- Numeric box pose on the SAME row: L/T/W/H in canvas px, R in
									     degrees. Drag on-canvas OR type here — same setter, live. -->
									<span class="tb-pose">
										<label class="tb-poselabel">L<input class="tb-posef" type="number" step="1" value={st.x ?? 0} aria-label="left, px" onchange={(e) => selected?.anim?.setPose?.(st.id, 'x', +e.currentTarget.value)} /></label>
										<label class="tb-poselabel">T<input class="tb-posef" type="number" step="1" value={st.y ?? 0} aria-label="top, px" onchange={(e) => selected?.anim?.setPose?.(st.id, 'y', +e.currentTarget.value)} /></label>
										<label class="tb-poselabel">W<input class="tb-posef" type="number" step="1" value={st.w ?? 0} aria-label="width, px" onchange={(e) => selected?.anim?.setPose?.(st.id, 'w', +e.currentTarget.value)} /></label>
										<label class="tb-poselabel">H<input class="tb-posef" type="number" step="1" value={st.h ?? 0} aria-label="height, px" onchange={(e) => selected?.anim?.setPose?.(st.id, 'h', +e.currentTarget.value)} /></label>
										<label class="tb-poselabel">R<input class="tb-posef" type="number" step="15" value={st.rot ?? 0} aria-label="rotation, deg" onchange={(e) => selected?.anim?.setPose?.(st.id, 'rot', +e.currentTarget.value)} />°</label>
									</span>
								{/if}
								<button
									class="tb-del"
									type="button"
									title="Remove this keyframe"
									disabled={selected.anim.stops.length <= 2}
									onclick={() => selected?.anim?.removeStop(st.id)}>✕</button
								>
							</div>
						{/each}
						<button class="tb-add" type="button" onclick={() => selected?.anim?.addStop()}
							>+ keyframe</button
						>
					</div>
				{/if}
				{#if selected.drawEdit}
					<!-- Draw-on reveal editor: retime the self-draw and its start
					     delay. Live + copyable, so the reveal is animatable/editable
					     just like geometry keyframes. -->
					<div class="tb-keyframes">
						<div class="tb-kftitle">draw-on</div>
						<div class="tb-kfrow">
							<span class="tb-flabel">time</span>
							<input
								class="tb-pct"
								type="number"
								min="0"
								step="0.1"
								value={selected.drawEdit.seconds}
								aria-label="draw-on seconds"
								onchange={(e) => selected?.drawEdit?.setSeconds(+e.currentTarget.value)}
							/>
							<span class="tb-pctsign">s</span>
						</div>
						<div class="tb-kfrow">
							<span class="tb-flabel">delay</span>
							<input
								class="tb-pct"
								type="number"
								min="0"
								step="0.1"
								value={selected.drawEdit.delay}
								aria-label="draw-on delay seconds"
								onchange={(e) => selected?.drawEdit?.setDelay(+e.currentTarget.value)}
							/>
							<span class="tb-pctsign">s</span>
						</div>
					</div>
				{/if}
				<button class="tb-copy" type="button" onclick={copySnippet}>
					{copied ? 'Copied!' : 'Copy'}
				</button>
			{/if}
			{#if dirtyAll.length}
				<div class="tb-changed">
					<span class="tb-count">{dirtyAll.length} changed</span>
					<button
						class="tb-copy tb-patch"
						type="button"
						title="Copies an OLD/NEW patch of every moved shape and Block — paste it to your AI assistant (or apply by hand) to update the source"
						onclick={copyPatch}
					>
						{copiedPatch ? 'Copied!' : `Copy changed (${dirtyAll.length})`}
					</button>
				</div>
			{/if}
		</div>
	{/if}
{/if}

<style>
	.draw {
		position: absolute;
		left: 0;
		top: 0;
		/* pointer-events:none is inline on the element — the never-eats-input
		   guarantee must hold even before/without this stylesheet. */
		display: block;
		fill: none;
		/* Theming contract: shapes read --draw-stroke / --draw-thickness /
		   --draw-fill (set them on the deck, a slide, or any ancestor — they
		   cascade into the svg); --draw-font-size feeds Phase 2 labels. */
		font-size: var(--draw-font-size, 32px);
	}
	/* In ADJUST mode the whole surface lifts above the HTML editing chrome
	   (Blocks/ghosts have no z-index) so handles and hit strokes always win
	   the pointer — otherwise a Block or a KeyframeStudio ghost sitting on a
	   shape (e.g. a ghost stop centered on a curve endpoint) makes the
	   handle unreachable, and you could never select the shape to begin
	   with. The surface itself remains pointer-events:none, so everything
	   that isn't a handle or hit stroke still clicks through to the
	   Blocks/ghosts beneath. */
	.draw.raised {
		z-index: 60;
		/* While EDITING, let the surface paint beyond the canvas edge: points
		   may legitimately live off-stage (a control point pulled below the
		   slide, a flight that enters from outside), and their handles must be
		   visible and grabbable to edit. Published/presenting keeps the svg
		   default (hidden), so an off-stage sprite stays hidden until its path
		   crosses the edge — the whole point of a fly-in. */
		overflow: visible;
	}

	/* Floating Copy toolbar (ADJUST mode, selected shape only) — the
	   KeyframeStudio panel look. */
	.draw-toolbar {
		position: absolute;
		left: 40px;
		bottom: 56px;
		display: flex;
		flex-direction: column;
		align-items: stretch;
		gap: 0.5em;
		padding: 0.6em 0.7em 0.7em;
		background: rgba(18, 18, 18, 0.92);
		border: 1px solid var(--ctrl-strong-bg, #2980b9);
		border-radius: 8px;
		/* Above the raised surface (60), so the toolbar stays usable even
		   where a stroke crosses it. */
		z-index: 70;
	}
	.tb-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 1.2em;
		cursor: move;
		user-select: none;
		touch-action: none;
	}
	.tb-title {
		font-family: 'Fira Code', monospace;
		font-size: 18px;
		color: #9aa7b0;
	}
	.tb-shape {
		font-family: 'Fira Code', monospace;
		font-size: 18px;
		font-weight: bold;
		color: #cfe3f2;
	}
	.tb-close {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 1.6em;
		height: 1.6em;
		font-family: 'Fira Code', monospace;
		font-size: 15px;
		line-height: 1;
		cursor: pointer;
		border: 0;
		border-radius: 5px;
		background: var(--ctrl-bg, #181818);
		color: #cfe3f2;
	}
	.tb-close:hover {
		background: #b3402e;
		color: #fff;
	}
	.tb-readout {
		font-family: 'Fira Code', monospace;
		font-size: 15px;
		color: #9aa7b0;
		white-space: nowrap;
	}
	.tb-changed {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 1em;
	}
	.tb-count {
		font-family: 'Fira Code', monospace;
		font-size: 15px;
		color: #9aa7b0;
	}

	/* Keyframe editor: a stacked list of stop rows + an add button. */
	.tb-keyframes {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: 0.3em;
		padding: 0.3em 0;
		border-top: 1px solid rgba(255, 255, 255, 0.12);
	}
	.tb-kftitle {
		font-family: 'Fira Code', monospace;
		font-size: 13px;
		letter-spacing: 0.1em;
		text-transform: uppercase;
		color: #6f7d86;
	}
	/* Live draw-progress readout — updates each frame as the bar scrubs. */
	.tb-livedrawn {
		margin-left: 0.6em;
		letter-spacing: 0;
		text-transform: none;
		color: var(--ctrl-selected-bg, #00b356);
		font-weight: bold;
	}
	.tb-kfrow {
		display: inline-flex;
		align-items: center;
		gap: 0.3em;
	}
	.tb-pct {
		width: 3.4em;
		font-family: 'Fira Code', monospace;
		font-size: 15px;
		color: #cfe3f2;
		background: var(--ctrl-bg, #181818);
		border: 1px solid var(--ctrl-strong-bg, #2980b9);
		border-radius: 5px;
		padding: 0.12em 0.3em;
	}
	.tb-pctsign {
		font-family: 'Fira Code', monospace;
		font-size: 15px;
		color: #9aa7b0;
	}
	/* Numeric box-pose fields (Sprite): compact L/T/W/H/R group inline on the
	   stop's % row. */
	.tb-pose {
		display: inline-flex;
		align-items: center;
		gap: 0.4em;
		margin-left: 0.4em;
	}
	.tb-poselabel {
		display: inline-flex;
		align-items: center;
		gap: 0.12em;
		font-family: 'Fira Code', monospace;
		font-size: 13px;
		color: #9aa7b0;
	}
	.tb-posef {
		width: 3.2em;
		font-family: 'Fira Code', monospace;
		font-size: 14px;
		color: #cfe3f2;
		background: var(--ctrl-bg, #181818);
		border: 1px solid var(--ctrl-strong-bg, #2980b9);
		border-radius: 4px;
		padding: 0.1em 0.25em;
	}
	.tb-flabel {
		display: inline-block;
		width: 3.2em;
		font-family: 'Fira Code', monospace;
		font-size: 15px;
		color: #9aa7b0;
	}
	.tb-drawnlabel {
		width: auto;
		margin-left: 0.5em;
	}
	.tb-ease {
		font-family: 'Fira Code', monospace;
		font-size: 13px;
		color: #cfe3f2;
		background: var(--ctrl-bg, #181818);
		border: 1px solid var(--ctrl-strong-bg, #2980b9);
		border-radius: 4px;
		padding: 0.1em 0.2em;
		margin-left: 0.4em;
	}
	.tb-del {
		font-family: 'Fira Code', monospace;
		font-size: 14px;
		line-height: 1;
		cursor: pointer;
		border: 0;
		border-radius: 4px;
		padding: 0.15em 0.4em;
		background: var(--ctrl-bg, #181818);
		color: #cfe3f2;
	}
	.tb-del:hover:not(:disabled) {
		background: #b3402e;
		color: #fff;
	}
	.tb-del:disabled {
		opacity: 0.35;
		cursor: default;
	}
	.tb-add {
		font-family: 'Fira Code', monospace;
		font-size: 14px;
		font-weight: bold;
		cursor: pointer;
		border: 0;
		border-radius: 5px;
		padding: 0.2em 0.6em;
		background: var(--ctrl-strong-bg, #2980b9);
		color: var(--on-accent, #ffffff);
	}
	.tb-copy {
		align-self: flex-start;
		font-family: 'Fira Code', monospace;
		font-weight: bold;
		font-size: 18px;
		cursor: pointer;
		border: 0;
		border-radius: 5px;
		padding: 0.3em 0.9em;
		background: var(--ctrl-selected-bg, #00b356);
		color: var(--on-accent, #ffffff);
	}
	.tb-copy.tb-patch {
		background: var(--ctrl-strong-bg, #2980b9);
	}
</style>
