<!--
  RemoteData — an AJAX call with a slide-safe UI around it.

  Wraps fetchRows() in the four states a live endpoint actually has, and hands
  the rows to a snippet, so a slide reads as data-first:

      <RemoteData url={feed} rowsPath="regions">
        {#snippet children(rows)}
          <BarChart data={rows} x={{ value: 'region' }} … />
          <DataTable {rows} {columns} />
        {/snippet}
      </RemoteData>

  SSR-INERT BY CONSTRUCTION. The request lives in an $effect, which never runs
  during prerender — so a server render emits the `pending` snippet (or the
  built-in "Loading…" line) and makes no network call at all. That is what lets
  a fetched slide prerender like every other one; see tests/RemoteDataSsr.ssr.test.ts.

  State precedence, in the order the blocks below test it:
    1. failed  — an error AND no rows to show (a first load that never landed)
    2. pending — loading AND no rows yet
    3. empty   — the request succeeded and returned nothing
    4. children— rows
  Note 1 and 2 both require "no rows": once a page of data is on screen, a
  failed or slow REFRESH leaves it there rather than blanking a chart mid-talk.
  The error is still readable through `bind:error` / `onerror`.

  Re-fetches whenever `url` or `params` change (so a DataTable's `bind:state`
  piped through toQuery() drives server-side paging with no extra wiring), and
  every `poll` ms when that is set. The in-flight request is aborted on each
  supersede and on teardown.

  Theme via --remote-* (dark fallbacks, matching an unthemed deck).
-->
<script lang="ts" generics="T">
	import type { Snippet } from 'svelte';
	import { untrack } from 'svelte';
	import { fetchRows } from './fetchRows';
	import { errorMessage, isAbort } from './remoteCore';
	import type { QueryParams } from './types';

	let {
		url,
		params,
		headers,
		rowsPath,
		totalPath,
		map,
		poll = 0,
		rows = $bindable([]),
		total = $bindable(0),
		loading = $bindable(true),
		error = $bindable(''),
		onload,
		onerror,
		children,
		pending,
		failed,
		empty,
		style = '',
		id = '',
		class: klass = ''
	}: {
		/** The endpoint. Relative URLs are fine and are what a deck usually
		 *  wants — import a colocated file as `./feed.json?url` so it is
		 *  hashed, bundled and base-path aware. */
		url: string;
		/** Query parameters, blanks dropped. Changing this object re-fetches —
		 *  pipe `toQuery(tableState)` in for server-side paging. */
		params?: QueryParams;
		/** Extra request headers. No server exists here: whatever you put in
		 *  one ships in the bundle, so public endpoints only. */
		headers?: Record<string, string>;
		/** Dot path to the row array (`data.items`); omit to auto-detect the
		 *  usual REST envelopes. */
		rowsPath?: string;
		/** Dot path to the total count; omit to auto-detect. */
		totalPath?: string;
		/** Reshape each record before it reaches the snippet. */
		// eslint-disable-next-line @typescript-eslint/no-explicit-any
		map?: (raw: any, index: number) => T;
		/** Re-fetch every N ms (minimum 250). 0 / unset = fetch once. */
		poll?: number;
		/** The rows (`bind:rows`) — also the snippet's first argument. */
		rows?: T[];
		/** Total count the endpoint reported (`bind:total`) — feed it straight
		 *  to DataTable's `totalCount` in server mode. */
		total?: number;
		/** True while a request is in flight (`bind:loading`). Starts true, so
		 *  a prerender shows the pending state rather than a flash of "empty". */
		loading?: boolean;
		/** Last error message, `''` when fine (`bind:error`). */
		error?: string;
		onload?: (result: { rows: T[]; total: number; payload: unknown }) => void;
		onerror?: (message: string) => void;
		/** Receives (rows, { total, loading, reload }). */
		children?: Snippet<[T[], { total: number; loading: boolean; reload: () => void }]>;
		/** Replaces the built-in "Loading…" line. */
		pending?: Snippet;
		/** Replaces the built-in error line; receives (message, reload). */
		failed?: Snippet<[string, () => void]>;
		/** Replaces the built-in "No data" line. */
		empty?: Snippet;
		/** Inline style for the root element, applied last so it wins. */
		style?: string;
		/** DOM id for the root element. */
		id?: string;
		/** Extra class(es) for the root element (global CSS / test hook — a
		 *  slide's scoped styles cannot reach inside a child component). */
		class?: string;
	} = $props();

	let controller: AbortController | undefined;
	let requestId = 0;

	/** Fetch now, superseding anything in flight. Exposed to the snippets as
	 *  `reload`, and to a parent through `bind:this`. */
	export async function reload(): Promise<void> {
		const ticket = ++requestId;
		controller?.abort();
		const aborter = new AbortController();
		controller = aborter;

		loading = true;
		error = '';

		try {
			const result = await fetchRows<T>(url, {
				params,
				headers,
				rowsPath,
				totalPath,
				map,
				signal: aborter.signal
			});
			if (ticket !== requestId) return; // a newer request already owns the UI
			rows = result.rows;
			total = result.total;
			loading = false;
			onload?.(result);
		} catch (caught) {
			if (ticket !== requestId || isAbort(caught)) return;
			error = errorMessage(caught);
			loading = false;
			onerror?.(error);
		}
	}

	// The request is identified by its URL and its params CONTENTS, not by the
	// identity of the params object — a $derived toQuery() hands us a fresh
	// object on every keystroke, and a parent re-render hands every prop back
	// through one shared signal. Comparing the serialised key is what keeps
	// either of those from firing a second HTTP request for the same data.
	const requestKey = $derived(JSON.stringify([url, params ?? null]));
	let lastKey: string | null = null;

	// $effect never runs during prerender — this is the whole SSR-inertness story.
	$effect(() => {
		const key = requestKey;
		if (key === lastKey) return;
		lastKey = key;
		untrack(() => void reload());
	});

	// Teardown only: no dependencies, so it runs once and its cleanup is the
	// component going away — at which point anything in flight is abandoned.
	$effect(() => () => controller?.abort());

	// Read through a $derived for the same reason as requestKey: a prop read in
	// an effect re-runs it on ANY parent re-render, which would keep resetting
	// the interval and could starve the poll entirely.
	const pollEvery = $derived(Number(poll) > 0 ? Math.max(250, Number(poll)) : 0);

	$effect(() => {
		if (!pollEvery) return;
		const timer = setInterval(() => void reload(), pollEvery);
		return () => clearInterval(timer);
	});
</script>

<div class="remote-data {klass}" id={id || undefined} {style}>
	{#if error && rows.length === 0}
		{#if failed}
			{@render failed(error, reload)}
		{:else}
			<div
				class="remote-status remote-failed"
				role="alert"
				style="color: var(--remote-error, #e74c3c);"
			>
				<span class="remote-message">{error}</span>
				<button class="remote-retry" type="button" onclick={() => void reload()}>Retry</button>
			</div>
		{/if}
	{:else if loading && rows.length === 0}
		{#if pending}
			{@render pending()}
		{:else}
			<div
				class="remote-status remote-pending"
				role="status"
				aria-live="polite"
				style="color: var(--remote-muted, #b8c2cc);"
			>
				<span
					class="remote-spinner"
					aria-hidden="true"
					style="border-top-color: var(--remote-accent, #4aa3df);"
				></span>
				<span class="remote-message">Loading…</span>
			</div>
		{/if}
	{:else if rows.length === 0}
		{#if empty}
			{@render empty()}
		{:else}
			<div class="remote-status remote-empty" style="color: var(--remote-muted, #b8c2cc);">
				No data
			</div>
		{/if}
	{:else}
		{@render children?.(rows, { total, loading, reload })}
	{/if}
</div>

<style>
	.remote-data {
		display: block;
		width: 100%;
	}

	.remote-status {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 0.5em;
		padding: 1.2em 0.6em;
		font-size: 0.8em;
	}

	/* Dark fallbacks ARE the theme: the main deck sets no theme class, so every
	   role must resolve, unthemed, to light-on-dark. The colour roles are written
	   INLINE on the elements above rather than here, so they survive a render
	   with no stylesheet at all — and so the SSR test can pin them. */

	.remote-retry {
		border: 1px solid currentColor;
		border-radius: 0.3em;
		background: transparent;
		color: inherit;
		cursor: pointer;
		padding: 0.15em 0.7em;
		font: inherit;
	}

	.remote-retry:hover {
		background: color-mix(in srgb, currentColor 18%, transparent);
	}

	.remote-spinner {
		width: 0.9em;
		height: 0.9em;
		border: 2px solid color-mix(in srgb, currentColor 35%, transparent);
		border-radius: 50%;
		animation: remote-spin 0.8s linear infinite;
	}

	@keyframes remote-spin {
		to {
			transform: rotate(360deg);
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.remote-spinner {
			animation: none;
		}
	}
</style>
