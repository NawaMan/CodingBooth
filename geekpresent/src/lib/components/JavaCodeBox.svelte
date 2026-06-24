<!--
  JavaCodeBox — JavaCode (Monaco) inside an expandable Box.

  STATUS: legacy / unverified. Prefer <CodeBox> for new slides.

  This wraps <JavaCode>, which carries custom Java-specific folding logic (a
  hand-rolled folding-range provider for imports + brace blocks — see
  JavaCode.svelte). That logic was written for an early, specific use of
  GeekPresent that is no longer part of this project, so there is no longer a
  slide here that exercises it. Because it can't be tested against its original
  use case, it's left untouched on purpose — don't refactor it casually.

  If you just need to show code (any language, including Java), use <CodeBox>:
  it uses Monaco's built-in, language-aware folding and is the supported path.
  JavaCodeBox/JavaCode will be revisited (kept, fixed, or removed) later.
-->
<script lang="ts">
    import Box      from '$lib/components/Box.svelte';
    import JavaCode from '$lib/components/JavaCode.svelte';

    export let javaCode:      string;
    export let title:         string = '';
    export let expanded:      boolean = false;
    export let revealedLines: Array<number> = [1];
    export let fontSize:      number = 20;

    // The box is 975px tall; the title bar (when present) takes 60px.
    $: editorHeight = title ? '915px' : '975px';
</script>

<Box bind:expanded={expanded} width={1500} height={975}>
    {#if title}
        <div class="code-title">{title}</div>
    {/if}
    <JavaCode javaCode={javaCode} revealLines={revealedLines} width="1500px" height={editorHeight} {fontSize} />
</Box>

<style>
    .code-title {
        height: 60px;
        box-sizing: border-box;
        display: flex;
        align-items: center;
        padding: 0 0.8em;
        font-family: 'Fira Code', monospace;
        font-weight: bold;
        color: var(--code-title-fg, #FFFFFF);
        background: var(--code-title-bg, #1E1E1E);
        border-bottom: 1.5px solid var(--code-title-border, #333333);
    }
</style>
