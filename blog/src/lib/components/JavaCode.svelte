<!--
  JavaCode — Monaco viewer with a hand-rolled Java folding-range provider
  (imports + brace blocks; see customFoldingRangeProvider below).

  STATUS: legacy / unverified. Prefer <Code> (or <CodeBox>) for new slides —
  Monaco's built-in language-aware folding covers Java too. This custom logic was
  written for an early, specific use of GeekPresent that is no longer in this
  project, so nothing here exercises it and it can't be tested against its
  original case. Left untouched on purpose; to be revisited later. Don't refactor
  casually.
-->
<script lang="javascript">
	import { onMount } from 'svelte';
	import { browser } from '$app/environment';

	export let javaCode       = '';
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
			if(Object.prototype.toString.call(lineNumber) === '[object Array]') {
				setTimeout(function () {
					unfoldLines(lineNumber)
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

			const highlightedLines = [2, 4, 6];

			const decorations = highlightedLines.map(line => ({
				// @ts-ignore
				range: new monaco.Range(line, 1, line, 1),
				options: {
					isWholeLine: true,
					className: 'myLineHighlight',
					linesDecorationsClassName: 'myGutterDecoration'
				}
			}));

			// @ts-ignore
			editor.deltaDecorations([], decorations);
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
			// @ts-ignore
			window.require.config({
				paths: { vs: 'https://cdnjs.cloudflare.com/ajax/libs/monaco-editor/0.21.2/min/vs' }
			});
			// @ts-ignore
			window.require(['vs/editor/editor.main'], function () {
				// @ts-ignore
				editor = monaco.editor.create(editorElement, {
					value: javaCode, fontSize,   // Monaco's font from the `fontSize` prop (fixed px, ignores the canvas lever).
					language: 'java',
					minimap: { enabled: true },
					folding: true,
					automaticLayout: true,
					readOnly: true,
					theme: "vs-dark",
					foldingImportsByDefault: true
				});

				// @ts-ignore
				monaco.languages.register({ id: 'java' });

				const customFoldingRangeProvider = {
					// @ts-ignore
					provideFoldingRanges: function (model, context, token) {
						let ranges = [];
						let importStartLine = -1;
						let importEndLine = -1;

						for (let i = 1; i <= model.getLineCount(); i++) {
							let line = model.getLineContent(i);

							// Check for import statements
							if (line.trim().startsWith('import ')) {
								if (importStartLine === -1) {
									importStartLine = i;
								}
								importEndLine = i;
							} else if (importStartLine !== -1) {
								// Add folding range for imports
								ranges.push({
									start: importStartLine,
									end: importEndLine,
									// @ts-ignore
									kind: monaco.languages.FoldingRangeKind.Imports
								});
								importStartLine = -1;
								importEndLine = -1;
							}

							// Existing code for brace folding
							if (line.trim().endsWith('{')) {
								let startLine = i;
								let endLine = findMatchingBrace(model, i);
								if (endLine > startLine) {
									ranges.push({
										start: startLine,
										end: endLine,
										// @ts-ignore
										kind: monaco.languages.FoldingRangeKind.Region
									});
								}
							}
						}

						// Check if there are imports at the end of the file
						if (importStartLine !== -1) {
							ranges.push({
								start: importStartLine,
								end: importEndLine,
								// @ts-ignore
								kind: monaco.languages.FoldingRangeKind.Imports
							});
						}

						return ranges;
					}
				};

				// @ts-ignore
				function findMatchingBrace(model, startLine) {
					let braceCount = 1;
					for (let i = startLine + 1; i <= model.getLineCount(); i++) {
						let line = model.getLineContent(i);
						braceCount += (line.match(/{/g) || []).length;
						braceCount -= (line.match(/}/g) || []).length;
						if (braceCount === 0) {
							return i;
						}
					}
					return startLine;
				}

				// @ts-ignore
				monaco.languages.registerFoldingRangeProvider('java', customFoldingRangeProvider);

				revealTheLines();
			});
		}
	}
</script>

<div bind:this={editorElement} style="width: {width}; height: {height};"></div>
