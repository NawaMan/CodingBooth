<!--
  Example: YouTube component showcase
  File: src/routes/slides/youtube-showcase.html/+page.svelte

  Page assets live in this folder, right next to the page that uses them:
    onerbc-TN.png   the thumbnail   (generate with utils/prepare-youtube.sh)
    onerbc-QR.png   the QR code
  Import them so Vite bundles them, then hand them to <YouTube>.
-->
<script>
	import ContentPage from '$lib/templates/ContentPage.svelte';
	import YouTube     from '$lib/components/YouTube.svelte';
	import thumbnail   from './onerbc-TN.png';
	import qr          from './onerbc-QR.png';
</script>

<ContentPage title="YouTube" subtitle="Thumbnail + QR code linking to a video">
	<div class="layout">
		<!-- Left column: what it is + how to use it -->
		<div class="explain">
			<p>
				<code>&lt;YouTube&gt;</code> shows a clickable <b>thumbnail</b> with a
				<b>QR code</b> overlaid in the corner &mdash; both link to the video.
				The QR lets an audience open the video on their phone even when the
				slide is on a screen they can't click.
			</p>

			<p class="step"><b>1.</b> Generate the thumbnail + QR next to your page:</p>
			<div class="snippet">utils/prepare-youtube.sh https://youtu.be/wJ8ucHyJuqg \
  src/routes/slides/your-page.html  onerbc</div>
			<p class="hint">
				Writes <code>onerbc-TN.png</code> and <code>onerbc-QR.png</code> into
				that folder (the last argument is the file-name prefix; it defaults to
				the video id).
			</p>

			<p class="step"><b>2.</b> Import the assets and drop in the component:</p>
			<div class="snippet">&lt;script&gt;
  import YouTube   from '$lib/components/YouTube.svelte';
  import thumbnail from './onerbc-TN.png';
  import qr        from './onerbc-QR.png';
&lt;/script&gt;
&lt;YouTube &#123;thumbnail&#125; &#123;qr&#125; youtubeId="wJ8ucHyJuqg" 
                          alt="My solution for OneRBC" width="600px" /&gt;</div>

			<p class="hint">
				<b>Props:</b>
				<code>thumbnail</code> &amp; <code>qr</code> (the imported images),
				<code>youtubeId</code> (the watch id, shown as <code>?v=…</code>),
				<code>alt</code> (accessible text), and <code>width</code> (any CSS size).
			</p>
		</div>

		<!-- Right column: the live component -->
		<div class="preview">
			<YouTube {thumbnail} {qr} alt="My solution for OneRBC" youtubeId="wJ8ucHyJuqg" width="600px" />
			<p class="caption"><b>My solution for OneRBC</b><br/>click the thumbnail or scan the QR to watch.</p>
		</div>
	</div>
</ContentPage>

<style>
	.layout {
		display: flex;
		gap: 2em;
		align-items: flex-start;
		/* Overall size knob for this slide: lower = shorter (content fits the page),
		   higher = bigger text. Dropped below the template's 1.28em default so this
		   content-heavy slide fits the canvas. */
		font-size: 0.75em;
		}
	.explain {
		flex: 1 1 0;
		min-width: 0;
	}
	/* The block above already leaves space; drop the first paragraph's top margin
	   so the two don't stack into a big gap at the top. */
	.explain > :first-child {
		margin-top: 0;
	}
	.preview {
		flex: 0 0 auto;
		text-align: center;
	}
	.caption {
		margin-top: 1em;
		opacity: 0.85;
	}
	.step {
		margin-top: 0.9em;
		margin-bottom: 0.3em;
	}
	.hint {
		margin-top: 0.4em;
		opacity: 0.7;
	}
	.snippet {
		font-family: 'Fira Code', monospace;
		line-height: 1.6em;
		background: #111;
		color: #cfe9f1;
		padding: 0.6em 1em;
		border-radius: 6px;
		white-space: pre-wrap;
		overflow-wrap: anywhere;
	}
	code {
		font-family: 'Fira Code', monospace;
		background: #1b1b1b;
		padding: 0 0.25em;
		border-radius: 3px;
	}
</style>
