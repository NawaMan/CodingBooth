// Firebase web client — config + lazy init for the static blog.
//
// The blog is a static site (no backend), so all Firebase work happens in the
// browser via the modular SDK loaded on demand from the gstatic CDN (kept out of
// the page bundle; only pages that use it fetch it). Mirrors how giscus loads.
//
// ONE-TIME SETUP (a maintainer does this once):
//   1. https://console.firebase.google.com → Add project (e.g. "codingbooth-blog").
//   2. Build → Firestore Database → Create database → production mode → pick a region.
//   3. Project settings (⚙) → Your apps → Web (</>) → register an app (Hosting NOT
//      needed) → copy the `firebaseConfig` values into FIREBASE_CONFIG below.
//   4. Firestore → Rules → paste the contents of `blog/firestore.rules` → Publish.
//
// The apiKey is NOT a secret (it ships in client JS by design); Firestore Security
// Rules are what protect the data. Until the config is filled in, anything built on
// this (e.g. <ViewCount/>) stays inert.

export const FIREBASE_CONFIG = {
	apiKey: 'AIzaSyBwUNkiBZSARlnkxgAQ5z3luARjGmAh0vc',
	authDomain: 'codingbooth-blog.firebaseapp.com',
	projectId: 'codingbooth-blog',
	storageBucket: 'codingbooth-blog.firebasestorage.app',
	messagingSenderId: '473345151433',
	appId: '1:473345151433:web:ec8a8ca9cf5cfe139a9818'
};

export const firebaseConfigured = !FIREBASE_CONFIG.apiKey.startsWith('REPLACE');

// Firebase JS SDK on the gstatic CDN (bump the version when you want to upgrade).
const SDK = 'https://www.gstatic.com/firebasejs/10.12.2';

// eslint-disable-next-line @typescript-eslint/no-explicit-any
let _app: any;

async function getApp() {
	const { initializeApp, getApps } = await import(/* @vite-ignore */ `${SDK}/firebase-app.js`);
	if (!_app) _app = getApps().length ? getApps()[0] : initializeApp(FIREBASE_CONFIG);
	return _app;
}

/** Lazily load Firestore and return the db handle plus the firestore module (doc/getDoc/…). */
export async function getDb() {
	const app = await getApp();
	const fs = await import(/* @vite-ignore */ `${SDK}/firebase-firestore.js`);
	return { db: fs.getFirestore(app), fs };
}

/** Lazily load Firebase Auth and return the auth instance plus the auth module
 * (GoogleAuthProvider, signInWithPopup, onAuthStateChanged, …). */
export async function getAuthModule() {
	const app = await getApp();
	const authMod = await import(/* @vite-ignore */ `${SDK}/firebase-auth.js`);
	return { auth: authMod.getAuth(app), authMod };
}
