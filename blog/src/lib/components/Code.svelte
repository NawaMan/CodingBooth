<script>
	// Generic code viewer/editor built on the Monaco editor (loaded from a CDN).
	// Distilled from JavaCode.svelte, but language is a parameter and it relies
	// on Monaco's built-in, language-aware folding rather than a custom
	// Java/brace-specific provider.
	//
	// Default is READ-ONLY (every deck Code/CodeBox usage). ViewSource flips
	// `readOnly={false}` under vite dev so the buffer can be typed into and
	// SAVEd back to disk.
	//
	// SCALE PORTAL: Monaco's own mouse hit-testing does not compensate for an
	// ancestor CSS `transform: scale()` — SlideDeck scales the whole canvas for
	// FITTED/SCALED display, so a click inside an in-canvas Monaco instance lands
	// on the wrong character whenever that scale isn't 1 (i.e. almost always).
	// `editorElement` therefore stays PUT at the authored (scaled) position as a
	// plain geometry placeholder — Monaco never mounts there. The real Monaco
	// node (`mountElement`) is portaled (`$lib/utils/portal`) into an unscaled,
	// `position: fixed` host appended to `<body>`, and repositioned every frame
	// to match `editorElement`'s live `getBoundingClientRect()` (which already
	// accounts for FITTED shrink, SCALED zoom and SCALED's native scroll-pan —
	// no need to know the transform math, just the resulting box). Monaco then
	// runs at true 1:1 screen pixels, so there is no scale left to mismatch.
	// Font size is scaled by the same measured ratio so the text still visually
	// tracks the deck's zoom. Inactive (SSR, or `expanded={false}` — a closed
	// CodeBox still mounts Monaco, see ViewSource.svelte) does none of this.
	import { onMount } from 'svelte';
	import { browser } from '$app/environment';

	export let code           = '';
	export let language       = 'java';
	export let width          = '1200px';
	export let height         = '600px';
	export let fontSize       = 20;   // Monaco's font (fixed px); overridable per usage.
	export let foldAllAtStart = false;
	/** When true (default), the buffer cannot be typed into. */
	export let readOnly       = true;
	/** Whether this instance is currently visible/interactive. A bare `<Code>` on a
	    slide has no collapsed state, hence default true; `CodeBox` forwards its own
	    `expanded` so a closed panel's (still-mounted) Monaco doesn't track/portal for
	    nothing. Gates the scale-portal sync loop below, not Monaco's own mount. */
	export let expanded       = true;

	// @ts-ignore
	export let revealLines = [];
	// @ts-ignore
	export let cursorLine = 1;

	/** Inline style for the root element, applied last so it wins. */
	export let style = '';
	/** DOM id for the root element. */
	export let id = '';
	/** Extra class(es) for the root element. NOTE: a slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS (global.css / roles.css / a
	    :global(...) block) or a utility class. See AGENTS.md. */
	let klass = '';
	export { klass as class };

	// @ts-ignore
	let editor;
	// @ts-ignore
	let editorElement;   // the geometry placeholder — stays at the authored, scaled position
	// @ts-ignore
	let mountElement;    // Monaco's real host — reparented unscaled, tracks editorElement's rect
	/** @type {HTMLDivElement | undefined} */
	let portalHost;      // shared unscaled `position: fixed` layer, appended to <body>
	/** @type {number | null} */
	let rafId = null;
	// SEQUENCED REVEAL: a wrapping Box (CodeBox) animates its own open/close (a
	// staggered width-then-height CSS transition, see Box.svelte) — before the
	// portal, Monaco was a DOM child of that box, so its own `overflow: hidden`
	// clipped/revealed the (fixed-size) code together with the border, reading as
	// one "unfurl". Portaled content sits outside that box, so it can no longer be
	// clipped by it — showing it immediately would read as a full-size rectangle
	// sliding in, competing with the border's separate unfurl. Instead: keep
	// tracking position (so nothing has to "catch up" once shown) but stay hidden
	// until the nearest clipping ancestor's OWN box stops changing — geometric, not
	// tied to Box's own transition properties/timing, so it degrades safely if that
	// CSS ever changes. Watching the PLACEHOLDER's own rect isn't enough: a normal-
	// flow child lays out at its full authored size regardless of an `overflow:
	// hidden` ancestor's current (still-animating) size, so its rect settles the
	// moment the ancestor's position stops moving — well before the ancestor's own
	// clip WINDOW (its width/height) finishes growing.
	let revealed = false;
	/** @type {{ left: number, top: number, width: number, height: number } | null} */
	let lastRect = null;
	let stableFrames = 0;
	const SETTLE_EPSILON = 0.5; // px tolerance for transition-end float jitter
	const SETTLE_FRAMES = 3;    // consecutive matching frames before "settled"
	/** The nearest ancestor that visually clips `editorElement` (an open CodeBox's
	    `.img-box`, typically) — resolved once and cached; `null` once resolution has
	    been attempted and found nothing (a bare `<Code>`, not inside a clipping Box),
	    so there is nothing to wait on and `editorElement` itself gates the reveal. */
	// @ts-ignore
	let clipTarget;

	function resolveClipTarget() {
		// @ts-ignore
		if (clipTarget !== undefined || !editorElement) return;
		let node = editorElement.parentElement;
		while (node && node !== document.body) {
			const cs = getComputedStyle(node);
			if (cs.overflowX === 'hidden' || cs.overflowY === 'hidden' || cs.overflow === 'clip') {
				clipTarget = node;
				return;
			}
			node = node.parentElement;
		}
		clipTarget = null;
	}

	function ensurePortalHost() {
		if (portalHost || !browser) return;
		portalHost = document.createElement('div');
		portalHost.className = 'code-portal-host';
		document.body.appendChild(portalHost);
	}

	/** Reparent (idempotent) and position/size the Monaco host to match the placeholder's
	    live on-screen box, scaling its font by the same ratio — read every frame, never
	    assumed. Re-checking the parent here (rather than a one-shot move) is what makes
	    this self-healing across HMR/remounts without depending on Svelte re-invoking an
	    action's `update` for a derived value — which, empirically, it does not. */
	function syncPortal() {
		// @ts-ignore
		if (!editorElement || !mountElement || !portalHost) return;
		if (mountElement.parentElement !== portalHost) portalHost.appendChild(mountElement);
		const rect = editorElement.getBoundingClientRect();
		mountElement.style.left   = `${rect.left}px`;
		mountElement.style.top    = `${rect.top}px`;
		mountElement.style.width  = `${rect.width}px`;
		mountElement.style.height = `${rect.height}px`;

		if (!revealed) {
			resolveClipTarget();
			// @ts-ignore
			const settleRect = (clipTarget ?? editorElement).getBoundingClientRect();
			const moved =
				!lastRect ||
				Math.abs(settleRect.left - lastRect.left) > SETTLE_EPSILON ||
				Math.abs(settleRect.top - lastRect.top) > SETTLE_EPSILON ||
				Math.abs(settleRect.width - lastRect.width) > SETTLE_EPSILON ||
				Math.abs(settleRect.height - lastRect.height) > SETTLE_EPSILON;
			stableFrames = moved ? 0 : stableFrames + 1;
			lastRect = {
				left: settleRect.left,
				top: settleRect.top,
				width: settleRect.width,
				height: settleRect.height
			};
			if (stableFrames >= SETTLE_FRAMES) {
				revealed = true;
				mountElement.style.visibility = 'visible';
			}
		}

		// @ts-ignore
		if (!editor) return;
		const naturalWidth = editorElement.offsetWidth;
		const scale = naturalWidth > 0 ? rect.width / naturalWidth : 1;
		const scaledFontSize = Number.isFinite(scale) && scale > 0 ? fontSize * scale : fontSize;
		// @ts-ignore
		editor.updateOptions({ fontSize: scaledFontSize });
		// @ts-ignore
		editor.layout({ width: rect.width, height: rect.height });
	}

	function portalLoop() {
		syncPortal();
		rafId = requestAnimationFrame(portalLoop);
	}

	// Drive the sync loop only while this instance is actually visible — a raf loop per
	// open code panel is cheap; one per closed panel (which still mounted Monaco, see
	// ViewSource.svelte) would not be. Hide (rather than detach) the mount node when
	// collapsing, so a frozen last-known position never flashes on the next open.
	$: if (browser) {
		ensurePortalHost();
		// @ts-ignore
		if (mountElement) {
			if (expanded) {
				mountElement.style.display = '';
			} else {
				mountElement.style.display = 'none';
				mountElement.style.visibility = 'hidden';
				revealed = false;
				lastRect = null;
				stableFrames = 0;
			}
		}
		if (expanded) {
			if (rafId == null) rafId = requestAnimationFrame(portalLoop);
		} else if (rafId != null) {
			cancelAnimationFrame(rafId);
			rafId = null;
		}
	}

	// Local edits while the parent still holds the prop from the last `?raw` import.
	// HMR updates `code`; we only re-sync the model when the buffer is clean.
	let dirty = false;

	/** Whether `target` lands inside the portaled Monaco node — the escape hatch a
	    wrapping `Box` uses (`containsExternal`) so a click on the code doesn't read
	    as "outside" and collapse it. See the SCALE PORTAL comment above. */
	// @ts-ignore
	export function containsPortaled(target) {
		return !!(portalHost && target instanceof Node && portalHost.contains(target));
	}
	/** Current buffer — Monaco when live, else the prop (jsdom / before mount). */
	export function getValue() {
		// @ts-ignore
		if (editor) return editor.getValue();
		return code;
	}

	/** True after the user has typed something that differs from `code`. */
	export function isDirty() {
		return dirty;
	}

	/** Clear the dirty flag (e.g. after a successful SAVE, before HMR lands). */
	export function markClean() {
		dirty = false;
	}

	/**
	 * Force the buffer to `next` and clear dirty (REFRESH from disk).
	 * @param {string} next
	 */
	export function setValue(next) {
		// @ts-ignore
		if (editor) editor.setValue(next);
		dirty = false;
	}

	$: {
		// @ts-ignore
		revealTheLines(revealLines);
	}

	// Keep the model in step with the prop when the user has not typed, and keep
	// Monaco's readOnly option in step with the prop (dev vs build).
	$: syncFromProps(code, readOnly);

	// @ts-ignore
	function syncFromProps(nextCode, nextReadOnly) {
		// @ts-ignore
		if (!editor) return;
		// @ts-ignore
		editor.updateOptions({ readOnly: nextReadOnly });
		if (dirty) return;
		// @ts-ignore
		if (editor.getValue() !== nextCode) {
			// @ts-ignore
			editor.setValue(nextCode);
		}
	}

	// @ts-ignore
	function unfoldLines(lineNumbers) {
		// @ts-ignore
		lineNumbers.forEach(lineNumber => {
			if (Object.prototype.toString.call(lineNumber) === '[object Array]') {
				setTimeout(function () {
					unfoldLines(lineNumber);
				}, 200);
				return;
			}
			// @ts-ignore
			editor.setSelection({
				startLineNumber: lineNumber,
				startColumn: 0,
				endLineNumber: lineNumber,
				endColumn: 1
			});
			// @ts-ignore
			editor.revealLine(cursorLine);
			// @ts-ignore
			editor.trigger('keyboard', 'editor.unfold');
		});
	}

	// @ts-ignore
	function revealTheLines(lines = []) {
		// @ts-ignore
		if (editor == null)
			return;

		if (lines.length === 0) {
			// @ts-ignore
			lines = revealLines;
		}

		if (foldAllAtStart) {
			setTimeout(function () {
				// @ts-ignore
				editor.trigger('keyboard', 'editor.foldAll');
				// @ts-ignore
				unfoldLines(revealLines);
			}, 200);
		} else if (revealLines.length > 0) {
			// @ts-ignore
			editor.setScrollTop(editor.getTopForLineNumber(revealLines[0]));
		}
	}

	onMount(() => {
		const script = document.createElement('script');
		script.src = 'https://cdnjs.cloudflare.com/ajax/libs/monaco-editor/0.21.2/min/vs/loader.js';
		script.onload = initMonaco;
		document.body.appendChild(script);

		return () => {
			if (rafId != null) cancelAnimationFrame(rafId);
			// @ts-ignore
			if (editor) {
				editor.dispose();
			}
			if (portalHost) {
				portalHost.remove();
				portalHost = undefined;
			}
		};
	});

	function initMonaco() {
		if (browser) {
			// Worker-backed languages (javascript / typescript) spin up the TS
			// language service in a Web Worker for diagnostics. Monaco is loaded
			// cross-origin from a CDN, so the default worker URL is cross-origin and
			// the browser blocks creating a Worker from it — which throws and leaves
			// the editor blank (java / python are tokenizer-only, so they were fine).
			// Point getWorkerUrl at a same-origin data-URL shim that importScripts the
			// CDN's workerMain, the standard cross-origin workaround for AMD Monaco.
			const monacoBase = 'https://cdnjs.cloudflare.com/ajax/libs/monaco-editor/0.21.2/min/';
			// @ts-ignore
			window.MonacoEnvironment = {
				getWorkerUrl: function () {
					return 'data:text/javascript;charset=utf-8,' + encodeURIComponent(
						`self.MonacoEnvironment = { baseUrl: '${monacoBase}' };\n` +
						`importScripts('${monacoBase}vs/base/worker/workerMain.js');`
					);
				}
			};
			// @ts-ignore
			window.require.config({
				paths: { vs: 'https://cdnjs.cloudflare.com/ajax/libs/monaco-editor/0.21.2/min/vs' }
			});
			// @ts-ignore
			window.require(['vs/editor/editor.main'], function () {
				// @ts-ignore
				editor = monaco.editor.create(mountElement, {
					value: code,
					// Monaco sizes its own font in fixed px, so it ignores the canvas
					// font-size lever — it comes from the `fontSize` prop instead.
					// Pin the family to the deck's monospace so glyph metrics match
					// the rendered text (a mismatch is another way carets drift).
					fontSize,
					fontFamily: "Fira Code, Menlo, Monaco, 'Courier New', monospace",
					fontLigatures: true,
					language: language,
					minimap: { enabled: true },
					folding: true,
					automaticLayout: true,
					readOnly,
					theme: 'vs-dark',
					foldingImportsByDefault: true
				});

				// @ts-ignore
				editor.onDidChangeModelContent(() => {
					// @ts-ignore
					dirty = editor.getValue() !== code;
				});

				revealTheLines();
			});
		}
	}
</script>

<!-- Placeholder: reserves the authored (scaled) footprint; Monaco never mounts here.
     See the SCALE PORTAL comment at the top of the script block. -->
<div bind:this={editorElement} class={klass || undefined} id={id || undefined} style="width: {width}; height: {height}; {style}"></div>
{#if browser}
	<!-- The real Monaco host, reparented into the unscaled body-level layer while
	     `expanded` — `syncPortal()` (rAF loop) keeps it created/parented/aligned. -->
	<div bind:this={mountElement} class="code-portal-mount"></div>
{/if}

<style>
	/* `position: fixed` opens its own stacking context outside SlideDeck's scaled
	   `.viewport`/`.container`, so an explicit z-index here only needs to beat their
	   z-index:auto (paints above the slide) while staying under `.overlay`'s 50 (the
	   top tool bar must stay reachable/visible over an open code panel, matching the
	   pre-portal look where the Box's own z-index:1000 was scoped to its ancestor and
	   never actually out-ranked the chrome). `pointer-events: none` so an EMPTY host
	   (no expanded Code instance right now) never eats a click meant for the page;
	   `.code-portal-mount` opts back in, since `pointer-events` inherits. */
	:global(.code-portal-host) {
		position: fixed;
		inset: 0;
		z-index: 30;
		pointer-events: none;
	}
	:global(.code-portal-mount) {
		position: fixed;
		pointer-events: auto;
		/* Starts hidden — `syncPortal()` flips this to `visible` once the placeholder's
		   rect (i.e. the wrapping Box's own open animation, if any) has settled. See the
		   SEQUENCED REVEAL comment in the script block. */
		visibility: hidden;
	}
</style>
