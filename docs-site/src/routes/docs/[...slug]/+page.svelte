<script lang="ts">
	import TableOfContents from '$lib/components/TableOfContents.svelte';

	let { data } = $props();
</script>

<svelte:head>
	<title>{data.title} - GloriousFlywheel</title>
</svelte:head>

<div class="flex gap-8">
	<div class="flex-1 min-w-0 max-w-none 2xl:max-w-5xl">
		{#if data.error}
			<div class="text-error-500">
				<h1 class="text-2xl font-bold mb-2">Page not found</h1>
				<p>The documentation page <code>{data.slug}</code> does not exist.</p>
			</div>
		{:else}
			<h1 class="text-3xl font-bold mb-6">{data.title}</h1>
			<article class="prose prose-invert max-w-none">
				{@html data.html}
			</article>
		{/if}
	</div>
	<TableOfContents />
</div>
