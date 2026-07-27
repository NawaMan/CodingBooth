<!--
  QRCode — a live, scannable link on any slide.

  The thing every talk ends with: "slides are at this URL". Today that QR is a PNG
  a shell script generates ahead of time (`utils/prepare-youtube.sh` shells out to
  `qrencode`), which means the image is stale the moment the URL changes and has to
  be committed next to the slide. This component encodes the symbol *itself*, in
  `utils/qrCore.ts`, and draws it as an `<svg>`.

  Three things follow from that, and they are the whole reason it exists:

    - **Nothing is fetched.** The symbol is computed where it is rendered — no image
      request, no CDN, no generator service, nothing to fail in a conference room
      with bad wifi. And nothing to regenerate: change the URL, the code changes.
    - **It stays crisp.** SlideDeck transform-scales the 1920×1080 canvas to whatever
      the projector is, and a raster QR softens with it. Vector modules do not, and
      a soft QR is a QR that takes three tries to scan from row twelve.
    - **It has no dependencies.** Neither an npm package nor the `qrencode` binary.

  It is SSR-safe — the markup is a function of the props, with no `onMount` and no
  browser API — but note the gotcha `Terminal` documents: a slide's content never
  reaches the static build, because `SlideDeck` gates it behind `initialized`. So
  "the symbol prerenders" is a **Text-artifact** benefit, not a slide one. What SSR
  safety buys a slide is the absence of a mount-time flash, and a symbol that cannot
  differ between the server's idea of it and the browser's.

  Usage:

    <script>
      import QRCode from '$lib/components/QRCode.svelte';
    </script>

    <QRCode value="https://geekpresent.dev" label="Slides" />
    <Block x={1400} y={640} width={340} height={380}><QRCode value={url} /></Block>

  Props:
    value      — what the symbol encodes. Empty (or too long to fit) → renders nothing.
    ecc        — 'L' | 'M' | 'Q' | 'H' error correction (default 'M'). Higher survives
                 more damage and costs a bigger symbol. A slide is a clean, backlit
                 surface, so 'M' is plenty; go 'Q'/'H' only if a logo overlaps it.
    size       — the side, in canvas px (number) or any CSS length ('100%'). Default 220.
                 The symbol never distorts: an svg keeps its aspect ratio by default,
                 so a Block that stretches this box letterboxes the code instead of
                 skewing it — and a skewed QR is an unreadable one.
    quiet      — the light margin, in modules (default 4, which is the spec's minimum).
                 It is part of the symbol, not padding you may trim: a scanner finds the
                 finders by their outer light edge.
    minVersion — floor the symbol's version (1–40) to keep its module size steady across
                 slides whose URLs differ in length.
    mask       — pin the data mask (0–7). Defaults to the spec's penalty-scored choice.
    label      — a caption under the code. The default slot overrides it, for rich markup.
    href       — where a *click* goes. Defaults to `value` when it looks like a link
                 (http, https, mailto, tel), so the code is scannable by the room and
                 clickable by whoever is reading the deck as a page. `link={false}` opts out.
    alt        — accessible name (default: the label, else the value).
    plate      — the light backing under the code and its quiet zone (default true).
    style      — extra inline CSS appended to the root.

  Colours come from roles.css (--qr-*). Note that unlike almost everything else here,
  they do NOT follow the theme's ink and paper: a QR must be dark-on-light to be read,
  so the defaults are literal black on literal white, whatever the deck's palette —
  the same call Video's letterbox and Terminal's screen make. `plate={false}` hands
  that responsibility back to the slide.
-->
<script lang="ts">
	import { encodeQr, qrExtent, qrPath, type Ecc } from '$lib/utils/qrCore';

	/** What the symbol encodes. Empty, or too long for version 40, renders nothing. */
	export let value: string = '';
	/** Error-correction level. Higher survives more damage, at a bigger symbol. */
	export let ecc: Ecc = 'M';
	/** The side, in canvas px (number) or a CSS length. Aspect ratio is never distorted. */
	export let size: number | string = 220;
	/** The light margin in modules. Four is the spec's minimum, and its default. */
	export let quiet: number = 4;
	/** Floor the version (1–40), to hold a module size steady across slides. */
	export let minVersion: number = 1;
	/** Pin the data mask (0–7); anything else lets the penalty score choose. */
	export let mask: number | null = null;
	/** A caption under the code. The default slot wins over this. */
	export let label: string = '';
	/** Where a click goes. `null` → `value`, when it looks like a link. */
	export let href: string | null = null;
	/** Whether the code is a link at all. */
	export let link: boolean = true;
	/** Accessible name. Falls back to the label, then to the encoded value. */
	export let alt: string = '';
	/** The light backing under the code and its quiet zone. */
	export let plate: boolean = true;
	/** Extra inline CSS appended to the root. */
	export let style: string = '';
	/** DOM id for the root element. */
	export let id: string = '';
	/** Extra class(es) for the root element. NOTE: a slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS (global.css / roles.css / a
	    :global(...) block) or a utility class. See AGENTS.md. */
	let klass: string = '';
	export { klass as class };

	// A QR is scanned, not clicked — but a deck is also read as a page (and built into
	// a Text artifact), where a link is what a reader can actually use. Only schemes
	// that mean "go here" auto-link; a wifi: or BEGIN:VCARD payload is not a URL.
	const LINKABLE = /^(https?:|mailto:|tel:)/i;

	$: matrix = encodeQr(value, { ecc, minVersion, mask });
	$: extent = qrExtent(matrix, quiet);
	$: path = qrPath(matrix, quiet);

	$: target = !link ? null : (href ?? (LINKABLE.test(value.trim()) ? value.trim() : null));
	$: external = target !== null && /^https?:/i.test(target);
	$: name = alt || label || value;

	$: css = typeof size === 'number' ? `${size}px` : size;
</script>

<!-- An unencodable value renders NO element, rather than an empty square the audience
     would point a phone at. Connector's rule: nothing at all beats something broken. -->
{#if matrix}
	<figure class="qr {klass}" id={id || undefined} {style}>
		<svelte:element
			this={target ? 'a' : 'div'}
			class="frame"
			href={target ?? undefined}
			target={external ? '_blank' : undefined}
			rel={external ? 'noopener noreferrer' : undefined}
			style="--qr-side: {css}"
		>
			<!-- viewBox is in MODULES, so the symbol is resolution-independent: the same
			     markup is a 220px slide badge and a full-canvas poster.
			     `shape-rendering: crispEdges` turns off antialiasing on the module edges —
			     a blurred module boundary is exactly what a scanner cannot resolve. -->
			<svg
				viewBox="0 0 {extent} {extent}"
				role="img"
				aria-label={name}
				shape-rendering="crispEdges"
			>
				{#if plate}
					<rect width={extent} height={extent} fill="var(--qr-light, #FFFFFF)" />
				{/if}
				<path d={path} fill="var(--qr-dark, #000000)" />
			</svg>
		</svelte:element>

		{#if $$slots.default || label}
			<figcaption class="caption">
				<slot>{label}</slot>
			</figcaption>
		{/if}
	</figure>
{/if}

<style>
	.qr {
		display: inline-flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 0.6em;
		margin: 0;
		/* Block stretches its slot content to fill the box. Take the stretch on the
		   wrapper, so a resized Block re-centres the code rather than clipping it. */
		max-width: 100%;
		min-width: 0;
	}

	.frame {
		display: block;
		line-height: 0; /* no descender gap under an inline svg */
		max-width: 100%;
		color: inherit;
		text-decoration: none;
	}

	.frame svg {
		display: block;
		width: var(--qr-side);
		height: var(--qr-side);
		max-width: 100%;
		/* The svg's default preserveAspectRatio ("xMidYMid meet") is doing real work
		   here: whatever box this lands in, the symbol stays square and centred. */
	}

	.caption {
		font-size: 0.85em;
		line-height: 1.3;
		text-align: center;
		color: var(--qr-caption-fg, #c0f1ff);
		overflow-wrap: anywhere; /* a long URL must not push the code off the canvas */
	}
</style>
