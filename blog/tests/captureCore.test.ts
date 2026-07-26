// Unit tests for the capture decision layer — pure, total, and (the load-bearing one) honest
// about what it cannot draw.
import { describe, expect, it } from 'vitest';
import {
	CHROME_SELECTOR,
	LIVE_SELECTOR,
	captureFileName,
	findBlockers,
	readCaptureParam,
	refusalText,
	resolveCanCapture,
	svgDocument,
	xmlSafeCss
} from '../src/lib/capture/captureCore';

function frag(html: string): HTMLElement {
	const d = document.createElement('div');
	d.innerHTML = html;
	return d;
}

describe('findBlockers — what no re-render can draw', () => {
	it('finds an iframe, and NAMES it', () => {
		// "1 EMBED" tells the speaker nothing; "YouTube" tells them which box will be missing.
		const el = frag('<iframe title="YouTube"></iframe><p>text</p>');
		expect(findBlockers(el)).toEqual([{ kind: 'embed', label: 'YouTube' }]);
	});

	it('falls back to the host when there is no title', () => {
		const el = frag('<iframe src="https://example.com/a/b"></iframe>');
		expect(findBlockers(el)[0].label).toBe('example.com');
	});

	it('does NOT block on canvas or video — their pixels are readable from this document', () => {
		// The distinction that matters: an iframe is a separate browsing context we may not read
		// (same-origin policy doing its job). A canvas and a video are ours, so captureSlide
		// snapshots them into <img>s rather than refusing.
		expect(findBlockers(frag('<canvas></canvas><video></video>'))).toEqual([]);
	});

	it('is happy with a slide it can draw, and total for junk', () => {
		expect(findBlockers(frag('<h1>Hi</h1><svg><path d="M 0 0"/></svg>'))).toEqual([]);
		expect(findBlockers(null)).toEqual([]);
		expect(findBlockers(undefined)).toEqual([]);
	});
});

describe('refusalText', () => {
	it('says what is in the way, not just that something is', () => {
		expect(refusalText([{ kind: 'embed', label: 'YouTube' }])).toContain('YouTube');
		expect(refusalText([{ kind: 'embed', label: 'a' }, { kind: 'embed', label: 'b' }])).toContain('2');
	});

	it('is empty when there is nothing to refuse', () => {
		expect(refusalText([])).toBe('');
		expect(refusalText(null as never)).toBe('');
	});
});

describe('CHROME_SELECTOR — the ink stays, the pen goes', () => {
	it('strips the pen chrome but KEEPS the ink surface', () => {
		// The whole reason a speaker captures a slide is that they circled something. The circle
		// has to be in the PNG; the bar they drew it with must not be.
		const el = frag(`
			<svg class="annot-surface"><path class="annot-stroke" d="M 0 0 L 9 9"/></svg>
			<div class="annot-bar no-print">PEN</div>
			<div class="annot-tools no-print">PRESENT · ANNOTATE · ADJUST · OVERVIEW · CAPTURE · PRINT</div>
			<div class="annot-stale no-print">old ink</div>
			<p>slide content</p>
		`);
		el.querySelectorAll(CHROME_SELECTOR).forEach((n) => n.remove());

		expect(el.querySelector('.annot-surface')).toBeTruthy();
		expect(el.querySelector('.annot-stroke')).toBeTruthy();
		expect(el.querySelector('p')).toBeTruthy();

		expect(el.querySelector('.annot-bar')).toBeNull();
		expect(el.querySelector('.annot-tools')).toBeNull();
		expect(el.querySelector('.annot-stale')).toBeNull();
	});

	it('matches the live elements whose bitmaps a clone would drop', () => {
		const el = frag('<canvas></canvas><video></video><p>x</p>');
		expect(el.querySelectorAll(LIVE_SELECTOR)).toHaveLength(2);
	});
});

describe('captureFileName', () => {
	it('names the file after the slide', () => {
		expect(captureFileName('/slides/intro.html')).toBe('intro.png');
		expect(captureFileName('/slides/annotate-component.html/')).toBe('annotate-component.png');
	});

	it('never yields a nameless file the browser would refuse to save', () => {
		expect(captureFileName('')).toBe('slide.png');
		expect(captureFileName('/')).toBe('slide.png');
		expect(captureFileName(null)).toBe('slide.png');
		expect(captureFileName('/slides/../..')).toBe('slide.png');
	});
});

describe('svgDocument', () => {
	it('sizes the foreignObject to the CANVAS, not to the window', () => {
		// The entire premise: a slide has a true size, so the PNG is the same on every machine.
		const svg = svgDocument('<p>hi</p>', 'p{color:red}', 1920, 1080);
		expect(svg).toContain('width="1920" height="1080"');
		expect(svg).toContain('viewBox="0 0 1920 1080"');
		expect(svg).toContain('<foreignObject');
		expect(svg).toContain('xmlns="http://www.w3.org/1999/xhtml"');
	});

	it('carries the CSS INTO the document — a data: URL SVG can see nothing of this page', () => {
		const svg = svgDocument('<p>hi</p>', 'p{color:red}', 1920, 1080);
		expect(svg).toContain('<style>p{color:red}</style>');
	});

	it('honours a portrait canvas, and refuses to emit a zero-sized one', () => {
		expect(svgDocument('', '', 1080, 1920)).toContain('viewBox="0 0 1080 1920"');
		expect(svgDocument('', '', NaN, 0)).toContain('viewBox="0 0 1920 1080"');
	});
});

describe('xmlSafeCss — the bug that refused to draw every slide', () => {
	// The deck's compiled CSS really does contain this line, and its `&` alone was enough to
	// reject the entire SVG. In HTML a bare `&` is tolerated; in XML it opens an entity, so the
	// document is malformed — and a malformed SVG is not partly drawn, it is thrown out whole,
	// with an `onerror` that explains nothing.
	const REAL = '@import url("https://fonts.googleapis.com/css2?family=Amatic+SC:wght@400;700&display=swap");.note{padding:0}';

	it('drops the @import rule entirely', () => {
		// Not tidiness: an SVG rendered as an IMAGE may not fetch external resources at all, so
		// the rule could never have worked. Its content is inlined separately instead.
		const out = xmlSafeCss(REAL);
		expect(out).not.toContain('@import');
		expect(out).not.toContain('fonts.googleapis.com');
		expect(out).toContain('.note{padding:0}'); // …and the real CSS survives
	});

	it('escapes the characters XML cannot take raw', () => {
		expect(xmlSafeCss('a{content:"x & y"}')).toBe('a{content:"x &amp; y"}');
		expect(xmlSafeCss('a{content:"1 < 2"}')).toBe('a{content:"1 &lt; 2"}');
	});

	it('is total', () => {
		expect(xmlSafeCss('')).toBe('');
		expect(xmlSafeCss(null as never)).toBe('');
	});

	it('yields an SVG that actually PARSES as XML — the thing the browser was refusing', () => {
		// The regression test with teeth: parse the document the way the browser does. Before the
		// fix this produced a <parsererror> and the capture died with "refused to draw".
		const svg = svgDocument('<p>hi</p>', REAL, 1920, 1080);
		const doc = new DOMParser().parseFromString(svg, 'image/svg+xml');
		expect(doc.querySelector('parsererror')).toBeNull();
		expect(doc.querySelector('foreignObject')).toBeTruthy();
	});

	it('escapes automatically, so a caller cannot forget', () => {
		// xmlSafeCss is applied INSIDE svgDocument for exactly this reason.
		expect(svgDocument('', 'a{content:"&"}', 100, 100)).toContain('&amp;');
	});
});

describe('resolveCanCapture / readCaptureParam', () => {
	it('offers capture in dev, then to a sticky flag, then to the deck', () => {
		expect(resolveCanCapture(true, null, false)).toBe(true);
		expect(resolveCanCapture(false, true, false)).toBe(true);
		expect(resolveCanCapture(false, false, true)).toBe(false); // the speaker asked; they outrank
		expect(resolveCanCapture(false, null, true)).toBe(true);
		expect(resolveCanCapture(false, null, false)).toBe(false);
	});

	it('treats an absent ?capture as "nothing was said", not as off', () => {
		expect(readCaptureParam(new URLSearchParams('capture'))).toBe(true);
		expect(readCaptureParam(new URLSearchParams('capture=off'))).toBe(false);
		expect(readCaptureParam(new URLSearchParams(''))).toBe(null);
		expect(readCaptureParam(null)).toBe(null);
	});
});
