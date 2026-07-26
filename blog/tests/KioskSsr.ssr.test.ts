// Kiosk chrome must prerender without touching window/localStorage — dialog and
// indicator are browser-gated and emit nothing on the server.
import { describe, expect, it } from 'vitest';
import { render } from 'svelte/server';
import KioskDialog from '$lib/components/KioskDialog.svelte';
import KioskIndicator from '$lib/components/KioskIndicator.svelte';
import KioskRunner from '$lib/components/KioskRunner.svelte';

describe('Kiosk SSR', () => {
	it('dialog renders an empty shell (no dialog markup)', () => {
		const { body } = render(KioskDialog);
		expect(body).not.toContain('kiosk-dialog');
		expect(body).not.toContain('auto-advance');
	});

	it('indicator renders nothing while off', () => {
		const { body } = render(KioskIndicator);
		expect(body).not.toContain('kiosk-panel');
		expect(body).not.toContain('KIOSK');
	});

	it('runner is a headless clock (no markup)', () => {
		const { body } = render(KioskRunner, {
			props: { pages: [{ path: 'a.html', title: 'A' }], currentSlide: 'a.html' }
		});
		// No element chrome — only optional comments/whitespace
		expect(body.replace(/<!--[\s\S]*?-->/g, '').trim()).toBe('');
	});
});
