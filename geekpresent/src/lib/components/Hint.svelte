<script lang="ts">
    export let text       = '-hint-';
	export let isVisible  = true;
</script>

<div class="text" class:hidden={!isVisible}>{text}</div>

<style>
	.text {
		/* cosmetic */
		position: absolute;
		padding-left: 0.5em;
		padding-right: 0.5em;
		bottom: 0px;
		margin-right: auto;
        margin-left: auto;
		font-size: 1.5em;
		font-weight: bold;
		opacity: 0.7;
	}
	.text.hidden {
		display: none;
	}
</style>
