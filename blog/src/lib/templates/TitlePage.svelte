<!-- Title page. The deck's pager lives in SlideDeck's ControlBar, not on this template. -->
<script lang="ts">
	/** Inline style for the page root, applied last so it wins. */
	export let style: string = '';
	/** DOM id for the page root. */
	export let id: string = '';
	/** Extra class(es) for the page root. NOTE: a slide's own style block is scoped, so a
	    class defined there will NOT match — use global CSS (global.css / roles.css / a
	    :global(...) block) or a utility class. See AGENTS.md. */
	let klass: string = '';
	export { klass as class };
</script>

<div class="page {klass}" id={id || undefined} style={style || undefined}>
	<h1 class="title"     ><slot name="title"       /></h1>
	<p class='subtitle'   ><slot name="subtitle"    /></p>
	<p class='subsubtitle'><slot name="subsubtitle" /></p>
</div>

<style>
	.page {
		/* cosmetic */
		width: 100%;
		padding: auto;
		margin: auto;
	}
	.page .title {
		padding: 0px;
		margin: 0px;
		text-align: center;
		font-size: 5em;
		font-family: 'Playfair Display Bold', 'Cormorant Garamond', serif;
		color: var(--page-title-fg, #F0A33E);
	}
	.page .subtitle {
		text-align: center;
		font-size: 3em;
	}
	.page .subsubtitle {
		text-align: center;
		font-size: 2em;
	}
</style>
