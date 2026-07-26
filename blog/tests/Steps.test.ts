import { render } from '@testing-library/svelte';
import { tick } from 'svelte';
import { get } from 'svelte/store';
import { describe, expect, it } from 'vitest';
import StepsHost from './StepsHost.svelte';
import { activeSteps } from '../src/lib/stores/activeSteps';

// The interactive half of Steps/Fragment (the SSR half — prerender-visible markup
// — is in StepsSsr.ssr.test.ts). Fragments start hidden but keep their box; Space
// builds the list up, Shift+Space peels it back. The arrow keys are deliberately
// left untouched so NavigationBar's slide paging keeps working during a build.

const frags = (root: ParentNode) => Array.from(root.querySelectorAll('.fragment')) as HTMLElement[];
const hidden = (el: HTMLElement) => el.classList.contains('hidden');

function press(key: string, opts: { shiftKey?: boolean; target?: EventTarget } = {}) {
	const { shiftKey = false, target = document.body } = opts;
	const code = key === ' ' ? 'Space' : key;
	const ev = new KeyboardEvent('keydown', { key, code, shiftKey, bubbles: true, cancelable: true });
	target.dispatchEvent(ev);
	return ev;
}

describe('Steps / Fragment', () => {
	it('Space builds up, Shift+Space peels back; all Fragments hidden at the start', async () => {
		const { container } = render(StepsHost);
		const f = frags(container);
		expect(f).toHaveLength(3);
		expect(f.every(hidden)).toBe(true); // start=0 → nothing revealed yet

		const e1 = press(' ');
		await tick();
		expect(hidden(f[0])).toBe(false);
		expect(hidden(f[1])).toBe(true);
		expect(e1.defaultPrevented).toBe(true); // we own Space (stops page scroll)

		press(' ');
		press(' ');
		await tick();
		expect(f.some(hidden)).toBe(false); // all three showing

		press(' ', { shiftKey: true });
		await tick();
		expect(hidden(f[2])).toBe(true); // last one peeled back off
	});

	// The handoff: Steps only claims Space while a step remains, so a spent build
	// lets the key reach NavigationBar, which pages to the next slide.
	it('releases Space at the ends so the deck can page', async () => {
		const { container } = render(StepsHost);
		const f = frags(container);

		// nothing revealed yet → Shift+Space is not ours (it should page back)
		const back = press(' ', { shiftKey: true });
		await tick();
		expect(f.every(hidden)).toBe(true);
		expect(back.defaultPrevented).toBe(false);

		press(' ');
		press(' ');
		press(' ');
		await tick();
		expect(f.some(hidden)).toBe(false); // build spent

		const spent = press(' ');
		await tick();
		expect(spent.defaultPrevented).toBe(false); // released → NavigationBar pages next
	});

	it('leaves the arrow keys alone so NavigationBar can page the deck', async () => {
		const { container } = render(StepsHost);
		const f = frags(container);

		const eR = press('ArrowRight');
		await tick();
		expect(f.every(hidden)).toBe(true); // build untouched by →
		expect(eR.defaultPrevented).toBe(false); // not consumed → the pager is free

		const eL = press('ArrowLeft');
		await tick();
		expect(eL.defaultPrevented).toBe(false);
	});

	// What NavigationBar's CONTINUE button reads: a live handle onto the build, so
	// the button can act as Space and grey out when there's nothing left to reveal.
	it('publishes the build to activeSteps for the CONTINUE button', async () => {
		const { container, unmount } = render(StepsHost);
		const f = frags(container);

		expect(get(activeSteps)?.hasNext).toBe(true); // CONTINUE starts enabled

		get(activeSteps)!.next(); // clicking CONTINUE == pressing Space
		await tick();
		expect(hidden(f[0])).toBe(false);
		expect(get(activeSteps)?.hasNext).toBe(true);

		get(activeSteps)!.next();
		await tick();
		get(activeSteps)!.next();
		await tick();
		expect(f.some(hidden)).toBe(false);
		expect(get(activeSteps)?.hasNext).toBe(false); // build spent → CONTINUE disables

		unmount();
		expect(get(activeSteps)).toBeNull(); // deregisters with the slide
	});

	it('ignores Space while a control is focused, keeping its native behaviour', async () => {
		const { container } = render(StepsHost);
		const f = frags(container);
		const btn = document.createElement('button');
		document.body.appendChild(btn);
		try {
			const ev = press(' ', { target: btn });
			await tick();
			expect(f.every(hidden)).toBe(true); // no reveal triggered
			expect(ev.defaultPrevented).toBe(false); // button keeps its own Space
		} finally {
			btn.remove();
		}
	});
});
