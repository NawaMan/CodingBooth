<!--
  Unscaled source editor — opened by ViewSource/SourceView/☰ EDIT into a separate window.

  Why a window: the slide canvas uses CSS transform: scale(...). Monaco's caret
  and glyph metrics are computed in untransformed CSS pixels, so inside the
  canvas the caret drifts. Here there is no scale: 1 CSS px = 1 layout px.

  Under `vite dev` it is a small IDE over src/routes + src/lib: a file tree, one
  tab per open file, Ctrl/Cmd+click on an import to open it. The EDIT that opened
  the window opens (or focuses) that slide's page. On a static host it is what it
  always was: the one page, read-only.

  SAVE    — Ctrl/Cmd+S, or Alt+. then s — write the ACTIVE tab; refused when the
            file changed on disk since it was loaded (CONFLICT), never clobbered.
  REFRESH — Ctrl/Cmd+Shift+R, or Alt+. then r — re-read the active tab from disk.
  CLOSE   — Esc, or Alt+. then c — leave the editor; confirms if any tab is dirty.

  Alt+. arms R/S/C for a few seconds (amber bar). Using any of those letters, or
  pressing Alt+. again, ends arm mode — so SAVE does not leave C live for a stray close.
  Keys are taken in the CAPTURE phase so Monaco cannot swallow Esc / the armed letters.

  Tabs and unsaved buffers survive a reload (ideSessionCore): saving a $lib file
  this window imports, or a dev-server restart, reloads it.
-->
<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { browser } from '$app/environment';
	import { base } from '$app/paths';
	import { loadPageSource } from '$lib/stores/sourceSave';
	import {
		SOURCE_EDIT_STORAGE_KEY,
		isSourceEditMessage,
		parseSourceEditPayload,
		type SourceEditPayload
	} from '$lib/source/sourceEditSession';
	import { sourceEditKeyIntent } from '$lib/source/sourceEditKeyCore';
	import {
		IDE_SESSION_KEY,
		closeTab,
		emptySession,
		encodeSession,
		openTab,
		parseSession,
		setDraft,
		tabLabel,
		type Draft,
		type IdeSession
	} from '$lib/source/ideSessionCore';
	import { listFiles, loadFile, resolveImport, saveFile, type Failure } from '$lib/source/sourceFiles';
	import FileTree from '$lib/source/FileTree.svelte';
	import IdeEditor from '$lib/source/IdeEditor.svelte';
	import {
		navTarget,
		positionOfFile,
		positionOfRoute,
		stripBase,
		type NavKind
	} from '$lib/source/deckNavCore';
	import { EDIT_DECKS } from '$lib/source/editDecks';
	import { TREE_DEFAULT_WIDTH, clampTreeWidth } from '$lib/source/treeWidthCore';
	import { treeWidth } from '$lib/stores/treeWidth';

	let payload: SourceEditPayload | null = null;
	/** The dev file endpoints answered: tree, tabs and SAVE are live. */
	let editable = false;
	let files: string[] = [];
	let session: IdeSession = emptySession();
	/** The disk version each open tab was loaded or last saved as. */
	let disk: Record<string, { content: string; fingerprint: string }> = {};
	let dirty: Record<string, boolean> = {};
	let ide: IdeEditor;
	let tree: FileTree;
	/** Static host: the one read-only page, keyed by its display path. */
	let staticFile = '';

	// One flash slot for every action (SAVE / REFRESH / follow), parked on SAVE.
	let actionLabel = 'SAVE';
	let actionRefused = false;
	let actionTip = '';
	let actionTimer: ReturnType<typeof setTimeout> | undefined;
	const notAllowedTip = 'Save not allowed in this setup.';
	const refreshNotAllowedTip = 'Refresh not allowed in this setup.';

	// Mini chrome-arm for this window only (same idea as the deck's Alt+.).
	// While armed, r/s/c fire even with the caret inside Monaco. One letter ends arm mode.
	let keysArmed = false;
	let armTimer: ReturnType<typeof setTimeout> | undefined;
	const ARM_MS = 5000;

	function armKeys() {
		keysArmed = true;
		clearTimeout(armTimer);
		armTimer = setTimeout(() => {
			keysArmed = false;
			armTimer = undefined;
		}, ARM_MS);
	}

	function disarmKeys() {
		keysArmed = false;
		if (armTimer) {
			clearTimeout(armTimer);
			armTimer = undefined;
		}
	}

	function flashAction(label: string, ms: number, opts?: { refused?: boolean; tip?: string }) {
		actionLabel = label;
		actionRefused = !!opts?.refused;
		actionTip = opts?.tip ?? '';
		clearTimeout(actionTimer);
		actionTimer = setTimeout(() => {
			actionLabel = 'SAVE';
			actionRefused = false;
			actionTip = '';
		}, ms);
	}

	/** Say why a file call failed, in the author's terms. */
	function flashFailure(r: Failure) {
		if (r.status === 0) {
			flashAction('OFFLINE', 4000, {
				refused: true,
				tip: 'The dev server is not answering (restarting?). Your edits are kept — try again.'
			});
		} else {
			flashAction('ERROR', 4000, { refused: true, tip: r.error });
		}
	}

	// ── tree / editor divider ─────────────────────────────────────────────────
	let windowWidth = Infinity;
	$: shownTreeWidth = clampTreeWidth($treeWidth, windowWidth);
	let drag: { pointer: number; startX: number; startWidth: number } | null = null;

	function dividerDown(e: PointerEvent) {
		if (e.button !== 0) return;
		e.preventDefault();
		(e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
		drag = { pointer: e.pointerId, startX: e.clientX, startWidth: shownTreeWidth };
	}

	function dividerMove(e: PointerEvent) {
		if (!drag || e.pointerId !== drag.pointer) return;
		treeWidth.set(clampTreeWidth(drag.startWidth + e.clientX - drag.startX, windowWidth));
	}

	function dividerUp(e: PointerEvent) {
		if (!drag || e.pointerId !== drag.pointer) return;
		drag = null;
	}

	// ── session ────────────────────────────────────────────────────────────────
	let persistTimer: ReturnType<typeof setTimeout> | undefined;
	function persist() {
		clearTimeout(persistTimer);
		persistTimer = setTimeout(() => {
			try {
				sessionStorage.setItem(IDE_SESSION_KEY, encodeSession(session));
			} catch {
				/* private mode / quota — tabs just won't survive a reload */
			}
		}, 250);
	}

	$: active = session.active;

	// ── deck paging (FIRST / PREV / NEXT / LAST) ─────────────────────────────
	/** The slide EDIT was opened on, or the one a button last went to. */
	let slideRoute: string | null = null;
	$: deckPos =
		positionOfFile(EDIT_DECKS, active) ?? positionOfRoute(EDIT_DECKS, slideRoute);
	$: navTo = {
		first: navTarget(deckPos, 'first'),
		prev: navTarget(deckPos, 'prev'),
		next: navTarget(deckPos, 'next'),
		last: navTarget(deckPos, 'last')
	};

	/** Open the slide's page in a tab, and move the slides window there too. */
	async function goSlide(kind: NavKind) {
		const target = navTarget(deckPos, kind);
		if (!target) return;
		if (!(await openFile(target.file))) return;
		slideRoute = target.route;
		const deckWin = window.opener as Window | null;
		if (deckWin && !deckWin.closed) {
			try {
				deckWin.location.assign(base + target.route);
				return;
			} catch {
				/* not ours any more */
			}
		}
		flashAction('NO DECK', 4000, {
			refused: true,
			tip: 'The slides window that opened this editor is gone, so it cannot follow. Reopen EDIT from a slide.'
		});
	}
	$: if (browser) document.title = active ? `Source — ${active}` : 'Source';

	// ── files ──────────────────────────────────────────────────────────────────

	/** Open `file` in a tab (or focus its tab), loading it from disk the first
	    time. A `draft` (from a reload) replaces the loaded buffer. */
	async function openFile(file: string, opts: { line?: number; draft?: Draft } = {}): Promise<boolean> {
		if (ide.has(file)) {
			session = openTab(session, file);
			persist();
			await ide.open(file, '', opts.line);
			return true;
		}
		const r = await loadFile(file);
		if (!r.ok) {
			flashFailure(r);
			return false;
		}
		disk = { ...disk, [file]: { content: r.content, fingerprint: r.fingerprint } };
		session = openTab(session, file);
		await ide.open(file, r.content, opts.line);
		const draft = opts.draft;
		if (draft && draft.content !== r.content) {
			ide.setContent(file, draft.content);
			// The draft was edited from the version it names; if that is no longer
			// what is on disk, SAVE must refuse rather than overwrite the newer file.
			disk = { ...disk, [file]: { content: r.content, fingerprint: draft.fingerprint } };
			if (draft.fingerprint !== r.fingerprint) {
				flashAction('CHANGED', 6000, {
					refused: true,
					tip: `${file} changed on disk since your unsaved edits. SAVE will refuse; REFRESH takes the disk version.`
				});
			}
		}
		onChange(file);
		persist();
		return true;
	}

	/** Open what an EDIT asked for: a named file at a line (ADJUST's </>), or
	    else the page of the slide it came from. */
	async function openPayload(p: SourceEditPayload) {
		session = { ...session, payloadTs: p.ts };
		slideRoute = stripBase(p.route, base);
		if (p.file) {
			await openFile(p.file, { line: p.line });
			return;
		}
		const r = await loadPageSource(p.route);
		if (!r.ok || !r.file) {
			flashAction('ERROR', 4000, { refused: true, tip: r.error ?? 'could not find the page file' });
			return;
		}
		await openFile(r.file);
	}

	async function start() {
		session = parseSession(sessionStorage.getItem(IDE_SESSION_KEY));
		payload = parseSourceEditPayload(sessionStorage.getItem(SOURCE_EDIT_STORAGE_KEY));
		if (!payload?.canSave) {
			if (payload) await showStatic(payload);
			return;
		}
		const listed = await listFiles();
		if (!listed.ok) {
			flashFailure(listed);
			await showStatic(payload);
			return;
		}
		files = listed.files;
		editable = true;
		slideRoute = stripBase(payload.route, base);

		const restore = session;
		session = { ...emptySession(), payloadTs: restore.payloadTs };
		for (const file of restore.tabs) await openFile(file, { draft: restore.drafts[file] });
		if (payload.ts !== restore.payloadTs) await openPayload(payload);
		else if (restore.active && ide.has(restore.active)) await openFile(restore.active);
		persist();
	}

	/** Static host (or no dev endpoints): the one page EDIT was opened on, read-only. */
	async function showStatic(p: SourceEditPayload) {
		editable = false;
		staticFile = p.path || 'page.svelte';
		session = openTab(emptySession(), staticFile);
		if (ide.has(staticFile)) ide.setContent(staticFile, p.source);
		await ide.open(staticFile, p.source);
	}

	function onMessage(event: MessageEvent) {
		if (event.origin !== window.location.origin) return;
		if (!isSourceEditMessage(event.data)) return;
		const p = parseSourceEditPayload(event.data);
		if (!p || p.ts === payload?.ts) return;
		payload = p;
		if (editable) openPayload(p);
		else showStatic(p);
	}

	function onChange(file: string) {
		const base = disk[file];
		const buffer = ide.getContent(file);
		if (!base || buffer === null) return;
		const isDirty = buffer !== base.content;
		if (dirty[file] !== isDirty) dirty = { ...dirty, [file]: isDirty };
		if (!editable) return;
		session = setDraft(session, file, isDirty ? { content: buffer, fingerprint: base.fingerprint } : null);
		persist();
	}

	async function onFollow(from: string, spec: string) {
		if (!editable) return;
		const r = await resolveImport(from, spec);
		if (!r.ok) {
			flashAction('NOT EDITABLE', 3600, { refused: true, tip: r.error });
			return;
		}
		await openFile(r.file);
	}

	async function closeFile(file: string) {
		if (dirty[file] && !confirm(`${file} has unsaved edits.\n\nClose it without saving?`)) return;
		ide.close(file);
		session = closeTab(session, file);
		const { [file]: _d, ...restDisk } = disk;
		const { [file]: _x, ...restDirty } = dirty;
		disk = restDisk;
		dirty = restDirty;
		if (session.active) await ide.open(session.active, '');
		persist();
	}

	// ── actions ────────────────────────────────────────────────────────────────

	async function onSave() {
		const file = session.active;
		if (!file) return;
		if (!editable) {
			flashAction('NOT ALLOWED', 2600, { refused: true, tip: notAllowedTip });
			return;
		}
		const content = ide.getContent(file);
		const base = disk[file];
		if (content === null || !base) return;
		if (content === base.content && !dirty[file]) {
			flashAction('NONE', 1600);
			return;
		}
		const r = await saveFile(file, content, base.fingerprint);
		if (!r.ok) {
			if (r.reason === 'conflict') {
				flashAction('CONFLICT', 7000, {
					refused: true,
					tip: `${file} changed on disk since you opened it. REFRESH loads the disk version (copy your edits first — it replaces them).`
				});
			} else flashFailure(r);
			return;
		}
		disk = { ...disk, [file]: { content, fingerprint: r.fingerprint } };
		onChange(file);
		flashAction('SAVED', 1600);
	}

	async function onRefresh() {
		const file = session.active;
		if (!file) return;
		if (!editable) {
			flashAction('NOT ALLOWED', 2600, { refused: true, tip: refreshNotAllowedTip });
			return;
		}
		const r = await loadFile(file);
		if (!r.ok) {
			flashFailure(r);
			return;
		}
		const buffer = ide.getContent(file);
		if (buffer === r.content) {
			disk = { ...disk, [file]: { content: r.content, fingerprint: r.fingerprint } };
			onChange(file);
			flashAction('CURRENT', 1600);
			return;
		}
		if (
			dirty[file] &&
			!confirm(
				'The editor buffer differs from the file on disk.\n\n' +
					'Reload from disk and discard the buffer?\n\n' +
					'(This picks up ADJUST SAVE and other external edits.)'
			)
		) {
			flashAction('KEEP', 1600);
			return;
		}
		disk = { ...disk, [file]: { content: r.content, fingerprint: r.fingerprint } };
		ide.setContent(file, r.content);
		onChange(file);
		flashAction('RELOADED', 1600);
	}

	function onClose() {
		const unsaved = Object.keys(dirty).filter((f) => dirty[f]);
		if (unsaved.length) {
			const ok = confirm(
				`Unsaved edits in:\n  ${unsaved.join('\n  ')}\n\nClose without saving?`
			);
			if (!ok) return;
			// Closing on purpose: don't resurrect the discarded drafts next time.
			session = { ...session, drafts: {} };
			try {
				sessionStorage.setItem(IDE_SESSION_KEY, encodeSession(session));
			} catch {
				/* ignore */
			}
		}
		window.close();
		setTimeout(() => {
			if (!window.closed) {
				document.body.insertAdjacentHTML(
					'beforeend',
					'<p class="close-fallback">You can close this tab manually.</p>'
				);
			}
		}, 100);
	}

	/**
	 * Capture-phase listener: Monaco steals Esc (and would steal bare r/s/c while
	 * the caret is in the buffer). Decisions live in sourceEditKeyCore (pure, tested).
	 */
	function onKeydown(event: KeyboardEvent) {
		const intent = sourceEditKeyIntent(event, keysArmed);
		if (intent === 'ignore') return;
		if (intent === 'close' && tree?.clearFilterIfFocused()) {
			event.preventDefault();
			return;
		}

		event.preventDefault();
		event.stopPropagation();

		switch (intent) {
			case 'arm-toggle':
				if (keysArmed) disarmKeys();
				else armKeys();
				return;
			case 'save':
				// Armed letter is one-shot; Ctrl+S does not need arm state.
				disarmKeys();
				onSave();
				return;
			case 'refresh':
				disarmKeys();
				onRefresh();
				return;
			case 'close':
				disarmKeys();
				onClose();
				return;
		}
	}

	onMount(() => {
		window.addEventListener('message', onMessage);
		// Capture = true: run before Monaco's bubble handlers.
		window.addEventListener('keydown', onKeydown, true);
		start();
		return () => {
			window.removeEventListener('message', onMessage);
			window.removeEventListener('keydown', onKeydown, true);
			disarmKeys();
		};
	});

	onDestroy(() => {
		clearTimeout(actionTimer);
		clearTimeout(persistTimer);
		disarmKeys();
	});

	$: pathLabel = active || '(no file loaded — open EDIT from a slide)';
	$: anyDirty = Object.values(dirty).some(Boolean);
	// Show flash next to whichever control last acted; default badge parks on SAVE.
	$: showFlash = actionLabel !== 'SAVE' || actionRefused;
</script>

<svelte:head>
	<title>Source</title>
</svelte:head>

<svelte:window bind:innerWidth={windowWidth} />

<div class="shell">
	<header class="bar" class:armed={keysArmed}>
		<div class="path" title={pathLabel}>{pathLabel}{#if active && dirty[active]} ●{/if}</div>
		{#if editable && deckPos}
			<nav class="deck-nav" aria-label="Slides">
				<button
					type="button"
					class="btn nav"
					disabled={!navTo.first}
					title={navTo.first ? `FIRST — ${navTo.first.title}` : 'FIRST — already there'}
					aria-label="First slide"
					on:click={() => goSlide('first')}>⏮</button
				>
				<button
					type="button"
					class="btn nav"
					disabled={!navTo.prev}
					title={navTo.prev ? `PREV — ${navTo.prev.title}` : 'PREV — this is the first slide'}
					aria-label="Previous slide"
					on:click={() => goSlide('prev')}>◀</button
				>
				<span class="deck-pos" title={deckPos.deck.slides[deckPos.index].title}
					>{deckPos.index + 1}/{deckPos.deck.slides.length}</span
				>
				<button
					type="button"
					class="btn nav"
					disabled={!navTo.next}
					title={navTo.next ? `NEXT — ${navTo.next.title}` : 'NEXT — this is the last slide'}
					aria-label="Next slide"
					on:click={() => goSlide('next')}>▶</button
				>
				<button
					type="button"
					class="btn nav"
					disabled={!navTo.last}
					title={navTo.last ? `LAST — ${navTo.last.title}` : 'LAST — already there'}
					aria-label="Last slide"
					on:click={() => goSlide('last')}>⏭</button
				>
			</nav>
		{/if}
		<div class="actions">
			<button
				type="button"
				class="btn refresh"
				disabled={!active}
				title="REFRESH — Ctrl+Shift+R, or Alt+. then R (confirms if the buffer has unsaved edits)"
				on:click={onRefresh}><span class="mn">R</span>EFRESH</button
			>
			<span class="action-wrap" class:refused={actionRefused}>
				<button
					type="button"
					class="btn save"
					disabled={!active}
					title="SAVE — Ctrl+S, or Alt+. then S"
					on:click={onSave}><span class="mn">S</span>AVE</button
				>
				{#if showFlash}
					<span class="action-pop">
						{#if actionLabel !== 'SAVE'}
							<span class="action-flash">{actionLabel}</span>
						{/if}
						{#if actionRefused && actionTip}
							<span class="action-tip" role="status">{actionTip}</span>
						{/if}
					</span>
				{/if}
			</span>
			<button
				type="button"
				class="btn close"
				title="CLOSE — Esc, or Alt+. then C (confirms if unsaved)"
				on:click={onClose}><span class="mn">C</span>LOSE{#if anyDirty} ●{/if}</button
			>
		</div>
	</header>

	<div
		class="body"
		class:with-tree={editable}
		class:dragging={drag}
		style={editable ? `grid-template-columns: ${shownTreeWidth}px 5px 1fr;` : undefined}
	>
		{#if editable}
			<FileTree bind:this={tree} {files} {active} on:open={(e) => openFile(e.detail.file)} />
			<!-- svelte-ignore a11y-no-static-element-interactions -->
			<div
				class="divider"
				role="separator"
				aria-orientation="vertical"
				aria-label="Resize the file tree"
				title="Drag to resize the file tree — double-click to reset"
				on:pointerdown={dividerDown}
				on:pointermove={dividerMove}
				on:pointerup={dividerUp}
				on:pointercancel={dividerUp}
				on:dblclick={() => treeWidth.set(TREE_DEFAULT_WIDTH)}
			></div>
		{/if}
		<section class="main">
			{#if session.tabs.length}
				<div class="tabs" role="tablist">
					{#each session.tabs as file (file)}
						<div class="tab" class:active={file === active} class:dirty={dirty[file]} title={file}>
							<button
								type="button"
								class="tab-name"
								role="tab"
								aria-selected={file === active}
								on:click={() => openFile(file)}>{tabLabel(file, session.tabs)}</button
							>
							{#if editable}
								<button
									type="button"
									class="tab-close"
									aria-label="Close {file}"
									title={dirty[file] ? 'Unsaved — close' : 'Close'}
									on:click={() => closeFile(file)}>{dirty[file] ? '●' : '×'}</button
								>
							{/if}
						</div>
					{/each}
				</div>
			{/if}
			<main class="editor">
				<IdeEditor
					bind:this={ide}
					readOnly={!editable}
					on:change={(e) => onChange(e.detail.file)}
					on:follow={(e) => onFollow(e.detail.from, e.detail.spec)}
				/>
				{#if !session.tabs.length}
					<p class="empty">
						{#if editable}
							Pick a file on the left, or open <b>☰ → EDIT</b> on a slide.
						{:else}
							No source loaded. From a slide, open <b>☰ → EDIT</b> (or SOURCE then the CodeBox
							<b>EDIT</b> button).
						{/if}
					</p>
				{/if}
			</main>
		</section>
	</div>

	{#if payload && !editable}
		<p class="hint">Read-only here (not vite dev). SAVE / REFRESH answer NOT ALLOWED.</p>
	{:else if editable}
		<p class="hint">Ctrl/Cmd+click an import to open it.</p>
	{/if}
</div>

<style>
	.shell {
		display: flex;
		flex-direction: column;
		width: 100%;
		height: 100vh;
		height: 100dvh;
		background: #1e1e1e;
		color: #d4d4d4;
		font-family: 'Fira Code', Menlo, Monaco, 'Courier New', monospace;
	}
	.bar {
		flex: 0 0 auto;
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 1em;
		padding: 0.55em 0.9em;
		background: #252526;
		border-bottom: 1px solid #333;
		min-height: 3em;
		box-sizing: border-box;
		transition: box-shadow 120ms ease;
	}
	/* Alt+. armed — same cue as the deck tool bar so R/S/C read as live. */
	.bar.armed {
		box-shadow: inset 0 0 0 2px color-mix(in srgb, #f0a33e 55%, transparent);
	}
	.bar.armed .btn .mn {
		color: #f0a33e;
	}
	.path {
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-size: 13px;
		font-weight: 600;
		color: #fff;
	}
	.deck-nav {
		flex: 0 0 auto;
		display: flex;
		align-items: center;
		gap: 0.3em;
		margin-left: auto;
	}
	.btn.nav {
		padding: 0.35em 0.6em;
		color: #c0f1ff;
	}
	.deck-pos {
		min-width: 4.5em;
		text-align: center;
		font-size: 12px;
		color: #aaa;
	}
	.actions {
		flex: 0 0 auto;
		display: flex;
		align-items: center;
		gap: 0.5em;
	}
	.btn {
		appearance: none;
		border: 1px solid #444;
		border-radius: 6px;
		padding: 0.35em 0.9em;
		font: inherit;
		font-size: 12px;
		font-weight: 700;
		letter-spacing: 0.04em;
		cursor: pointer;
		color: #f0a33e;
		background: rgba(255, 255, 255, 0.06);
	}
	.btn:hover:not(:disabled) {
		background: rgba(255, 255, 255, 0.12);
	}
	.btn:disabled {
		opacity: 0.4;
		cursor: not-allowed;
	}
	.btn.close {
		color: #ccc;
	}
	.btn.refresh {
		color: #7fd9ff;
	}
	/* Mnemonic letter on the bar buttons (R / S / C) — same underline cue as deck chrome. */
	.btn .mn {
		text-decoration: underline;
		text-underline-offset: 0.15em;
		text-decoration-thickness: 1px;
	}
	.action-wrap {
		position: relative;
	}
	.action-pop {
		position: absolute;
		top: calc(100% + 6px);
		right: 0;
		z-index: 10;
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		gap: 4px;
		pointer-events: none;
	}
	.action-flash {
		white-space: nowrap;
		padding: 0.15em 0.6em;
		border-radius: 6px;
		font-size: 11px;
		font-weight: bold;
		background: #000;
		color: #f0a33e;
		border: 1px solid rgba(255, 255, 255, 0.2);
	}
	.action-wrap.refused .action-flash {
		color: #e5484d;
		border-color: #e5484d;
	}
	.action-tip {
		max-width: 22em;
		text-align: right;
		padding: 0.3em 0.7em;
		border-radius: 6px;
		font-size: 11px;
		font-weight: bold;
		background: #000;
		color: #fff;
		border: 1px solid #e5484d;
	}
	.body {
		flex: 1 1 auto;
		min-height: 0;
		display: grid;
		grid-template-columns: 1fr;
	}
	.divider {
		cursor: col-resize;
		background: #252526;
		touch-action: none;
	}
	.divider:hover,
	.body.dragging .divider {
		background: #0e639c;
	}
	.body.dragging {
		cursor: col-resize;
		user-select: none;
	}
	.main {
		display: flex;
		flex-direction: column;
		min-width: 0;
		min-height: 0;
	}
	.tabs {
		flex: 0 0 auto;
		display: flex;
		overflow-x: auto;
		background: #252526;
		border-bottom: 1px solid #333;
		font-size: 12.5px;
	}
	.tab {
		display: flex;
		align-items: center;
		border-right: 1px solid #333;
		background: #2d2d2d;
		color: #aaa;
		flex: 0 0 auto;
	}
	.tab.active {
		background: #1e1e1e;
		color: #fff;
		box-shadow: inset 0 2px 0 #f0a33e;
	}
	.tab-name,
	.tab-close {
		border: 0;
		background: none;
		color: inherit;
		font: inherit;
		cursor: pointer;
	}
	.tab-name {
		padding: 0.45em 0.4em 0.45em 0.8em;
		white-space: nowrap;
	}
	.tab-close {
		width: 1.8em;
		padding: 0.45em 0;
		opacity: 0.6;
	}
	.tab.dirty .tab-close {
		color: #f0a33e;
		opacity: 1;
	}
	.tab-close:hover {
		opacity: 1;
		background: rgba(255, 255, 255, 0.08);
	}
	.editor {
		flex: 1 1 auto;
		min-height: 0;
		position: relative;
	}
	.empty {
		position: absolute;
		inset: 0;
		margin: 2em;
		line-height: 1.5;
		opacity: 0.85;
		pointer-events: none;
	}
	.hint {
		flex: 0 0 auto;
		margin: 0;
		padding: 0.4em 0.9em;
		font-size: 12px;
		opacity: 0.7;
		border-top: 1px solid #333;
	}
	:global(.close-fallback) {
		position: fixed;
		bottom: 1em;
		left: 50%;
		transform: translateX(-50%);
		background: #000;
		color: #fff;
		padding: 0.5em 1em;
		border-radius: 6px;
		font-size: 13px;
	}
</style>
