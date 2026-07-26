<!-- Steps fixture: three Fragments in a Steps, mirroring a build-up slide. The
     test drives the reveal with the arrow keys and checks the slide-handoff
     (a spare arrow at the end passes through to a bubble-phase pager). -->
<script lang="ts">
	import Steps from '../src/lib/components/Steps.svelte';
	import Fragment from '../src/lib/components/Fragment.svelte';
</script>

<Steps>
	<p>base</p>
	<Fragment tag="p">one</Fragment>
	<Fragment tag="p">two</Fragment>
	<Fragment tag="p">three</Fragment>
</Steps>
