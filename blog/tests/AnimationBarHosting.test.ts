import { render, cleanup } from '@testing-library/svelte';
import { get } from 'svelte/store';
import { tick } from 'svelte';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import AnimationBar from '../src/lib/components/AnimationBar.svelte';
import { animBarSlot, hostedAnim } from '../src/lib/stores/localChrome';

// A plain <AnimationBar> is the slide's ONE central control, so it is HOSTED in the deck's
// bottom ControlBar: it registers in `hostedAnim` (so the bar reveals its animation segment)
// and portals its `.anim-bar` into the ControlBar's slot (published via `animBarSlot`). A
// SCOPED bar (scope=".set-a") governs a region and stays in the slide — it registers nothing
// and never leaves its container. See stores/localChrome + utils/portal.

// A single finite animation, enough for hasAnim to flip true.
class FakeAnimation {
	currentTime = 0;
	playState: 'idle' | 'running' | 'paused' | 'finished' = 'running';
	effect = { getComputedTiming: () => ({ endTime: 300 }) };
	play() {}
	pause() { this.playState = 'paused'; }
}

function installClock() {
	const get = () => [new FakeAnimation()] as unknown as Animation[];
	(Element.prototype as unknown as { getAnimations: () => Animation[] }).getAnimations = get;
	(Document.prototype as unknown as { getAnimations: () => Animation[] }).getAnimations = get;
}
function removeClock() {
	delete (Element.prototype as unknown as { getAnimations?: unknown }).getAnimations;
	delete (Document.prototype as unknown as { getAnimations?: unknown }).getAnimations;
}

beforeEach(installClock);
afterEach(() => {
	cleanup();
	removeClock();
	animBarSlot.set(null);
	hostedAnim.set(new Set());
});

describe('AnimationBar hosting', () => {
	it('a plain bar registers as a hosted animation and portals into the ControlBar slot', async () => {
		// Stand in for the ControlBar's published slot element.
		const slot = document.createElement('div');
		document.body.appendChild(slot);
		animBarSlot.set(slot);

		const { container } = render(AnimationBar);
		await tick();
		await tick();

		// It announces itself so the ControlBar reveals the animation segment.
		expect(get(hostedAnim).size).toBe(1);
		// And its bar node has physically moved into the slot, not left in the render tree.
		expect(slot.querySelector('.anim-bar')).not.toBeNull();
		expect(container.querySelector('.anim-bar')).toBeNull();

		slot.remove();
	});

	it('a scoped bar stays in the slide and registers nothing', async () => {
		const { container } = render(AnimationBar, { props: { scope: '.set-a' } });
		await tick();
		await tick();

		expect(get(hostedAnim).size).toBe(0);
		expect(container.querySelector('.anim-bar')).not.toBeNull();
	});

	it('barHosted={false} forces a plain bar to stay in the slide', async () => {
		const slot = document.createElement('div');
		document.body.appendChild(slot);
		animBarSlot.set(slot);

		const { container } = render(AnimationBar, { props: { barHosted: false } });
		await tick();
		await tick();

		expect(get(hostedAnim).size).toBe(0);
		expect(slot.querySelector('.anim-bar')).toBeNull();
		expect(container.querySelector('.anim-bar')).not.toBeNull();

		slot.remove();
	});

	it('unregisters from hostedAnim when destroyed', async () => {
		const slot = document.createElement('div');
		document.body.appendChild(slot);
		animBarSlot.set(slot);

		const { unmount } = render(AnimationBar);
		await tick();
		await tick();
		expect(get(hostedAnim).size).toBe(1);

		unmount();
		await tick();
		expect(get(hostedAnim).size).toBe(0);

		slot.remove();
	});

	it('a destroyed hosted bar leaves NO node behind in the slot — a successor hosts alone', async () => {
		// The SAVE → HMR duplicate: the portaled .anim-bar lives OUTSIDE its
		// component's subtree, where anchor-range teardown can miss it. The portal
		// action must evict its node on destroy, or every save strands one more
		// ANIMATE button in the ControlBar.
		const slot = document.createElement('div');
		document.body.appendChild(slot);
		animBarSlot.set(slot);

		const first = render(AnimationBar);
		await tick();
		await tick();
		expect(slot.querySelectorAll('.anim-bar')).toHaveLength(1);

		first.unmount();
		await tick();
		expect(slot.querySelectorAll('.anim-bar')).toHaveLength(0);

		// The remount (what HMR does after a SAVE) hosts exactly one bar.
		render(AnimationBar);
		await tick();
		await tick();
		expect(slot.querySelectorAll('.anim-bar')).toHaveLength(1);

		slot.remove();
	});
});
