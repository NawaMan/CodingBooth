<!--
  ViewCount.svelte — a free, Firebase/Firestore-backed "👁 N views" badge.
  Drop it on a page; it counts that page on its own (keyed by location.pathname,
  one Firestore doc per URL) and shows the running total.

  Client-only (works on a static host), free on Firebase's Spark tier. Increments
  once per visitor per page via a localStorage guard — best-effort, not audit-grade
  (a determined visitor can still inflate it; App Check + the rules limit abuse).

  Config + setup live in `$lib/firebase.ts`; the matching Firestore rules are in
  `geekpresent/firestore.rules`. Until Firebase is configured, this renders nothing.
-->
<script lang="ts">
	import { onMount } from 'svelte';
	import { firebaseConfigured, getDb } from '$lib/firebase';

	let count: number | null = null;

	// Turn the page path into a safe Firestore doc id, e.g.
	// "/blog/2026-06-18.html" -> "blog_2026_06_18_html".
	const pageId = () =>
		(location.pathname || '/').replace(/[^a-zA-Z0-9]+/g, '_').replace(/^_+|_+$/g, '') || 'root';

	onMount(async () => {
		if (!firebaseConfigured) return;
		try {
			const { db, fs } = await getDb();
			const id = pageId();
			const ref = fs.doc(db, 'views', id);

			// Count this visitor once per page. setDoc+merge+increment creates the
			// doc (count: 1) if missing, or atomically bumps it otherwise.
			const key = `viewed:${id}`;
			if (!localStorage.getItem(key)) {
				await fs.setDoc(ref, { count: fs.increment(1) }, { merge: true });
				localStorage.setItem(key, '1');
			}

			const snap = await fs.getDoc(ref);
			count = snap.exists() ? (snap.data().count ?? 0) : 0;
		} catch (e) {
			// Never let a counter break the page — just stay hidden.
			console.warn('view count unavailable', e);
		}
	});
</script>

{#if firebaseConfigured && count !== null}
	<p class="viewcount">👁 {count.toLocaleString()} views</p>
{/if}

<style>
	.viewcount {
		margin-top: 2em;
		font-family: 'Fira Code', monospace;
		font-size: 0.85em;
		opacity: 0.6;
	}
</style>
