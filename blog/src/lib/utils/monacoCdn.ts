// The Monaco editor, loaded ONCE per page from cdnjs and shared by every Code /
// JavaCode instance.
//
// Before this module each instance appended its own `loader.js`, so a slide with
// two editors bootstrapped the AMD loader twice — and the version lived in four
// hard-coded URLs across two components. Now the version is here, the loader runs
// once, and a second editor reuses the first one's `window.monaco`.
//
// 0.52.2 is the newest Monaco with the classic AMD build (`min/vs` + a single
// `vs/base/worker/workerMain.js`). 0.53+ ships Vite-built, hash-named workers, so
// the cross-origin worker shim below has no stable file to point at; moving past
// 0.52 means bundling Monaco from npm instead of the CDN.

import { monacoTheme } from './shikiMonacoCore';

export const MONACO_VERSION = '0.52.2';
const MONACO_BASE = `https://cdnjs.cloudflare.com/ajax/libs/monaco-editor/${MONACO_VERSION}/min/`;

/** The page's one Monaco theme — see `monacoTheme`. Every editor passes this. */
export const MONACO_THEME = 'gp-dark';

// Monaco's own types never reach this repo (it is a CDN global), hence `any`.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Monaco = any;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type AmdWindow = Window & { monaco?: Monaco; require?: any; MonacoEnvironment?: unknown };

let loading: Promise<Monaco> | null = null;

/** Resolve with `window.monaco`, loading it on first call. A failed load is
    forgotten, so the next editor to mount tries again. Browser only. */
export function loadMonaco(): Promise<Monaco> {
	const w = window as AmdWindow;
	if (w.monaco?.editor) return Promise.resolve(w.monaco);
	if (!loading) {
		loading = new Promise<Monaco>((resolve, reject) => {
			const start = () => {
				// Worker-backed languages (javascript / typescript / html / css) run their
				// language service in a Web Worker. Monaco is cross-origin here, and the
				// browser refuses a Worker from a cross-origin URL — which throws and leaves
				// the editor blank. Point getWorkerUrl at a same-origin data-URL shim that
				// importScripts the CDN's workerMain: the standard workaround for AMD Monaco.
				w.MonacoEnvironment = {
					getWorkerUrl: () =>
						'data:text/javascript;charset=utf-8,' +
						encodeURIComponent(
							`self.MonacoEnvironment = { baseUrl: '${MONACO_BASE}' };\n` +
								`importScripts('${MONACO_BASE}vs/base/worker/workerMain.js');`
						)
				};
				w.require.config({ paths: { vs: `${MONACO_BASE}vs` } });
				w.require(
					['vs/editor/editor.main'],
					() => {
						w.monaco.editor.defineTheme(MONACO_THEME, monacoTheme());
						resolve(w.monaco);
					},
					reject
				);
			};
			const script = document.createElement('script');
			script.src = `${MONACO_BASE}vs/loader.js`;
			script.onload = start;
			script.onerror = () => reject(new Error(`could not load ${script.src}`));
			document.body.appendChild(script);
		}).catch((err) => {
			loading = null;
			throw err;
		});
	}
	return loading;
}
