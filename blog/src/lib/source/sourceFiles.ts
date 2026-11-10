// Client half of the EDIT window's file endpoints (dev only; the server half is
// devFilePlugin.ts). Every call resolves — a failure comes back as `ok: false`
// with the server's own explanation — so the editor never has to catch.

const TREE = '/__geekpresent/file-tree';
const LOAD = '/__geekpresent/file-load';
const SAVE = '/__geekpresent/file-save';
const RESOLVE = '/__geekpresent/file-resolve';

export type Failure = {
	ok: false;
	status: number;
	error: string;
	reason?: string;
	fingerprint?: string;
};

async function call<T>(url: string, init?: RequestInit): Promise<({ ok: true } & T) | Failure> {
	try {
		const res = await fetch(url, init);
		const data = await res.json().catch(() => ({}));
		if (!res.ok) {
			return {
				ok: false,
				status: res.status,
				error: data.error || `HTTP ${res.status}`,
				reason: data.reason,
				fingerprint: data.fingerprint
			};
		}
		return { ok: true, ...(data as T) };
	} catch (err) {
		// The dev server is down or restarting (status 0).
		return { ok: false, status: 0, error: err instanceof Error ? err.message : String(err) };
	}
}

/** Every editable file in the project. */
export function listFiles() {
	return call<{ files: string[] }>(TREE);
}

/** A file's content and the fingerprint a later save must quote. */
export function loadFile(file: string) {
	return call<{ file: string; content: string; fingerprint: string }>(
		`${LOAD}?path=${encodeURIComponent(file)}`
	);
}

/** Write `content`, refused (409, `reason: 'conflict'`) if the file is no longer
    the version `fingerprint` names. Returns the new fingerprint. */
export function saveFile(file: string, content: string, fingerprint: string) {
	return call<{ file: string; fingerprint: string }>(SAVE, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ path: file, content, fingerprint })
	});
}

/** The project file that `spec`, imported from `from`, names. */
export function resolveImport(from: string, spec: string) {
	return call<{ file: string }>(
		`${RESOLVE}?from=${encodeURIComponent(from)}&spec=${encodeURIComponent(spec)}`
	);
}
