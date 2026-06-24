<script lang="ts">
    import { createEventDispatcher } from 'svelte';

    const dispatch = createEventDispatcher();

    export let isHovered = false;
    export let style     = '';
    let hoverState = false;
    $:  isHovered  = hoverState;

    function handleMouseOver(event: MouseEvent) {
        hoverState = true;
        dispatch('mouseover', event);
    }

    function handleMouseOut(event: MouseEvent) {
        hoverState = false;
        dispatch('mouseout', event);
    }
</script>

<!-- svelte-ignore a11y-no-static-element-interactions -->
<!-- svelte-ignore a11y-mouse-events-have-key-events -->
<span
    class="label"
    on:mouseover={handleMouseOver}
    on:mouseout={handleMouseOut}
    style={style}
    {...$$restProps}>
    <slot></slot>
</span>

<style>
.label {
    font-weight: bold;
    color: var(--label-fg, #DEB887);
    cursor: help;
}
</style>
