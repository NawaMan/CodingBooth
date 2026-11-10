<!--
  The EDIT window's editor: ONE Monaco instance, one Monaco model per open file.
  Switching tabs swaps the model and restores where the caret and scroll were, and
  each file keeps its own undo history for as long as its tab is open.

  Imports are links: Ctrl/Cmd+click on `'$lib/…'`, `'./…'` or `'../…'` raises
  `follow`, and the page opens the file. The ranges come from
  importResolveCore.importSpecifiersIn; Monaco draws the underline and the
  "Follow link" hover itself.

  Why not Code.svelte: Code holds a single buffer bound to one `code` prop, and
  portals itself out of a scaled canvas. Neither fits a window of tabs.
-->
<script lang="ts">
	import { createEventDispatcher, onMount } from 'svelte';
	import { loadMonaco, MONACO_THEME } from '$lib/utils/monacoCdn';
	import { ensureMonacoLanguage } from '$lib/utils/monacoShiki';
	import { languageFor } from './fileAccessCore';
	import { importSpecifiersIn } from './importResolveCore';

	export let readOnly = false;
	export let fontSize = 15;

	const dispatch = createEventDispatcher<{
		change: { file: string };
		follow: { from: string; spec: string };
	}>();

	// Monaco is a CDN global with no types in this repo.
	/* eslint-disable @typescript-eslint/no-explicit-any */
	let host: HTMLDivElement;
	let monaco: any;
	let editor: any;
	const models = new Map<string, any>();
	const viewStates = new Map<string, any>();
	const disposables: { dispose(): void }[] = [];
	/* eslint-enable @typescript-eslint/no-explicit-any */
	let current: string | null = null;
	let readyResolve: () => void;
	const ready = new Promise<void>((r) => (readyResolve = r));

	const FILE_SCHEME = 'gp-file';
	const LINK_SCHEME = 'gp-import';

	// A link carries its (from, spec) pair in the URI path, base64url-encoded so no
	// URI normalisation can mangle a `/` or `?` inside the specifier.
	function encodeLink(from: string, spec: string): string {
		const b64 = btoa(unescape(encodeURIComponent(JSON.stringify([from, spec]))));
		return b64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
	}
	function decodeLink(token: string): { from: string; spec: string } | null {
		try {
			const b64 = token.replace(/-/g, '+').replace(/_/g, '/');
			const [from, spec] = JSON.parse(decodeURIComponent(escape(atob(b64))));
			return typeof from === 'string' && typeof spec === 'string' ? { from, spec } : null;
		} catch {
			return null;
		}
	}

	async function init() {
		monaco = await loadMonaco();
		await ensureMonacoLanguage(monaco, 'svelte');

		const ts = monaco.languages.typescript;
		for (const defaults of [ts.typescriptDefaults, ts.javascriptDefaults]) {
			// The TS worker sees one file at a time, not the project: every `$lib/…`
			// import would be a red "cannot find module". Keep syntax errors only.
			defaults.setDiagnosticsOptions({ noSemanticValidation: true, noSuggestionDiagnostics: true });
			// Ctrl+click is ours (follow the import), not the worker's go-to-definition,
			// which can only answer "no definition found" without the project.
			defaults.setModeConfiguration({ ...defaults.modeConfiguration, definitions: false });
		}

		for (const lang of ['svelte', 'typescript', 'javascript']) {
			disposables.push(
				monaco.languages.registerLinkProvider(lang, {
					// eslint-disable-next-line @typescript-eslint/no-explicit-any
					provideLinks(model: any) {
						if (model.uri.scheme !== FILE_SCHEME) return { links: [] };
						const from = model.uri.path.slice(1);
						const links = [];
						for (let n = 1; n <= model.getLineCount(); n++) {
							for (const s of importSpecifiersIn(model.getLineContent(n))) {
								links.push({
									range: new monaco.Range(n, s.start + 1, n, s.end + 1),
									url: monaco.Uri.from({
										scheme: LINK_SCHEME,
										path: '/' + encodeLink(from, s.spec)
									}),
									tooltip: `Open ${s.spec}`
								});
							}
						}
						return { links };
					}
				})
			);
		}
		disposables.push(
			monaco.editor.registerLinkOpener({
				// eslint-disable-next-line @typescript-eslint/no-explicit-any
				open(resource: any) {
					if (resource.scheme !== LINK_SCHEME) return false;
					const link = decodeLink(resource.path.slice(1));
					if (link) dispatch('follow', link);
					return true;
				}
			})
		);

		editor = monaco.editor.create(host, {
			model: null,
			fontSize,
			fontFamily: "Fira Code, Menlo, Monaco, 'Courier New', monospace",
			fontLigatures: true,
			minimap: { enabled: true },
			automaticLayout: true,
			readOnly,
			theme: MONACO_THEME
		});
		editor.onDidChangeModelContent(() => {
			if (current) dispatch('change', { file: current });
		});
		readyResolve();
	}

	onMount(() => {
		init().catch((err) => console.warn('[EDIT] Monaco did not load:', err));
		return () => {
			editor?.dispose();
			models.forEach((m) => m.dispose());
			disposables.forEach((d) => d.dispose());
		};
	});

	$: editor?.updateOptions({ readOnly });

	/** Show `file`, creating its model from `content` the first time. A `line`
	    puts the caret there (1-based) and centres it. */
	export async function open(file: string, content: string, line?: number) {
		await ready;
		let model = models.get(file);
		if (!model) {
			const uri = monaco.Uri.from({ scheme: FILE_SCHEME, path: '/' + file });
			model = monaco.editor.createModel(content, languageFor(file), uri);
			models.set(file, model);
		}
		if (current && current !== file) viewStates.set(current, editor.saveViewState());
		current = file;
		editor.setModel(model);
		const state = viewStates.get(file);
		if (state) editor.restoreViewState(state);
		if (line && line > 0) {
			editor.setPosition({ lineNumber: line, column: 1 });
			editor.revealLineInCenter(line);
		}
		editor.focus();
	}

	export function has(file: string): boolean {
		return models.has(file);
	}

	/** The buffer of an open file (null if it has none). */
	export function getContent(file: string): string | null {
		return models.get(file)?.getValue() ?? null;
	}

	/** Replace a file's buffer (REFRESH from disk, a restored draft). */
	export function setContent(file: string, content: string) {
		const model = models.get(file);
		if (model && model.getValue() !== content) model.setValue(content);
	}

	/** Drop a file's model; the editor goes blank if it was showing. */
	export function close(file: string) {
		models.get(file)?.dispose();
		models.delete(file);
		viewStates.delete(file);
		if (current === file) {
			current = null;
			editor?.setModel(null);
		}
	}
</script>

<div class="ide-editor" bind:this={host}></div>

<style>
	.ide-editor {
		width: 100%;
		height: 100%;
	}
</style>
