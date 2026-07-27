<script>
    import QRCode from './QRCode.svelte';

    // Pass the thumbnail as an imported asset so it can live next to the page
    // that uses it (Vite resolves the import to a URL):
    //   import thumbnail from './my-video-TN.png';
    export let thumbnail;
    export let youtubeId;
    export let width = "900px";
    export let alt   = "";

    // The QR is now OPTIONAL, and omitting it is the better answer: `QRCode` encodes
    // the watch URL right here, from `youtubeId`, so the code can never drift from the
    // video it points at. Pass an imported `-QR.png` (as `utils/prepare-youtube.sh`
    // generates) only to keep an existing slide rendering exactly as it did.
    /** @type {string | null} */
    export let qr = null;

    /** Inline style for the root element, applied last so it wins. */
    export let style = '';
    /** DOM id for the root element. */
    export let id = '';
    /** Extra class(es) for the root element. NOTE: a slide's own style block is scoped, so a
        class defined there will NOT match — use global CSS (global.css / roles.css / a
        :global(...) block) or a utility class. See AGENTS.md. */
    let klass = '';
    export { klass as class };

    $: videoUrl = `https://www.youtube.com/watch?v=${youtubeId}`;
</script>

<a href={videoUrl} target="_blank" class={klass || undefined} id={id || undefined} style="--width: {width}; {style}">
    <div class="youtube">
        <img class="thumbnail" src={thumbnail} alt={alt} />
        <div class="qr-block">
            <span class="watch-id">?v={youtubeId}</span>
            {#if qr}
                <img class="qr" src={qr} alt={alt ? `${alt} QR code` : "QR code"} />
            {:else}
                <!-- link={false}: this sits inside the card's own <a>, and an anchor
                     nested in an anchor is invalid HTML the browser silently unpicks. -->
                <div class="qr qr-live">
                    <QRCode
                        value={videoUrl}
                        size={150}
                        link={false}
                        alt={alt ? `${alt} QR code` : "QR code"}
                    />
                </div>
            {/if}
        </div>
    </div>
</a>

<style>
a {
    color: inherit;          /* use the slide's regular font color */
    text-decoration: none;
}
img {
    display: block;
    margin-left: auto;
    margin-right: auto;
    margin-bottom: 1em;
    border: 3px var(--media-frame, #FFFFFF) solid;
    border-radius: 7.5px;
}
.youtube {
    position: relative;
    margin: auto;
    width: var(--width);
}
.thumbnail {
    width: 100%;
}
.qr-block {
    position: absolute;
    bottom: 15px;
    left: 15px;
    display: flex;
    flex-direction: column;
    align-items: flex-start;
}
.watch-id {
    font-family: monospace;
    font-size: 21px;
    line-height: 1;
    margin-bottom: 6px;
}
.qr {
    width: 150px;
    margin-bottom: 0;
}
/* The encoded code is an <svg>, not an <img>, so it misses the frame the `img` rule
   above draws. Repeat it here rather than widen that selector — the thumbnail and the
   code want the same frame for different reasons. */
.qr-live {
    box-sizing: content-box;
    border: 3px var(--media-frame, #FFFFFF) solid;
    border-radius: 7.5px;
    line-height: 0;
    overflow: hidden;
}
</style>
