// The EDIT window's tabs, kept across reloads (pure).
//
// The editor page reloads more often than it looks: Vite reloads it when the dev
// server restarts (after editing vite.config / the dev plugins), and HMR reloads
// it when a $lib file it imports is saved — which is exactly what this editor is
// for. So the open tabs, the active one and any UNSAVED buffer live in
// sessionStorage and come back on load. A draft keeps the fingerprint of the
// disk version it was edited from, so saving it after the file changed on disk
// is refused, not silently clobbering.

export interface Draft {
	content: string;
	/** Fingerprint of the disk version the draft was edited from. */
	fingerprint: string;
}

export interface IdeSession {
	tabs: string[];
	active: string | null;
	drafts: Record<string, Draft>;
	/** `ts` of the last EDIT payload already opened, so a reload does not
	    re-activate the slide page over the tab the author moved to. */
	payloadTs: number;
}

export const IDE_SESSION_KEY = 'gp-source-ide';

export function emptySession(): IdeSession {
	return { tabs: [], active: null, drafts: {}, payloadTs: 0 };
}

/** Parse a stored session. Total: junk or a missing key yields an empty session,
    and bad entries are dropped one by one rather than losing the rest. */
export function parseSession(raw: unknown): IdeSession {
	let obj: unknown = raw;
	if (typeof raw === 'string') {
		try {
			obj = JSON.parse(raw);
		} catch {
			return emptySession();
		}
	}
	if (!obj || typeof obj !== 'object') return emptySession();
	const o = obj as Record<string, unknown>;
	const tabs = Array.isArray(o.tabs)
		? o.tabs.filter(
				(t, i, all): t is string => typeof t === 'string' && !!t && all.indexOf(t) === i
			)
		: [];
	const active =
		typeof o.active === 'string' && tabs.includes(o.active) ? o.active : (tabs[0] ?? null);
	const drafts: Record<string, Draft> = {};
	if (o.drafts && typeof o.drafts === 'object') {
		for (const [file, d] of Object.entries(o.drafts as Record<string, unknown>)) {
			const draft = d as Record<string, unknown> | null;
			if (
				tabs.includes(file) &&
				draft &&
				typeof draft.content === 'string' &&
				typeof draft.fingerprint === 'string'
			) {
				drafts[file] = { content: draft.content, fingerprint: draft.fingerprint };
			}
		}
	}
	const payloadTs =
		typeof o.payloadTs === 'number' && Number.isFinite(o.payloadTs) ? o.payloadTs : 0;
	return { tabs, active, drafts, payloadTs };
}

export function encodeSession(s: IdeSession): string {
	return JSON.stringify(s);
}

/** Open `file` (appended if new) and make it active. */
export function openTab(s: IdeSession, file: string): IdeSession {
	return { ...s, tabs: s.tabs.includes(file) ? s.tabs : [...s.tabs, file], active: file };
}

/** Close `file`; if it was active, its right neighbour (else left) takes over.
    Its draft goes with it. */
export function closeTab(s: IdeSession, file: string): IdeSession {
	const i = s.tabs.indexOf(file);
	if (i < 0) return s;
	const tabs = s.tabs.filter((t) => t !== file);
	const active = s.active === file ? (tabs[i] ?? tabs[i - 1] ?? null) : s.active;
	const drafts = { ...s.drafts };
	delete drafts[file];
	return { ...s, tabs, active, drafts };
}

/** Record or clear (`null`) the unsaved buffer of a tab. */
export function setDraft(s: IdeSession, file: string, draft: Draft | null): IdeSession {
	const drafts = { ...s.drafts };
	if (draft && s.tabs.includes(file)) drafts[file] = draft;
	else delete drafts[file];
	return { ...s, drafts };
}

/** The last segment of a path, for a tab label; the parent folder too when two
    open tabs share a name (`+page.svelte` everywhere). */
export function tabLabel(file: string, tabs: readonly string[]): string {
	const name = file.slice(file.lastIndexOf('/') + 1);
	const twins = tabs.filter((t) => t !== file && t.slice(t.lastIndexOf('/') + 1) === name);
	if (!twins.length) return name;
	const parts = file.split('/');
	return parts.length > 1 ? `${parts[parts.length - 2]}/${name}` : name;
}
