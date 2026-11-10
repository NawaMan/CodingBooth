// Client half of deck structure editing — capability flag + fetch helpers for
// the dev-only page-add / page-remove / page-duplicate / page-rename / page-refs
// endpoints.
//
// canEditDeck is a store (not a bare import.meta.env.DEV const) so:
//   1. tests can force the built-site refusal path
//   2. Vite cannot dead-code-eliminate the NOT ALLOWED UI in production builds
//      (same lesson as canSave / ADJUST)

import { writable } from 'svelte/store';
import type { PageTemplate } from '$lib/deckEdit/pageEditCore';

export const canEditDeck = writable<boolean>(import.meta.env.DEV);

/** Is Overview currently in EDIT mode? Not persisted — close Overview resets it. */
export const overviewEditMode = writable(false);

const ADD_ENDPOINT = '/__geekpresent/page-add';
const REMOVE_ENDPOINT = '/__geekpresent/page-remove';
const DUPLICATE_ENDPOINT = '/__geekpresent/page-duplicate';
const RENAME_ENDPOINT = '/__geekpresent/page-rename';
const REFS_ENDPOINT = '/__geekpresent/page-refs';

/** A route file that links to a slide, and how many times. */
export type SlideRef = { file: string; count: number };

export type PageEditResponse = {
	ok?: boolean;
	error?: string;
	file?: string;
	path?: string;
	/** Rename: the files whose links were rewritten. */
	updated?: string[];
	/** Delete: files that still link to the deleted slide. */
	refs?: SlideRef[];
	deleted?: boolean;
};

async function postJson(url: string, body: unknown): Promise<PageEditResponse> {
	let res: Response;
	try {
		res = await fetch(url, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(body)
		});
	} catch {
		return { error: 'network error — is the dev server running?' };
	}
	let payload: PageEditResponse = {};
	try {
		payload = (await res.json()) as PageEditResponse;
	} catch {
		payload = { error: res.ok ? 'empty response' : `HTTP ${res.status}` };
	}
	if (!res.ok) {
		return { error: payload.error || `HTTP ${res.status}` };
	}
	return { ok: true, ...payload };
}

export async function addPage(args: {
	deck: string;
	path: string;
	title: string;
	template: PageTemplate;
	after?: string | null;
}): Promise<PageEditResponse> {
	return postJson(ADD_ENDPOINT, {
		deck: args.deck,
		path: args.path,
		title: args.title,
		template: args.template,
		after: args.after ?? null
	});
}

export async function removePage(args: {
	deck: string;
	path: string;
	/** Also delete the slide folder from disk (default: unlist only). */
	deleteFiles?: boolean;
}): Promise<PageEditResponse> {
	return postJson(REMOVE_ENDPOINT, {
		deck: args.deck,
		path: args.path,
		deleteFiles: !!args.deleteFiles
	});
}

export async function duplicatePage(args: {
	deck: string;
	path: string;
	newPath: string;
	title: string;
}): Promise<PageEditResponse> {
	return postJson(DUPLICATE_ENDPOINT, args);
}

export async function renamePage(args: {
	deck: string;
	path: string;
	newPath: string;
	title: string;
}): Promise<PageEditResponse> {
	return postJson(RENAME_ENDPOINT, args);
}

/** Which route files link to a slide (shown before a delete). Empty on any failure:
    the list is advice, never a gate. */
export async function slideRefs(deck: string, path: string): Promise<SlideRef[]> {
	try {
		const res = await fetch(
			`${REFS_ENDPOINT}?deck=${encodeURIComponent(deck)}&path=${encodeURIComponent(path)}`
		);
		if (!res.ok) return [];
		const data = (await res.json()) as { refs?: SlideRef[] };
		return Array.isArray(data.refs) ? data.refs : [];
	} catch {
		return [];
	}
}
