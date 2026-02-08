<script lang="ts">
	import { base } from '$app/paths';
</script>

<svelte:head>
	<title>GloriousFlywheel - attic-iac Documentation</title>
</svelte:head>

<div class="max-w-3xl">
	<h1 class="text-4xl font-bold mb-4">GloriousFlywheel</h1>
	<p class="text-lg text-surface-400 mb-8">
		Self-deploying infrastructure that builds, caches, and monitors itself.
	</p>

	<div class="grid grid-cols-1 md:grid-cols-2 gap-4">
		<a href="{base}/docs/architecture/recursive-dogfooding" class="block p-4 rounded-lg border border-surface-600 hover:border-primary-500 transition-colors">
			<h3 class="font-semibold mb-1">Recursive Dogfooding</h3>
			<p class="text-sm text-surface-400">Infrastructure that deploys itself using itself.</p>
		</a>
		<a href="{base}/docs/architecture/bzlmod-topology" class="block p-4 rounded-lg border border-surface-600 hover:border-primary-500 transition-colors">
			<h3 class="font-semibold mb-1">Bzlmod Topology</h3>
			<p class="text-sm text-surface-400">Two-module architecture with overlay merge.</p>
		</a>
		<a href="{base}/docs/build-system/greedy-build-pattern" class="block p-4 rounded-lg border border-surface-600 hover:border-primary-500 transition-colors">
			<h3 class="font-semibold mb-1">Greedy Build Pattern</h3>
			<p class="text-sm text-surface-400">Build immediately, cache incrementally, validate later.</p>
		</a>
		<a href="{base}/docs/infrastructure/quick-start" class="block p-4 rounded-lg border border-surface-600 hover:border-primary-500 transition-colors">
			<h3 class="font-semibold mb-1">Quick Start</h3>
			<p class="text-sm text-surface-400">Deploy the full stack from zero.</p>
		</a>
	</div>
</div>
