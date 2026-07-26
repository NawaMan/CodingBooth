// Client half of deck structure editing — capability flag + fetch helpers for
// the dev-only page-add / page-remove endpoints.
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

export type PageEditResponse = {
	ok?: boolean;
	error?: string;
	file?: string;
	path?: string;
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
}): Promise<PageEditResponse> {
	return postJson(REMOVE_ENDPOINT, {
		deck: args.deck,
		path: args.path
	});
}
