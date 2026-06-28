<!--
  FirebaseComments.svelte — login-gated comments backed by Firebase Auth + Firestore.

  One thread per page (keyed by location.pathname). Visitors must sign in with a
  social provider to post; everyone can read. Authors can delete their own
  comments; the MODERATOR_EMAIL account can delete any. Client-only, so it works
  on a static host. Rules live in blog/firestore.rules.

  Enabling a provider takes two things: (1) turn it on in the Firebase console
  (Authentication → Sign-in method) and add the site's domains under Authorized
  domains, and (2) list it in PROVIDERS below. Google + GitHub are on by default;
  Facebook / X / Apple are scaffolded but commented out until their apps exist.
-->
<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { firebaseConfigured, getDb, getAuthModule } from '$lib/firebase';

	// This account may delete ANY comment (must match isModerator() in firestore.rules).
	const MODERATOR_EMAIL = 'nawaman@gmail.com';

	// Sign-in buttons. `cls` is the firebase-auth provider class; for generic
	// OAuth providers (Apple) use `providerId` instead.
	const PROVIDERS = [
		{ id: 'google', label: 'Google', cls: 'GoogleAuthProvider' },
		{ id: 'github', label: 'GitHub', cls: 'GithubAuthProvider' }
		// { id: 'facebook', label: 'Facebook', cls: 'FacebookAuthProvider' },
		// { id: 'twitter', label: 'X', cls: 'TwitterAuthProvider' },
		// { id: 'apple', label: 'Apple', providerId: 'apple.com' }
	];

	let auth: any, authMod: any, db: any, fs: any;
	let user: any = null;
	let comments: any[] = [];
	let text = '';
	let busy = false;
	let errorMsg = '';
	let ready = false;
	let unsubAuth: undefined | (() => void);
	let unsubSnap: undefined | (() => void);

	const pageId = () =>
		(location.pathname || '/').replace(/[^a-zA-Z0-9]+/g, '_').replace(/^_+|_+$/g, '') || 'root';

	onMount(async () => {
		if (!firebaseConfigured) return;
		try {
			({ db, fs } = await getDb());
			({ auth, authMod } = await getAuthModule());

			const col = fs.collection(db, 'comments', pageId(), 'messages');
			const q = fs.query(col, fs.orderBy('createdAt', 'asc'));
			unsubSnap = fs.onSnapshot(
				q,
				(snap: any) => {
					comments = snap.docs.map((d: any) => ({ id: d.id, ...d.data() }));
					ready = true;
				},
				() => {
					errorMsg = 'Could not load comments.';
				}
			);

			unsubAuth = authMod.onAuthStateChanged(auth, (u: any) => (user = u));
		} catch (e) {
			errorMsg = 'Comments are unavailable right now.';
			console.warn('comments init failed', e);
		}
	});

	onDestroy(() => {
		unsubAuth?.();
		unsubSnap?.();
	});

	async function signIn(p: any) {
		errorMsg = '';
		try {
			const provider = p.providerId
				? new authMod.OAuthProvider(p.providerId)
				: new authMod[p.cls]();
			await authMod.signInWithPopup(auth, provider);
		} catch (e: any) {
			const code = e?.code ?? '';
			if (code === 'auth/account-exists-with-different-credential') {
				errorMsg = 'That email is already registered with a different sign-in provider.';
			} else if (code !== 'auth/popup-closed-by-user' && code !== 'auth/cancelled-popup-request') {
				errorMsg = `Sign-in failed (${code || 'is this provider enabled?'}).`;
			}
		}
	}

	async function doSignOut() {
		try {
			await authMod.signOut(auth);
		} catch {}
	}

	async function post() {
		const body = text.trim();
		if (!body || !user || busy) return;
		busy = true;
		errorMsg = '';
		try {
			const col = fs.collection(db, 'comments', pageId(), 'messages');
			await fs.addDoc(col, {
				text: body.slice(0, 2000),
				authorId: user.uid,
				authorName: user.displayName || 'Anonymous',
				authorPhoto: user.photoURL || null,
				createdAt: fs.serverTimestamp()
			});
			text = '';
		} catch (e) {
			errorMsg = 'Could not post your comment.';
			console.warn('post failed', e);
		} finally {
			busy = false;
		}
	}

	async function remove(c: any) {
		if (!confirm('Delete this comment?')) return;
		try {
			await fs.deleteDoc(fs.doc(db, 'comments', pageId(), 'messages', c.id));
		} catch (e) {
			errorMsg = 'Delete failed.';
			console.warn('delete failed', e);
		}
	}

	const canDelete = (c: any) =>
		!!user && (c.authorId === user.uid || (user.email === MODERATOR_EMAIL && user.emailVerified));

	function when(ts: any) {
		if (!ts?.toDate) return '';
		return ts.toDate().toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' });
	}
</script>

<section class="comments">
	<h2>Comments {#if ready && comments.length}<span class="count">({comments.length})</span>{/if}</h2>

	{#if !firebaseConfigured}
		<p class="muted">Comments aren't configured yet.</p>
	{:else}
		{#if errorMsg}<p class="error">{errorMsg}</p>{/if}

		<ul class="thread">
			{#each comments as c (c.id)}
				<li>
					{#if c.authorPhoto}<img class="avatar" src={c.authorPhoto} alt="" referrerpolicy="no-referrer" />{/if}
					<div class="body">
						<p class="meta"><span class="name">{c.authorName}</span> · <span class="date">{when(c.createdAt)}</span></p>
						<p class="text">{c.text}</p>
					</div>
					{#if canDelete(c)}<button class="del" title="Delete" on:click={() => remove(c)}>×</button>{/if}
				</li>
			{/each}
		</ul>

		{#if ready && comments.length === 0}
			<p class="muted">No comments yet — be the first.</p>
		{/if}

		{#if user}
			<div class="composer">
				<textarea bind:value={text} maxlength="2000" rows="3" placeholder="Add a comment…"></textarea>
				<div class="row">
					<span class="signed">Signed in as <strong>{user.displayName || user.email}</strong> · <button class="link" on:click={doSignOut}>sign out</button></span>
					<button class="post" on:click={post} disabled={busy || !text.trim()}>{busy ? 'Posting…' : 'Post'}</button>
				</div>
			</div>
		{:else}
			<div class="signin">
				<span>Sign in to comment:</span>
				{#each PROVIDERS as p}
					<button class="provider" on:click={() => signIn(p)}>{p.label}</button>
				{/each}
			</div>
		{/if}
	{/if}
</section>

<style>
	.comments {
		margin-top: 2.5em;
		padding-top: 1.2em;
		border-top: 1px solid #2a3a40;
	}
	.comments h2 {
		color: #7fd9ff;
		margin-bottom: 0.6em;
	}
	.count {
		opacity: 0.6;
		font-size: 0.7em;
	}
	.muted {
		opacity: 0.6;
		font-style: italic;
	}
	.error {
		color: #ff9b9b;
	}
	.thread {
		list-style: none;
		padding: 0;
		margin: 0 0 1.4em;
	}
	.thread li {
		display: flex;
		gap: 0.7em;
		align-items: flex-start;
		padding: 0.8em 0;
		border-bottom: 1px solid #1f2c30;
	}
	.avatar {
		width: 2em;
		height: 2em;
		border-radius: 50%;
		flex: 0 0 auto;
	}
	.body {
		flex: 1;
		min-width: 0;
	}
	.meta {
		margin: 0 0 0.2em;
		font-family: 'Fira Code', monospace;
		font-size: 0.8em;
		opacity: 0.7;
	}
	.name {
		color: #7fd9ff;
	}
	.text {
		margin: 0;
		white-space: pre-wrap;
		word-wrap: break-word;
		line-height: 1.5;
	}
	.del {
		flex: 0 0 auto;
		background: none;
		border: none;
		color: #ff9b9b;
		font-size: 1.2em;
		cursor: pointer;
		opacity: 0.5;
	}
	.del:hover {
		opacity: 1;
	}
	.composer textarea {
		width: 100%;
		box-sizing: border-box;
		background: #11181b;
		color: inherit;
		border: 1px solid #2a3a40;
		border-radius: 6px;
		padding: 0.6em;
		font: inherit;
		resize: vertical;
	}
	.row {
		display: flex;
		justify-content: space-between;
		align-items: center;
		margin-top: 0.5em;
		gap: 1em;
		flex-wrap: wrap;
	}
	.signed {
		font-size: 0.85em;
		opacity: 0.8;
	}
	.link {
		background: none;
		border: none;
		color: #7fd9ff;
		cursor: pointer;
		padding: 0;
		font: inherit;
	}
	.signin {
		display: flex;
		align-items: center;
		gap: 0.6em;
		flex-wrap: wrap;
	}
	.provider,
	.post {
		background: #7fd9ff;
		color: #0d1416;
		border: none;
		border-radius: 6px;
		padding: 0.45em 1em;
		font-weight: bold;
		cursor: pointer;
	}
	.provider {
		background: #1c2a30;
		color: #7fd9ff;
		border: 1px solid #2a3a40;
	}
	.post:disabled {
		opacity: 0.5;
		cursor: default;
	}
</style>
