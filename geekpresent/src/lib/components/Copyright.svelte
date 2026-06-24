<script lang="ts">
    export let name    = 'GeekPresent';
    export let url     = 'https://nawaman.net/projects#geekpresent';
    export let year    = new Date().getFullYear().toString();
</script>

<div class="copyright">
	<span class="text">&copy; {name} {year}</span>
	<span class="hover-text"
		><a href={url} target="_blank"
			>Copyright <b>{name} &lt;{url}&gt;</b> {year}</a
		></span
	>
</div>

<style>
	@import url('https://fonts.googleapis.com/css2?family=Amatic+SC:wght@400;700&display=swap');

	.copyright {
		/* cosmetic */
		position: absolute;
		padding-left: 0.5em;
		padding-right: 0px;
		/* Vertical position knob: negative = lower, positive = higher. */
		bottom: -10px;
		/* Horizontal position knob: negative = further right, positive = further left. */
		right: 5px;
		margin-right: 0.5em;
		font-size: 1.5em;
		font-weight: bold;
		opacity: 0.7;

		font-family: 'Amatic SC', cursive;
	}

	.copyright .hover-text {
		display: none;
	}
	.copyright:hover .hover-text {
		display: inline;
		opacity: 1;
		font-stretch: expanded;
		font-family: 'Amatic SC', cursive;
	}

	.copyright:hover .text {
		display: none;
	}
</style>
