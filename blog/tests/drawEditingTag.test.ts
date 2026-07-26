import { describe, expect, it } from 'vitest';
import { boxTag, playheadPercent, sharedAttrs } from '$lib/draw/editing';

// The opening tag ADJUST emits — what COPY puts on your clipboard, and what you paste
// over the tag in your source.
//
// Which is why the author's own props have to be in it. ADJUST neither reads nor edits
// `id` / `class` / `style`, but Copy emits a WHOLE tag and the author pastes it OVER the
// one they wrote — so anything the emitter forgets is deleted from their slide by the
// act of dragging a box. (SAVE is a different, safer path: patchSource rewrites only the
// geometry attributes in place and leaves every other prop alone — see patchSource.ts
// and the round-trip test in adjustPatch.test.ts.)

describe('sharedAttrs — the author’s props survive the round-trip', () => {
	it('emits id, class and style when the author set them', () => {
		const out = sharedAttrs({ id: 'api-box', class: 'hot', style: 'opacity: 0.4' });
		expect(out).toContain(' id="api-box"');
		expect(out).toContain(' class="hot"');
		expect(out).toContain(' style="opacity: 0.4"');
	});

	// The tag of an undecorated shape must be byte-for-byte what it always was — the
	// emitter is shared by every Copy in the deck, and a stray `class=""` in everyone's
	// pasted source would be a tax paid by slides that never asked for this.
	it('emits nothing for a shape that set none of them', () => {
		expect(sharedAttrs({})).toBe('');
		expect(sharedAttrs({ id: '', class: '', style: '' })).toBe('');
		expect(sharedAttrs({ color: 'red' })).toBe(' color="red"');
	});

	// The emitted line is pasted straight into Svelte source, so it has to PARSE — and a
	// style like `content: "x"` carries the very character that would end the attribute.
	it('single-quotes a value that carries a double quote, so the tag still parses', () => {
		const out = sharedAttrs({ style: 'content: "x"' });
		expect(out).toBe(` style='content: "x"'`);
	});

	it('keeps them alongside the shape’s own attributes, in the full tag', () => {
		const attrs = sharedAttrs({ color: 'red', thickness: 4, id: 'api-box', class: 'hot' });
		const tag = boxTag('Rect', 'api', attrs, 100, 100, 200, 80);

		expect(tag).toBe(
			'<Rect name="api" color="red" thickness={4} id="api-box" class="hot"' +
				' x={100} y={100} width={200} height={80} />'
		);
	});
});

// The live playhead percent behind "+ keyframe" / preview: read the CSS
// animation's currentTime off the element and map it onto the keyframe pct
// scale. currentTime spans delay + duration, the pct scale only the duration —
// so a delayed sprite's playhead must subtract the hold, clamping at 0 while
// the animation is still waiting (fill:both parks it at the start pose).
describe('playheadPercent', () => {
	/** An element whose getAnimations() reports the given CSS animations. */
	const el = (...anims: Array<{ name: string; currentTime: number | null }>) =>
		({
			getAnimations: () =>
				anims.map((a) => ({ animationName: a.name, currentTime: a.currentTime }))
		}) as unknown as Element;

	it('maps currentTime onto the duration: halfway is 50', () => {
		expect(playheadPercent(el({ name: 'fly', currentTime: 1500 }), 'fly', 3)).toBe(50);
	});

	it('subtracts the delay — the pct scale starts AFTER the hold', () => {
		const held = el({ name: 'fly', currentTime: 1500 });
		// 1.5s into a 1.5s delay: the flight has not begun. Without the delay
		// argument this used to read 50%.
		expect(playheadPercent(held, 'fly', 3, 1.5)).toBe(0);
		expect(playheadPercent(el({ name: 'fly', currentTime: 3000 }), 'fly', 3, 1.5)).toBe(50);
		expect(playheadPercent(el({ name: 'fly', currentTime: 4500 }), 'fly', 3, 1.5)).toBe(100);
	});

	it('clamps to 0..100 beyond either end', () => {
		expect(playheadPercent(el({ name: 'fly', currentTime: 9999 }), 'fly', 3)).toBe(100);
		expect(playheadPercent(el({ name: 'fly', currentTime: -50 }), 'fly', 3)).toBe(0);
	});

	it('picks the animation by NAME among several, falling back to the first', () => {
		const both = el({ name: 'other', currentTime: 0 }, { name: 'fly', currentTime: 1500 });
		expect(playheadPercent(both, 'fly', 3)).toBe(50);
		// Unknown name: the first animation stands in rather than reading nothing.
		expect(playheadPercent(both, 'missing', 3)).toBe(0);
	});

	it('returns null when there is nothing to read', () => {
		expect(playheadPercent(undefined, 'fly', 3)).toBeNull();
		expect(playheadPercent(el({ name: 'fly', currentTime: 1500 }), 'fly', null)).toBeNull();
		// currentTime not a number (idle/unresolved animation).
		expect(playheadPercent(el({ name: 'fly', currentTime: null }), 'fly', 3)).toBeNull();
		// No getAnimations at all (bare jsdom element).
		expect(playheadPercent(document.createElement('div'), 'fly', 3)).toBeNull();
	});
});
