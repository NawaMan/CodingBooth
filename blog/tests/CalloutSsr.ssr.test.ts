// @vitest-environment node
//
// True server-side render of Callout (svelte/server, no DOM). Callout is
// purely declarative — no onMount, no browser APIs — so its full markup must
// come from props alone, which is what prerendering a slide does. This locks in
// the kind -> accent/title/glyph mapping and the color-mix tint plumbing.
import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';
import Callout from '../src/lib/components/Callout.svelte';

describe('Callout (SSR)', () => {
	it('defaults to info: accent token, "Info" label, "i" glyph', () => {
		const { body } = render(Callout, { props: {} });
		expect(body).toContain('var(--callout-info-accent, #2980B9)');
		expect(body).toContain('>Info</div>');
		expect(body).toContain('>i</div>');
	});

	it('maps each kind to its own accent + default title', () => {
		for (const [kind, accent, label] of [
			['tip',    'var(--callout-tip-accent, #00B356)',    'Tip'],
			['warn',   'var(--callout-warn-accent, #F0A33E)',   'Warning'],
			['danger', 'var(--callout-danger-accent, #E5484D)', 'Danger'],
		] as const) {
			const { body } = render(Callout, { props: { kind } });
			expect(body).toContain(accent);
			expect(body).toContain(`>${label}</div>`);
		}
	});

	it('title="" hides the heading; a custom title overrides the default', () => {
		const hidden = render(Callout, { props: { title: '' } });
		expect(hidden.body).not.toContain('class="title"');

		const custom = render(Callout, { props: { kind: 'warn', title: 'Gotcha' } });
		expect(custom.body).toContain('>Gotcha</div>');
		expect(custom.body).not.toContain('>Warning</div>');
	});

	it('icon prop overrides the default glyph', () => {
		const { body } = render(Callout, { props: { kind: 'tip', icon: '★' } });
		expect(body).toContain('>★</div>');
	});
});
