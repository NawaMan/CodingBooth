<script>
	// Generic read-only code viewer built on the Monaco editor (loaded from a
	// CDN). Distilled from JavaCode.svelte, but language is a parameter and it
	// relies on Monaco's built-in, language-aware folding rather than a custom
	// Java/brace-specific provider.
	import { onMount } from 'svelte';
	import { browser } from '$app/environment';

	export let code           = '';
	export let language       = 'java';
	export let width          = '1200px';
	export let height         = '600px';
	export let fontSize       = 20;   // Monaco's font (fixed px); overridable per usage.
	export let foldAllAtStart = false;

	// @ts-ignore
	export let revealLines = [];
	// @ts-ignore
	export let cursorLine = 1;

	// @ts-ignore
	let editor;
	// @ts-ignore
	let editorElement;

	$: {
		// @ts-ignore
		revealTheLines(revealLines);
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
			// @ts-ignore
			if (editor) {
				editor.dispose();
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
				editor = monaco.editor.create(editorElement, {
					value: code,
					// Monaco sizes its own font in fixed px, so it ignores the canvas
					// font-size lever — it comes from the `fontSize` prop instead.
					fontSize,
					language: language,
					minimap: { enabled: true },
					folding: true,
					automaticLayout: true,
					readOnly: true,
					theme: 'vs-dark',
					foldingImportsByDefault: true
				});

				revealTheLines();
			});
		}
	}
</script>

<div bind:this={editorElement} style="width: {width}; height: {height};"></div>
