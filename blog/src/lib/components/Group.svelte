<!--
  Group — a logical group of Blocks that moves, zooms and pans as one.

  Its members (Block, ImageBlock, TextBlock, SvgBlock, and nested Groups) are
  authored in the group's own LOCAL coordinates. The group maps that space onto
  the canvas with one uniform zoom plus a shift, so changing ONE tag moves every
  part together:

      <Group x={200} y={100} scale={0.5}>        placement: origin at 200,100, half size
          <ImageBlock name="host" … />
          <ImageBlock name="booth" … />
      </Group>

  Or aim it like a camera — the same scene, a different shot per slide:

      <Group focus="stats" zoom={21}>   this part's centre at the canvas centre, 21×
      <Group fit="variants" pad={0.1}>  this part fills the canvas, 10% margin
      <Group view={{ x, y, width, height }}>   this local rectangle fills the canvas

  Precedence: view, then fit, then focus, then x/y/scale. A name that isn't a
  member falls through to the next, so a typo shows the scene unzoomed.

  Members still render REAL canvas boxes — the group is no CSS transform on a
  wrapper — so a View-Transition morph between two slides glides each named part
  from its true box on one to its true box on the other, crisp at any zoom. A
  member's content IS scaled with it (text, borders, the picture), the way a
  zoom should be. Connector and Spotlight keep working: anchors are published in
  canvas coordinates.

  One scene, many slides: write the parts once in a component, render it on
  each slide with that slide's shot. Per slide, `hide={['logo']}` takes parts
  out (they keep their box, so they fade as they glide), and a `<slot />` inside
  the scene's Group lets a slide add its own extras in scene coordinates.
  `move={{ db: { x: 480 } }}` puts a part somewhere else on this slide — shifted
  in the drawing's units, `scale` about its own centre — by name, like `hide`, so
  a scene forwards one prop and a slide can move any part (a nested group's
  name moves all of it). A drag in ADJUST still saves where the part is DRAWN.
  `morph="cam"` names every member for the glide (`view-transition-name:
  cam-<name>`), and `morphOn="camera"` keeps those names to that one transition
  kind — no hand-written CSS per part.

  In ADJUST mode a member drags in local units, so SAVE writes the scene's own
  numbers back — never the zoomed ones — into the file that wrote the tag (the
  scene component, for a shared scene). The group itself shows a dashed outline
  round its members, labelled with the prop that's in charge.

  A NAMED camera (`fit` / `focus="name"`) resolves once its target has mounted:
  always so in the browser, but in a server render (the handout) members are
  drawn with the placement frame. `view` and a `focus` point are exact
  everywhere.

  The element itself is `display: contents`: it creates no box, so members still
  position against the canvas. `style` therefore only carries inherited custom
  properties (a `--textblock-fg` for every node in the group, say).
-->
<script lang="ts">
	import { readable, writable } from 'svelte/store';
	import { onDestroy } from 'svelte';
	import { adjustMode, canAdjust } from '$lib/stores/adjustMode';
	import { getGroup, setGroup } from '$lib/utils/groupContext';
	import {
		IDENTITY,
		NOTHING_HIDDEN,
		NOTHING_MOVED,
		childHide,
		childMoves,
		isIdentity,
		moveFor,
		moveFrame,
		compose,
		mapBox,
		morphRules,
		resolveFrame,
		unionBox,
		type Box,
		type Frame,
		type HideState,
		type MoveMap
	} from '$lib/utils/groupCore';

	/** Label in ADJUST mode; a named group also publishes its members' bounding
	    box to an enclosing group, so an outer camera can `fit` the whole group. */
	export let name = '';
	/** Placement: where the local origin sits in the parent, and the zoom. */
	export let x = 0;
	export let y = 0;
	export let scale = 1;
	/** Camera: this local rectangle fills the canvas (centred, aspect kept). */
	export let view: Box | null = null;
	/** Camera: this member, by name, fills the canvas. */
	export let fit: string | null = null;
	/** Margin round a `fit` target, as a fraction of its size (0.1 = 10%). */
	export let pad = 0;
	/** Camera: this member's centre (by name), or this local point, at the canvas centre. */
	export let focus: string | [number, number] | null = null;
	/** Zoom for `focus`. */
	export let zoom = 1;
	/** Members to hide on THIS slide, by name — or a nested group's name, which
	    hides all of it. Hidden is `visibility: hidden`, not removed: the part
	    keeps its box and its morph name, so it fades out (or in) as it glides
	    rather than popping. In ADJUST it shows faint instead, still draggable. */
	export let hide: string[] = [];
	/** Members to put somewhere else on THIS slide, by name — or a nested group's
	    name, which moves all of it: `{ db: { x: 480, y: 0, scale: 1.2 } }`. x/y are
	    the drawing's units, `scale` is about the part's own centre. The part's
	    source x/y stay where it is drawn, and a drag in ADJUST saves those. */
	export let move: MoveMap = {};
	/** Name every named member for a View-Transition morph:
	    `view-transition-name: <morph>-<name>`. Nested groups inherit it. */
	export let morph: string | null = null;
	/** Only while these transition kinds run (`html[data-vt-kind]`, from the
	    page's `transition` in pages.ts) — so paging to an unrelated neighbour
	    with a plain 'slide' leaves the parts alone. Omit to name them always. */
	export let morphOn: string | string[] | null = null;
	/** Animate changes WITHIN the slide: when the camera, a placement or `hide`
	    changes, every member glides to its new box over this many seconds
	    (ordinary CSS transitions — any browser, no deck setup). 0 = jump.
	    Off while ADJUST is on, and under prefers-reduced-motion. Nested groups
	    inherit it. Across slides, use `morph` instead. */
	export let glide = 0;
	/** The canvas a camera fills. Match the deck's width/height. */
	export let canvasWidth = 1920;
	export let canvasHeight = 1080;

	/** Inline style — custom properties only, since the element draws no box. */
	export let style: string = '';
	/** DOM id for the root element. */
	export let id: string = '';
	/** Extra class(es) for the root element (global CSS / a script hook). */
	let klass: string = '';
	export { klass as class };

	const parent = getGroup();
	const parentFrame = parent?.frame ?? readable<Frame>(IDENTITY);
	const parentHidden = parent?.hidden ?? readable<HideState>(NOTHING_HIDDEN);
	const parentMorph = parent?.morph ?? readable<string | null>(null);
	const parentMoves = parent?.moves ?? readable<MoveMap>(NOTHING_MOVED);

	const moves = writable<MoveMap>(NOTHING_MOVED);
	$: moves.set(childMoves($parentMoves, move));

	const hidden = writable<HideState>(NOTHING_HIDDEN);
	$: hidden.set(childHide($parentHidden, name, hide));
	const morphPrefix = writable<string | null>(null);
	$: morphPrefix.set(morph ?? $parentMorph);
	const parentGlide = parent?.glide ?? readable(0);
	const glideSeconds = writable(0);
	$: glideSeconds.set(Number.isFinite(glide) && glide > 0 ? glide : $parentGlide);

	// Named members' LOCAL boxes, for fit/focus by name.
	const members = writable<Map<object, { name: string; box: Box }>>(new Map());
	const sameBox = (a: Box, b: Box) =>
		a.x === b.x && a.y === b.y && a.width === b.width && a.height === b.height;

	const frame = writable<Frame>(IDENTITY);
	setGroup({
		frame,
		moves,
		hidden,
		morph: morphPrefix,
		glide: glideSeconds,
		register(key, memberName, box) {
			members.update((map) => {
				const prev = map.get(key);
				if (prev && prev.name === memberName && sameBox(prev.box, box)) return map;
				const next = new Map(map);
				next.set(key, { name: memberName, box: { ...box } });
				return next;
			});
		},
		withdraw(key) {
			members.update((map) => {
				if (!map.has(key)) return map;
				const next = new Map(map);
				next.delete(key);
				return next;
			});
		}
	});

	// Rebuilt whenever membership changes, so the frame below re-resolves with it.
	$: lookup = (target: string): Box | undefined => {
		for (const m of $members.values()) if (m.name === target) return m.box;
		return undefined;
	};

	$: resolved = resolveFrame({ x, y, scale, view, fit, pad, focus, zoom }, lookup, canvasWidth, canvasHeight);
	// Moved by an enclosing group's `move` (by this group's name): applied on top,
	// about the group's own extent in the parent.
	$: extent = unionBox([...$members.values()].map((m) => m.box));
	$: selfMove = moveFrame(moveFor($parentMoves, name), mapBox(resolved.frame, extent ?? { x: 0, y: 0, width: 0, height: 0 }));
	$: moved = !isIdentity(selfMove);
	$: local = compose(selfMove, resolved.frame);
	$: frame.set(compose($parentFrame, local));

	// Forward members up, mapped into the parent's space — so an outer camera can
	// aim at a part of this group — plus, when named, the group's own extent.
	const selfKey = {};
	let forwarded = new Set<object>();
	$: if (parent) {
		const now = new Set<object>();
		for (const [key, m] of $members) {
			parent.register(key, m.name, mapBox(local, m.box));
			now.add(key);
		}
		if (name && extent) {
			parent.register(selfKey, name, mapBox(local, extent));
			now.add(selfKey);
		}
		for (const key of forwarded) if (!now.has(key)) parent.withdraw(key);
		forwarded = now;
	}
	onDestroy(() => {
		for (const key of forwarded) parent?.withdraw(key);
	});

	// The morph names, as one rule per member (members carry `data-gp-morph`).
	// Only the group that SETS `morph` writes them; a nested group inheriting the
	// prefix has its members forwarded up here, so they're covered too. A style
	// element rather than inline names, so `morphOn` can scope them to a
	// transition kind — an inline name would be on for every navigation.
	$: morphCss = morph ? morphRules(morph, [...$members.values()].map((m) => m.name), morphOn) : '';

	// ADJUST: outline the members' extent on the canvas, and say who's in charge.
	$: editing = $canAdjust && $adjustMode;
	$: outline = editing ? unionBox([...$members.values()].map((m) => mapBox($frame, m.box))) : null;
	$: label = (moved ? 'moved · ' : '') + (() => {
		const r = resolved.frame;
		const zoomText = `×${+r.s.toFixed(3)}`;
		switch (resolved.source) {
			case 'view': return `view · ${zoomText}`;
			case 'fit': return `fit ${fit} · ${zoomText}`;
			case 'focus': return `focus ${typeof focus === 'string' ? focus : focus?.join(',')} · ${zoomText}`;
			default: return `${Math.round(x)},${Math.round(y)} · ${zoomText}`;
		}
	})();
</script>

<div class="group {klass}" id={id || undefined} style="display: contents; {style}">
	<slot />
	{#if morphCss}
		{@html `<style>${morphCss}</style>`}
	{/if}
	{#if outline}
		<div
			class="group-outline gp-chrome no-print"
			style="left:{outline.x}px; top:{outline.y}px; width:{outline.width}px; height:{outline.height}px;"
		>
			<span class="group-label">{name ? name + ' · ' : ''}{label}</span>
		</div>
	{/if}
</div>

<style>
	/* ADJUST-only: the group's extent. Never takes a pointer, so every member
	   underneath stays grabbable. Dotted and warm, to read as "a set of Blocks"
	   rather than one more Block (those are dashed and blue). */
	.group-outline {
		position: absolute;
		box-sizing: border-box;
		outline: 2px dotted var(--adjust-warn-bg, #f0a33e);
		outline-offset: 8px;
		pointer-events: none;
		z-index: 34;
	}
	.group-label {
		position: absolute;
		left: 0;
		bottom: calc(100% + 10px);
		font-size: 0.55em;
		font-family: 'Fira Code', monospace;
		white-space: nowrap;
		padding: 0 0.4em;
		background: var(--adjust-warn-bg, #f0a33e);
		color: var(--adjust-warn-fg, #1a1a1a);
		border-radius: 3px;
	}
</style>
