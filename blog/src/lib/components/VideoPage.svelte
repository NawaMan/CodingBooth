<!--
  VideoPage — a video filling the whole slide canvas. (The TODO calls this VDOPage;
  it is named for the `Video` it wraps, as WebPage is for WebSite.)

  The full-bleed sibling of Video: same player, same chrome, same bookmarks — but
  stretched over the deck's fixed 1920x1080 canvas instead of a Block. Use Video
  when the recording is ONE element on a slide; use VideoPage when it IS the slide.

  Usage — this is a complete slide:

    <script>
      import VideoPage from '$lib/components/VideoPage.svelte';
      import demo      from './demo.mp4';
    </script>

    <VideoPage src={demo} keys="global" bookmarks={[
      { at: '0:03', tag: 'HOST',  label: 'No toolchain on the host.' },
      { at: '1:14', tag: 'BOOTH', label: 'It builds.' },
    ]} />

  Paging still works with the video on screen: the deck's pager lives in SlideDeck's
  ControlBar (the bottom-centre chrome bar), not on this component — so a full-bleed
  video and a nested one behave the same and there is no second bar to suppress.

  `keys="global"` is worth more here than on a mixed slide: when the video IS the
  content, Space walking chapter to chapter and then paging on is exactly the deck's
  forward march. It stays opt-in all the same — see Video.svelte for why.

  Layering: the player is absolutely positioned and carries no z-index, so it paints
  in DOM order — the deck's own chrome (ADJUST toggle, Table of Contents, speaker
  Notes) are later siblings and stay above it. A <video> takes no keys of its own,
  so nothing here competes for the deck's.

  Props: `src`, `poster`, `bookmarks`, `chapters`, `controls`, `native`, `keys`,
  `continueKey`, `start`, `autoplay` (`true` | `false` | `'kiosk'`), `kioskHold`,
  `loop`, `muted`, `playsinline`, `preload` all pass straight through to Video. Plus:
    height — text mode only: the player's height there (a text artifact has no canvas).

  In `text` mode there is no canvas to fill, so the player drops out of the absolute
  layer into normal flow at `height`, with no nav bar.
-->
<script lang="ts">
	import { getMode } from '$lib/presentation';
	import Video from '$lib/components/Video.svelte';
	import type { Bookmark } from '$lib/utils/videoCore';
	import type { VideoAutoplay } from '$lib/utils/videoKioskCore';

	/** The video URL. Import the file as an asset so it survives a base path. */
	export let src: string = '';
	/** Still frame shown before playback. */
	export let poster: string = '';
	/** Chapter markers: `{ at: '1:14', label: '…', tag: 'BOOTH' }`. */
	export let bookmarks: Bookmark[] = [];
	/** Render the chapter list under the bar. */
	export let chapters: boolean = true;
	/** Render Video's chrome bar. */
	export let controls: boolean = true;
	/** Use the browser's own controls instead. */
	export let native: boolean = false;
	/** 'global': Space/Shift+Space step the bookmarks, then page the deck. */
	export let keys: 'global' | 'off' = 'off';
	/** Also seek on the presenter console's CONTINUE pulse. Needs `keys`. */
	export let continueKey: boolean = true;
	/** Seek here once metadata arrives — seconds or a clock string. */
	export let start: number | string | null = null;
	/** `true` always; `false` never; `'kiosk'` only while kiosk is active. */
	export let autoplay: VideoAutoplay = false;
	/** Hold the kiosk clock until this clip ends (one cycle if `loop`). Default true. */
	export let kioskHold: boolean = true;
	/** Restart on end. */
	export let loop: boolean = false;
	/** Start muted. `undefined` → muted when autoplay is `true` or `'kiosk'`. */
	export let muted: boolean | undefined = undefined;
	/** Play inline on iOS. */
	export let playsinline: boolean = true;
	/** How much to fetch up front. */
	export let preload: 'none' | 'metadata' | 'auto' = 'metadata';
	/** Text mode only: how tall the player renders where there is no canvas. */
	export let height: string = '640px';
	/** Inline style for the root element, applied last so it wins. */
	export let style: string = '';
	/** DOM id for the root element. */
	export let id: string = '';
	/** Extra class(es) for the root element. NOTE: a slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS (global.css / roles.css / a
	    :global(...) block) or a utility class. See AGENTS.md. */
	let klass: string = '';
	export { klass as class };

	const isText = getMode() === 'text';
</script>

<div class="videopage {klass}" class:text-mode={isText} id={id || undefined} style={style || undefined}>
	<Video
		{src}
		{poster}
		{bookmarks}
		{chapters}
		{controls}
		{native}
		{keys}
		{continueKey}
		{start}
		{autoplay}
		{kioskHold}
		{loop}
		{muted}
		{playsinline}
		{preload}
		height={isText ? height : '100%'}
	/>
</div>

<style>
	/* Absolute against the deck's .container (the only positioned ancestor), so this
	   covers the full canvas — the same coordinate space Block authors in. No
	   z-index: later siblings (nav bar, TOC, Notes) must keep painting above it. */
	.videopage {
		position: absolute;
		inset: 0;
		overflow: hidden;
	}

	/* No canvas in a text artifact — fall back into the document flow. */
	.videopage.text-mode {
		position: static;
		inset: auto;
		width: 100%;
	}
</style>
