<script lang="ts">
	import '../app.css';
	import type { Snippet } from 'svelte';
	import DocNav from '$lib/components/DocNav.svelte';
	import { base } from '$app/paths';

	let { data, children }: { data: any; children: Snippet } = $props();
	let sidebarOpen = $state(true);
</script>

<div class="h-full flex">
	<aside
		class="w-64 shrink-0 overflow-y-auto border-r border-surface-300 p-4 {sidebarOpen ? '' : 'hidden'}"
	>
		<a href="{base}/" class="block mb-6">
			<h1 class="text-lg font-bold">GloriousFlywheel</h1>
			<p class="text-xs text-surface-500">attic-iac documentation</p>
		</a>

		{#if data.navigation}
			<DocNav items={data.navigation} />
		{/if}
	</aside>

	<main class="flex-1 overflow-auto p-8">
		{@render children()}
	</main>
</div>
