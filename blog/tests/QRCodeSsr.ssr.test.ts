// @vitest-environment node
//
// True server-side render of QRCode (svelte/server, no DOM). It is purely
// declarative — no onMount, no browser APIs — so its full markup, the encoded symbol
// included, must come from props alone.
//
// The one gotcha, the same one `Terminal` carries: a slide's markup never reaches the
// static build, because `SlideDeck` gates its content behind `initialized`. So "the
// symbol prerenders" is a **Text-artifact** benefit, not a slide one, and it is
// asserted here against `svelte/server` — never against a built page, which would
// pass for the wrong reason or fail for one. What SSR-safety buys a slide is the
// absence of a mount-time flash, and a symbol that cannot differ between the server's
// idea of it and the browser's.
//
// The path data itself is proved correct against qrencode in `tests/qrCore.test.ts`;
// what is proved here is that the markup carries it, and that the component's
// judgement calls (auto-linking, the missing-value case, the aria name) survive a
// render with no DOM at all.
import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';
import QRCode from '../src/lib/components/QRCode.svelte';
import { encodeQr, qrPath } from '../src/lib/utils/qrCore';

const URL = 'https://geekpresent.dev';

describe('QRCode (SSR)', () => {
	it('prerenders the whole symbol as one <path>, module for module', () => {
		const { body } = render(QRCode, { props: { value: URL } });
		// Not "an svg is present" — the actual encoded geometry, byte for byte.
		expect(body).toContain(`d="${qrPath(encodeQr(URL, { ecc: 'M' }), 4)}"`);
	});

	it('sizes the viewBox in modules, quiet zone included', () => {
		// v2 is 25 modules; the spec's 4-module quiet zone on each side makes 33.
		const { body } = render(QRCode, { props: { value: URL } });
		expect(body).toContain('viewBox="0 0 33 33"');

		// The quiet zone is part of the symbol, so trimming it shrinks the canvas.
		const bare = render(QRCode, { props: { value: URL, quiet: 0 } });
		expect(bare.body).toContain('viewBox="0 0 25 25"');
	});

	it('a higher ecc level buys a bigger symbol for the same text', () => {
		// 23 bytes: it fits version 2 at level L (32 bytes), but level H holds only 14
		// there, so the symbol grows to version 3.
		const low = render(QRCode, { props: { value: URL, ecc: 'L' } });
		const high = render(QRCode, { props: { value: URL, ecc: 'H' } });
		expect(low.body).toContain('viewBox="0 0 33 33"'); // v2: 25 modules + 8
		expect(high.body).toContain('viewBox="0 0 37 37"'); // v3: 29 modules + 8
	});

	it('minVersion holds the module size steady across differing URLs', () => {
		const short = render(QRCode, { props: { value: 'https://a.co', minVersion: 5 } });
		const long = render(QRCode, { props: { value: URL, minVersion: 5 } });
		expect(short.body).toContain('viewBox="0 0 45 45"');
		expect(long.body).toContain('viewBox="0 0 45 45"');
	});

	it('renders no element at all for a value it cannot encode', () => {
		// An empty square is worse than nothing: the audience would point a phone at it.
		for (const value of ['', '   '.trim(), 'A'.repeat(3000)]) {
			const { body } = render(QRCode, { props: { value } });
			expect(body).not.toContain('<svg');
			expect(body).not.toContain('<figure');
		}
	});

	it('crispEdges is on the svg — a blurred module is an unreadable one', () => {
		const { body } = render(QRCode, { props: { value: URL } });
		expect(body).toContain('shape-rendering="crispEdges"');
	});

	it('auto-links a URL, so the room can scan it and a reader can click it', () => {
		const { body } = render(QRCode, { props: { value: URL } });
		expect(body).toContain(`<a`);
		expect(body).toContain(`href="${URL}"`);
		expect(body).toContain('target="_blank"');
		expect(body).toContain('rel="noopener noreferrer"');
	});

	it('links mailto/tel without opening a tab, and leaves other payloads alone', () => {
		const mail = render(QRCode, { props: { value: 'mailto:hi@example.com' } });
		expect(mail.body).toContain('href="mailto:hi@example.com"');
		expect(mail.body).not.toContain('target="_blank"');

		// A wifi credential or a vcard is a payload, not a destination.
		const wifi = render(QRCode, { props: { value: 'WIFI:S:GuestNet;T:WPA;P:hunter2;;' } });
		expect(wifi.body).not.toContain('<a');
		expect(wifi.body).toContain('<div class="frame');
	});

	it('href overrides the value, and link={false} drops the anchor entirely', () => {
		const over = render(QRCode, { props: { value: URL, href: 'https://example.com' } });
		expect(over.body).toContain('href="https://example.com"');

		const none = render(QRCode, { props: { value: URL, link: false } });
		expect(none.body).not.toContain('<a');
	});

	it('names the image for a screen reader: alt, else the label, else the value', () => {
		expect(render(QRCode, { props: { value: URL, alt: 'Deck' } }).body).toContain('aria-label="Deck"');
		expect(render(QRCode, { props: { value: URL, label: 'Slides' } }).body).toContain('aria-label="Slides"');
		expect(render(QRCode, { props: { value: URL } }).body).toContain(`aria-label="${URL}"`);
	});

	it('renders a caption only when there is one to render', () => {
		expect(render(QRCode, { props: { value: URL, label: 'Slides' } }).body).toContain('>Slides<');
		expect(render(QRCode, { props: { value: URL } }).body).not.toContain('figcaption');
	});

	it('plate={false} drops the light backing, leaving the modules alone', () => {
		expect(render(QRCode, { props: { value: URL } }).body).toContain('<rect');
		expect(render(QRCode, { props: { value: URL, plate: false } }).body).not.toContain('<rect');
	});

	it('takes a numeric size as px and a CSS length as written', () => {
		expect(render(QRCode, { props: { value: URL, size: 320 } }).body).toContain('--qr-side: 320px');
		expect(render(QRCode, { props: { value: URL, size: '100%' } }).body).toContain('--qr-side: 100%');
	});
});
