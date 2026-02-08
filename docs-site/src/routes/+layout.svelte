<script lang="ts">
	import '../app.css';
	import type { Snippet } from 'svelte';
	import DocNav from '$lib/components/DocNav.svelte';
	import { base } from '$app/paths';

	let { data, children }: { data: any; children: Snippet } = $props();
	let sidebarOpen = $state(true);
</script>

<div class="h-full flex">
	<!-- Mobile menu button -->
	<button
		class="fixed top-3 left-3 z-50 p-2 rounded-lg bg-surface-800 border border-surface-600 md:hidden"
		onclick={() => sidebarOpen = !sidebarOpen}
		aria-label="Toggle navigation"
	>
		<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
			{#if sidebarOpen}
				<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
			{:else}
				<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16" />
			{/if}
		</svg>
	</button>

	<!-- Sidebar -->
	<aside
		class="w-64 shrink-0 overflow-y-auto border-r border-surface-300 p-4
			fixed inset-y-0 left-0 z-40 bg-surface-900 transition-transform duration-200
			md:relative md:translate-x-0 md:bg-transparent
			{sidebarOpen ? 'translate-x-0' : '-translate-x-full'}"
	>
		<a href="{base}/" class="block mb-4">
			<h1 class="text-lg font-bold">GloriousFlywheel</h1>
			<p class="text-xs text-surface-500">attic-iac documentation</p>
		</a>
		<div class="border-b border-surface-700 mb-4"></div>

		{#if data.navigation}
			<DocNav items={data.navigation} />
		{/if}
	</aside>

	<!-- Overlay for mobile sidebar -->
	{#if sidebarOpen}
		<button
			class="fixed inset-0 z-30 bg-black/50 md:hidden"
			onclick={() => sidebarOpen = false}
			aria-label="Close navigation"
		></button>
	{/if}

	<main class="flex-1 overflow-auto p-8 md:p-8 pt-14 md:pt-8">
		{@render children()}
	</main>
</div>
