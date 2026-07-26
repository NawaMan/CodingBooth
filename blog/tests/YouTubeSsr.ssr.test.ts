// @vitest-environment node
//
// YouTube's `qr` prop used to be mandatory: a PNG that `utils/prepare-youtube.sh`
// generated with the `qrencode` binary and committed next to the slide. It is now
// optional, and omitting it is the better answer — `QRCode` encodes the watch URL
// from `youtubeId`, so the code cannot drift from the video it points at.
//
// Both paths are pinned here, because the PNG path is what every existing slide in
// the repo still uses and must keep rendering exactly as it did.
import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';
import YouTube from '../src/lib/components/YouTube.svelte';
import { encodeQr, qrPath } from '../src/lib/utils/qrCore';

const ID = 'dQw4w9WgXcQ';
const WATCH = `https://www.youtube.com/watch?v=${ID}`;

describe('YouTube (SSR)', () => {
	it('encodes the watch URL when no QR image is supplied', () => {
		const { body } = render(YouTube, { props: { thumbnail: '/tn.png', youtubeId: ID } });
		expect(body).toContain(`d="${qrPath(encodeQr(WATCH, { ecc: 'M' }), 4)}"`);
		expect(body).toContain('qr-live');
	});

	it('still renders a supplied QR image, untouched', () => {
		const { body } = render(YouTube, {
			props: { thumbnail: '/tn.png', qr: '/my-QR.png', youtubeId: ID, alt: 'My talk' },
		});
		expect(body).toContain('src="/my-QR.png"');
		expect(body).toContain('alt="My talk QR code"');
		expect(body).not.toContain('<svg');
		expect(body).not.toContain('qr-live');
	});

	it('never nests an anchor inside the card\'s own anchor', () => {
		// QRCode auto-links an https value, which here would put an <a> inside the <a>
		// wrapping the whole card — invalid HTML that a browser silently unpicks.
		const { body } = render(YouTube, { props: { thumbnail: '/tn.png', youtubeId: ID } });
		expect(body.match(/<a\b/g)).toHaveLength(1);
		expect(body).toContain(`href="${WATCH}"`);
	});
});
