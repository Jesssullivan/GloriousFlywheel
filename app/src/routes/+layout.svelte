<script lang="ts">
	import '../app.css';
	import type { Snippet } from 'svelte';
	import Sidebar from '$lib/components/nav/Sidebar.svelte';
	import Breadcrumb from '$lib/components/nav/Breadcrumb.svelte';
	import { initEnvironments } from '$lib/stores/environment';

	let { data, children }: { data: any; children: Snippet } = $props();

	$effect(() => {
		if (data.environments) {
			initEnvironments(data.environments);
		}
	});
</script>

<div class="h-full flex">
	<Sidebar />

	<main class="flex-1 overflow-auto p-6">
		<Breadcrumb />
		{@render children()}
	</main>
</div>
