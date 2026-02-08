<script lang="ts">
	import MermaidRenderer from './MermaidRenderer.svelte';

	let { children } = $props();
</script>

<MermaidRenderer />

<article class="prose prose-invert max-w-none">
	{@render children()}
</article>
