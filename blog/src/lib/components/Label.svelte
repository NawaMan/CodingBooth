<script lang="ts">
    import { createEventDispatcher } from 'svelte';

    const dispatch = createEventDispatcher();

    export let isHovered = false;
    export let style     = '';
    /** DOM id for the root element. */
    export let id: string = '';
    /** Extra class(es) for the root element. NOTE: a slide's own style block is scoped, so a
        class defined there will NOT match — use global CSS (global.css / roles.css / a
        :global(...) block) or a utility class. See AGENTS.md. */
    let klass: string = '';
    export { klass as class };

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
    class="label {klass}"
    id={id || undefined}
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
