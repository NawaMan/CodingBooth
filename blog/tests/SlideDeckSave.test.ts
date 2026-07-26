import { render, fireEvent } from '@testing-library/svelte';
import { tick } from 'svelte';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import SlideDeck from '$lib/components/SlideDeck.svelte';
import { adjustMode, canAdjust, canSave } from '$lib/stores/adjustMode';
import { reportChange, withdrawChange } from '$lib/stores/adjustChanges';

// The ADJUST chrome across the dev/build boundary: which slides OFFER the control,
// how loudly the button announces itself, and what SAVE does where it cannot write.
//
// The regression underneath all of it: SAVE used to be gated on a bare
// `const canSave = import.meta.env.DEV`, which Vite folded to `false` in a build and
// dead-code-eliminated the whole button away — so a deployed ADJUST demo showed the
// mode with a hole where its payoff should be. `canSave` is a settable store now,
// which is both why the refusal path survives the build AND why a test can reach it
// at all (`import.meta.env.DEV` is true under vitest).

const plain = [{ path: 'stub.html', title: 'Stub' }];
// The stub URL that tests/stubs/app-stores.ts serves is /slides/stub.html, so a page
// entry at 'stub.html' IS the current slide — which is what makes the per-slide
// `adjust` flag reachable from here.
const teaches = [{ path: 'stub.html', title: 'Stub', adjust: true }];

// ADJUST and SAVE are word buttons on <Annotate>'s top-centre tool bar (`.adjust-tab` toggle /
// `.save-act` action). SAVE's outcome is a transient verdict badge (`.save-flash`), with the
// refusal reason under it (`.save-tip`). So we target the controls by class and read the verdict
// from the badge rather than from the button's own text (which stays "SAVE").
const adjustIcon = (root: ParentNode) => root.querySelector('.adjust-tab') as HTMLButtonElement | null;
const saveIcon = (root: ParentNode) => root.querySelector('.save-act') as HTMLButtonElement | null;
const flash = (root: ParentNode) => root.querySelector('.save-flash')?.textContent ?? undefined;

const mount = async (pages: typeof plain) => {
	const { container } = render(SlideDeck, { props: { pages } });
	await tick();
	return container;
};

beforeEach(() => {
	canAdjust.set(true);
	adjustMode.set(true); // the speaker has flipped the mode on
	canSave.set(true);
});
afterEach(() => {
	adjustMode.set(false);
	canSave.set(true);
});

describe('which slides offer ADJUST', () => {
	// ADJUST (the old ADJUST) is off in production by default. In THIS environment
	// import.meta.env.DEV is true, so the control is offered on every slide and the store
	// recomputes to true whatever we set — dev is the highest authority, and refusing to
	// fake that is the point. The precedence itself (including the ordinary-slide-in-a-build
	// case, which is unreachable here) is unit-tested purely in adjustAccess.test.ts.
	//
	// (The old "featured / halo" behaviour is gone: ADJUST is a bar icon now, bright when on and
	// dim when off — a slide can no longer make a corner pill glow. It is simply offered or not.)
	it('offers the control on an ordinary slide under dev', async () => {
		const container = await mount(plain);
		expect(adjustIcon(container)).toBeTruthy();
	});

	// The whole ADJUST group is gated on $canAdjust. Flipped AFTER mount on purpose: setting
	// it before would be a lie this environment refuses to tell, since SlideDeck's own
	// recompute puts it straight back to true under dev.
	it('drops ADJUST and SAVE entirely when the control is not offered', async () => {
		const container = await mount(teaches);
		canAdjust.set(false);
		await tick();
		expect(adjustIcon(container)).toBeNull();
		expect(container.querySelector('.save-btn')).toBeNull();
	});
});

describe('SAVE where it cannot write (a static build)', () => {
	it('renders as an ORDINARY, enabled control — not pre-emptively greyed out', async () => {
		canSave.set(false);
		const container = await mount(teaches);
		const save = saveIcon(container);
		expect(save).toBeTruthy();
		expect(save?.disabled).toBe(false);
		expect(container.querySelector('.save-btn.refused')).toBeNull();
	});

	// The beat the demo is built around: it answers when pressed. A control disabled from
	// the start invites the audience to assume the feature is missing or broken.
	it('answers NOT ALLOWED on click, with a tooltip saying why', async () => {
		canSave.set(false);
		const container = await mount(teaches);
		await fireEvent.click(saveIcon(container)!);
		await tick();

		expect(flash(container)).toBe('NOT ALLOWED');
		expect(container.querySelector('.save-btn.refused')).toBeTruthy();
		expect(container.querySelector('.save-tip')?.textContent).toBe(
			'Save not allowed in this setup.'
		);
	});

	it('announces the refusal, rather than only drawing it', async () => {
		canSave.set(false);
		const container = await mount(teaches);
		await fireEvent.click(saveIcon(container)!);
		await tick();
		expect(container.querySelector('.save-tip')?.getAttribute('role')).toBe('status');
	});
});

describe('SAVE under vite dev', () => {
	it('shows no refusal tooltip — it has a source tree to write to', async () => {
		const container = await mount(teaches);
		const save = saveIcon(container);
		expect(save?.disabled).toBe(false);
		expect(container.querySelector('.save-tip')).toBeNull();
		expect(container.querySelector('.save-btn.refused')).toBeNull();
	});
});

describe('SAVE follows the mode', () => {
	it('is absent while ADJUST is off, in either world', async () => {
		adjustMode.set(false);
		canSave.set(false);
		const container = await mount(teaches);
		expect(container.querySelector('.save-btn')).toBeNull();
		expect(saveIcon(container)).toBeNull();
	});
});

// A PARTIAL write is the outcome that can cost an author work. The server places
// what it can and reports the rest as `unmatched` — never guessing, which is the
// whole design of patchSource.ts. What it must NOT do is then flash SAVED at the
// author: the drags that didn't land are gone on the next reload, and the only
// evidence was a console.warn nobody had reason to open. (Lived, not theorised: a
// demo slide whose <QuickCode> sample was a byte-for-byte twin of its real Block —
// same name AND geometry — made the tag ambiguous, so one of two boxes silently
// failed to save while the button said SAVED. See tests/adjustPatch.test.ts.)
describe('SAVE that only half-lands', () => {
	const CHANGE_ID = 9001;
	let realFetch: typeof globalThis.fetch;

	/** onSave awaits saveAdjust(), which awaits fetch() and then res.json() — two
	    microtask hops past the click. A bare tick() lands between them and reads the
	    button mid-flight, still saying SAVE. Flush the queue, THEN let Svelte render. */
	const settle = async () => {
		await new Promise((r) => setTimeout(r, 0));
		await tick();
	};

	/** The dev endpoint's verdict, whatever the real one would have said. The live
	    payload is `{label, reason}` objects (see devSavePlugin); bare strings stand
	    in for a STALE dev server from before reasons existed — the client shims them. */
	type Unmatched = { label: string; reason: 'not-found' | 'ambiguous' } | string;
	const serverSays = (patched: number, unmatched: Unmatched[]) => {
		globalThis.fetch = (() =>
			Promise.resolve(
				new Response(JSON.stringify({ patched, unmatched }), {
					status: 200,
					headers: { 'content-type': 'application/json' }
				})
			)) as typeof globalThis.fetch;
	};

	beforeEach(() => {
		realFetch = globalThis.fetch;
		// One dirty tag in the page registry — without it saveAdjust() short-circuits
		// to NONE and never reaches the endpoint at all.
		reportChange({
			id: CHANGE_ID,
			kind: 'Block',
			name: 'pinned',
			dirty: true,
			oldTag: '<Block name="pinned" x={140} y={620} width={300} height={150}>',
			newTag: '<Block name="pinned" x={460} y={838} width={300} height={150}>',
			before: { x: 140, y: 620, width: 300, height: 150, z: 0 },
			after: { x: 460, y: 838, width: 300, height: 150, z: 0 }
		});
	});
	afterEach(() => {
		globalThis.fetch = realFetch;
		withdrawChange(CHANGE_ID);
	});

	it('counts what landed instead of claiming SAVED', async () => {
		serverSays(1, [{ label: 'pinned', reason: 'ambiguous' }]);
		const container = await mount(teaches);
		await fireEvent.click(saveIcon(container)!);
		await settle();

		expect(flash(container)).toBe('1 OF 2');
		expect(flash(container)).not.toBe('SAVED');
	});

	it('wears the refusal styling and says what did not land, out loud', async () => {
		serverSays(1, [{ label: 'pinned', reason: 'ambiguous' }]);
		const container = await mount(teaches);
		await fireEvent.click(saveIcon(container)!);
		await settle();

		expect(container.querySelector('.save-btn.refused')).toBeTruthy();
		const tip = container.querySelector('.save-tip');
		expect(tip?.getAttribute('role')).toBe('status'); // announced, not merely drawn
		expect(tip?.textContent).toContain('1 tag not written');
		expect(tip?.textContent).not.toContain('Save not allowed'); // the OTHER refusal
	});

	it('pluralises the count, because "1 tags not written" reads as a bug', async () => {
		serverSays(1, [
			{ label: 'a', reason: 'not-found' },
			{ label: 'b', reason: 'not-found' }
		]);
		const container = await mount(teaches);
		await fireEvent.click(saveIcon(container)!);
		await settle();

		expect(flash(container)).toBe('1 OF 3');
		expect(container.querySelector('.save-tip')?.textContent).toContain('2 tags not written');
	});

	// The tooltip must tell the TRUE story per cause — one blanket message used to
	// blame a code-sample twin for every failure, sending authors hunting for a
	// twin that didn't exist (lived too: a <Curve> whose geometry was expressions
	// on a shared const can never match literally — no twin anywhere in sight).
	it("names the TRUE cause: a tag absent in literal form gets the expressions story", async () => {
		serverSays(0, [{ label: 'road', reason: 'not-found' }]);
		const container = await mount(teaches);
		await fireEvent.click(saveIcon(container)!);
		await settle();

		const tip = container.querySelector('.save-tip')?.textContent ?? '';
		expect(tip).toContain("isn't in the source in its literal form");
		expect(tip).not.toContain('name AND geometry match another');
	});

	it('names the TRUE cause: a twin tie gets the ambiguity story', async () => {
		serverSays(0, [{ label: 'pinned', reason: 'ambiguous' }]);
		const container = await mount(teaches);
		await fireEvent.click(saveIcon(container)!);
		await settle();

		const tip = container.querySelector('.save-tip')?.textContent ?? '';
		expect(tip).toContain('name AND geometry match another');
		expect(tip).not.toContain('literal form');
	});

	it('a mixed batch tells both stories', async () => {
		serverSays(0, [
			{ label: 'road', reason: 'not-found' },
			{ label: 'pinned', reason: 'ambiguous' }
		]);
		const container = await mount(teaches);
		await fireEvent.click(saveIcon(container)!);
		await settle();

		const tip = container.querySelector('.save-tip')?.textContent ?? '';
		expect(tip).toContain('2 tags not written');
		expect(tip).toContain("isn't in the source in its literal form");
		expect(tip).toContain('name AND geometry match another');
	});

	it('tolerates the legacy string payload from a stale dev server', async () => {
		serverSays(0, ['<Block name="pinned" x={460} y={838} width={300} height={150}>']);
		const container = await mount(teaches);
		await fireEvent.click(saveIcon(container)!);
		await settle();

		// Shimmed to the commoner cause rather than crashing or claiming SAVED.
		expect(flash(container)).toBe('0 OF 1');
		expect(container.querySelector('.save-tip')?.textContent).toContain('1 tag not written');
	});

	it('still says SAVED — plainly — when every tag landed', async () => {
		serverSays(1, []);
		const container = await mount(teaches);
		await fireEvent.click(saveIcon(container)!);
		await settle();

		expect(flash(container)).toBe('SAVED');
		expect(container.querySelector('.save-btn.refused')).toBeNull();
		expect(container.querySelector('.save-tip')).toBeNull();
	});
});
