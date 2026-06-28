<script lang="ts">
	import { onMount } from "svelte";
	import { browser } from "$app/environment";

	export let width;
	export let height;

	export let expanded   : boolean       = false;
	export let showClose  : boolean       = true;
	export let scrollable : boolean       = false;
	export let top        : string | null = null;
	export let left       : string | null = null;
	export let bottom     : string | null = null;
	export let right      : string | null = null;
	export let linkUrl    : string | null = null;
	export let linkText   : string        = 'LINK';

	export let shadowOpacity: number              = 0.8;
	export let onClick      : (() => void) | null = null;

	// The visible box. Clicks inside it are left alone (select / copy / drag);
	// the box only closes on CLOSE, Escape, or a click outside it.
	let boxEl: HTMLElement;

	function collapse() {
		expanded = false;
	}

	function handleKeydown(event: KeyboardEvent) {
		if (event.key === 'Escape') {
			collapse();
		}
	}

	function handleOutsideClick(event: MouseEvent) {
		if (expanded && boxEl && !boxEl.contains(event.target as Node)) {
			collapse();
		}
	}

	let outsideListening = false;
	function listenOutside() {
		if (browser && !outsideListening) {
			document.addEventListener('click', handleOutsideClick);
			outsideListening = true;
		}
	}
	function unlistenOutside() {
		if (browser && outsideListening) {
			document.removeEventListener('click', handleOutsideClick);
			outsideListening = false;
		}
	}

	// Listen for outside clicks only while expanded. Deferred by a tick so the
	// very click that opened the box does not immediately close it again.
	$: if (browser) {
		if (expanded) setTimeout(listenOutside, 0);
		else unlistenOutside();
	}

	onMount(() => {
		window.addEventListener('keydown', handleKeydown);

		return () => {
			window.removeEventListener('keydown', handleKeydown);
			unlistenOutside();
		};
	});
</script>

<div
	class="parent {expanded ? 'expanded' : ''}"
	style="--custom-top: {top}; --custom-left: {left}; --custom-bottom: {bottom}; --custom-right: {right}; --shadow-opacity: {shadowOpacity}; --scrollable: {scrollable ? 'scroll' : 'hidden'};"
>
	<!-- svelte-ignore a11y-click-events-have-key-events a11y-no-noninteractive-element-interactions -->
	<div
		class="img-box"
		bind:this={boxEl}
		style="--full-width: {width}px; --full-height: {height}px;"
		on:click={() => onClick && onClick()}
		role="dialog"
		tabindex="-1">
		<slot />
		{#if showClose}
		<div class="close" on:click={collapse} on:keydown={collapse} role="button" tabindex="-1">
			CLOSE
		</div>
		{/if}

		{#if linkUrl}
			<div class="link"><a href={linkUrl} target="_blank">{linkText}</a></div>
		{/if}
	</div>
</div>

<style>
	.parent {
		--box-ani-time: 0.3s;
		display: block;
		position: absolute;
		width: 0px;
		height: 0px;
		top: var(--custom-top, 50%);
		left: var(--custom-left, 50%);
		bottom: var(--custom-bottom, auto);
		right: var(--custom-right, auto);
		transform: translate(-50%, -50%);
	}

    .parent .link a {
        text-decoration: none;
    }

    .parent .close,
    .parent .link {
		/* Was the absolute keyword `small`, which ignored the canvas font-size
		   lever and stayed tiny. Use a relative size so the button (its width,
		   height and offsets are all em, i.e. relative to this) scales with the
		   canvas. */
		font-size: 0.85em;
        position: absolute;
        overflow: hidden;
        cursor: pointer;
		background-color: var(--box-btn-bg, #ADD8E6);
		color: var(--box-btn-fg, #000000);
        border-radius: 4.5px;
        align-content: center;
        text-align: center;
        top: calc(50% - var(--full-height) / 2);
        transition: var(--box-ani-time) height;
    }

	.parent .close {
		right: calc(100% - 9px - 0.5 * var(--full-width));
		width: 5.5em;
		padding: 0px;
	}

    .parent .link {
        left: calc(50% + 4.5px - var(--full-width) / 2);
        padding-top: 0px;
        padding-bottom: 0px;
        padding-left: 1em;
        padding-right: 1em;
    }

	.parent:not(.expanded) .close,
    .parent:not(.expanded) .link {
		height: 0em;
		transition:
            /* Duration         Delay */
			var(--box-ani-time) calc(0 * var(--box-ani-time)) top,
			var(--box-ani-time) calc(0 * var(--box-ani-time)) height,
			var(--box-ani-time) calc(0 * var(--box-ani-time)) padding;
	}

	.parent.expanded .close {
		top: calc(50% - 1.5em - 4.5px - var(--full-height) / 2);
		height: 1.5em;
		padding: 4.5px;
		transition:
            /* Duration         Delay */
			var(--box-ani-time) calc(1 * var(--box-ani-time)) top,
			var(--box-ani-time) calc(1 * var(--box-ani-time)) height,
			var(--box-ani-time) calc(1 * var(--box-ani-time)) padding;
	}

	.parent.expanded .link {
		top: calc(50% - 1.5em - 4.5px - var(--full-height) / 2);
		height: 1.5em;
		padding-top: 4.5px;
		padding-bottom: 4.5px;
		padding-left: 1em;
		padding-right: 1em;
		transition:
            /* Duration         Delay */
			var(--box-ani-time) calc(1 * var(--box-ani-time)) top,
			var(--box-ani-time) calc(1 * var(--box-ani-time)) height,
			var(--box-ani-time) calc(1 * var(--box-ani-time)) padding;
	}

	.parent .img-box {
		padding: 0px;
		overflow-x: hidden;
		overflow-y: var(--scrollable);
		background-color: var(--box-bg, #000000);

		border: 0px solid var(--box-border, #ADD8E6);
		width: 0px;
		height: 0px;
		margin-top: calc(50% - var(--full-height) / 2);
		margin-left: 50%;
		box-shadow:
			3px 3px 0px black,
			0 0 0 9999px rgb(0, 0, 0, 0);
		transition:
            /* Duration         Delay */
			var(--box-ani-time) calc(1 * var(--box-ani-time)) width,
			var(--box-ani-time) calc(0 * var(--box-ani-time)) height,
			var(--box-ani-time) calc(1 * var(--box-ani-time)) margin-left,
			var(--box-ani-time) calc(1 * var(--box-ani-time)) padding,
			var(--box-ani-time) calc(1 * var(--box-ani-time)) border,
			var(--box-ani-time) calc(1 * var(--box-ani-time)) box-shadow;
	}

	.parent.expanded .img-box {
		border-radius: 4.5px;
		border: 7.5px solid var(--box-border, #ADD8E6);
		width: var(--full-width);
		height: var(--full-height);
		margin-top: calc(50% - var(--full-height) / 2);
		margin-left: calc(50% - var(--full-width) / 2);
		box-shadow:
			3px 3px 15px black,
			0 0 0 9999px rgb(0, 0, 0, var(--shadow-opacity));
		transition:
			var(--box-ani-time) calc(0 * var(--box-ani-time)) width,
			var(--box-ani-time) calc(1 * var(--box-ani-time)) height,
			var(--box-ani-time) calc(0 * var(--box-ani-time)) margin-left,
			var(--box-ani-time) calc(0 * var(--box-ani-time)) padding,
			var(--box-ani-time) calc(0 * var(--box-ani-time)) border,
			var(--box-ani-time) calc(0 * var(--box-ani-time)) box-shadow;
	}
</style>
