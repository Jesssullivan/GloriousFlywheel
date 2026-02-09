<script lang="ts">
	import { base } from '$app/paths';
	import { onMount } from 'svelte';
	import { browser } from '$app/environment';

	let diagramEl: HTMLDivElement;

	onMount(async () => {
		if (!browser || !diagramEl) return;
		const mermaid = (await import('mermaid')).default;
		mermaid.initialize({ startOnLoad: false, theme: 'dark', securityLevel: 'loose' });
		const source = `graph LR
    R[Runners] -->|"tofu apply"| R
    R -->|deploy| AC[Attic Cache]
    AC -->|accelerates| NB[Nix Builds]
    NB -->|"executed by"| R
    R -->|deploy| D[Dashboard]
    D -->|monitors| R
    AC -->|"caches its own derivations"| AC`;
		try {
			const { svg } = await mermaid.render('hero-diagram', source);
			diagramEl.innerHTML = svg;
		} catch (err) {
			console.warn('Hero diagram failed:', err);
		}
	});
</script>

<svelte:head>
	<title>GloriousFlywheel - Documentation</title>
</svelte:head>

<div class="max-w-6xl mx-auto">
	<!-- Hero -->
	<div class="text-center mb-10">
		<h1 class="text-5xl font-bold mb-3">GloriousFlywheel</h1>
		<p class="text-xl text-surface-400 mb-2">
			Self-deploying infrastructure that builds, caches, and monitors itself.
		</p>
		<p class="text-sm text-surface-500">
			Tested on RKE2 (on-premise) and Civo k3s (cloud)
		</p>
	</div>

	<!-- Hero diagram -->
	<div class="flex justify-center mb-10">
		<div bind:this={diagramEl} class="max-w-full"></div>
	</div>

	<!-- Feature cards -->
	<div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
		<a href="{base}/docs/architecture/recursive-dogfooding" class="block p-5 rounded-lg border border-surface-600 hover:border-primary-500 hover:bg-surface-800/50 transition-all">
			<h3 class="font-semibold mb-2">Recursive Dogfooding</h3>
			<p class="text-sm text-surface-400">Infrastructure that deploys itself using itself.</p>
		</a>
		<a href="{base}/docs/architecture/bzlmod-topology" class="block p-5 rounded-lg border border-surface-600 hover:border-primary-500 hover:bg-surface-800/50 transition-all">
			<h3 class="font-semibold mb-2">Bzlmod Topology</h3>
			<p class="text-sm text-surface-400">Two-module architecture with overlay merge.</p>
		</a>
		<a href="{base}/docs/build-system/greedy-build-pattern" class="block p-5 rounded-lg border border-surface-600 hover:border-primary-500 hover:bg-surface-800/50 transition-all">
			<h3 class="font-semibold mb-2">Greedy Build Pattern</h3>
			<p class="text-sm text-surface-400">Build immediately, cache incrementally, validate later.</p>
		</a>
		<a href="{base}/docs/infrastructure/quick-start" class="block p-5 rounded-lg border border-surface-600 hover:border-primary-500 hover:bg-surface-800/50 transition-all">
			<h3 class="font-semibold mb-2">Quick Start</h3>
			<p class="text-sm text-surface-400">Deploy the full stack from zero.</p>
		</a>
		<a href="{base}/docs/infrastructure/tested-deployments" class="block p-5 rounded-lg border border-surface-600 hover:border-primary-500 hover:bg-surface-800/50 transition-all">
			<h3 class="font-semibold mb-2">Tested Deployments</h3>
			<p class="text-sm text-surface-400">RKE2 on-premise and Civo k3s cloud guides.</p>
		</a>
		<a href="{base}/docs/infrastructure/gitlab-oauth" class="block p-5 rounded-lg border border-surface-600 hover:border-primary-500 hover:bg-surface-800/50 transition-all">
			<h3 class="font-semibold mb-2">GitLab OAuth</h3>
			<p class="text-sm text-surface-400">Set up SSO for the runner dashboard.</p>
		</a>
	</div>

	<!-- Branding -->
	<div class="mt-16 border-t border-surface-700 pt-10 space-y-8 text-center">
		<div>
			<p class="text-sm font-semibold text-surface-400 uppercase tracking-wide">A Tinyland.dev, Inc project</p>
			<p class="mt-2 text-surface-500 max-w-2xl mx-auto">
				Building brutally resilient infrastructure at the intersection of individual authenticity and communal security.
			</p>
		</div>
		<div>
			<p class="text-sm text-surface-400">
				built with <a href="https://xoxd.ai" target="_blank" rel="noopener noreferrer" class="font-semibold text-primary-500 hover:text-primary-400 transition-colors">xoxd.ai</a>
			</p>
			<p class="mt-2 text-surface-500 max-w-2xl mx-auto">
				Orchestrating massively parallel, provable agent infrastructure at the intersection of autonomous scale and cryptographic integrity. xoxd.ai ^w^
			</p>
		</div>
	</div>
</div>
