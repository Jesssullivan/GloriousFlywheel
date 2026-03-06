<script lang="ts">
	import HPAGauge from '$lib/components/metrics/HPAGauge.svelte';
	import MetricCard from '$lib/components/metrics/MetricCard.svelte';
	import DataTable from '$lib/components/common/DataTable.svelte';
	import type { HPAStatus, PodInfo, MetricCardData, Forge } from '$lib/types';

	let { data } = $props();

	const metrics = $derived(data.metrics as MetricCardData[]);
	const hpas = $derived(data.hpas as HPAStatus[]);
	const pods = $derived(data.pods as PodInfo[]);

	type ForgeFilter = 'all' | Forge;
	let forgeFilter: ForgeFilter = $state('all');

	const filteredHpas = $derived(
		forgeFilter === 'all' ? hpas : hpas.filter((h) => (h.forge ?? 'gitlab') === forgeFilter)
	);
	const filteredPods = $derived(
		forgeFilter === 'all' ? pods : pods.filter((p) => (p.forge ?? 'gitlab') === forgeFilter)
	);

	function forgeBadge(forge?: Forge): string {
		return forge === 'github' ? 'GH' : 'GL';
	}

	function forgeBadgeClass(forge?: Forge): string {
		return forge === 'github' ? 'bg-gray-700 text-white' : 'bg-orange-600 text-white';
	}
</script>

<svelte:head>
	<title>Monitoring - Runner Dashboard</title>
</svelte:head>

<div class="space-y-6">
	<div class="flex items-center justify-between">
		<h2 class="text-2xl font-bold">Monitoring</h2>
		<div class="flex gap-1">
			<button
				class="px-3 py-1 text-sm rounded-lg transition-colors {forgeFilter === 'all'
					? 'bg-primary-500 text-white'
					: 'bg-surface-200-700 hover:bg-surface-300-600'}"
				onclick={() => (forgeFilter = 'all')}
			>
				All
			</button>
			<button
				class="px-3 py-1 text-sm rounded-lg transition-colors {forgeFilter === 'gitlab'
					? 'bg-orange-600 text-white'
					: 'bg-surface-200-700 hover:bg-surface-300-600'}"
				onclick={() => (forgeFilter = 'gitlab')}
			>
				GitLab
			</button>
			<button
				class="px-3 py-1 text-sm rounded-lg transition-colors {forgeFilter === 'github'
					? 'bg-gray-700 text-white'
					: 'bg-surface-200-700 hover:bg-surface-300-600'}"
				onclick={() => (forgeFilter = 'github')}
			>
				GitHub
			</button>
		</div>
	</div>

	<!-- Overview metrics -->
	<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
		{#each metrics as metric}
			<MetricCard {metric} />
		{/each}
	</div>

	<!-- HPA / Autoscaler gauges -->
	<div>
		<h3 class="text-lg font-semibold mb-3">Autoscaling</h3>
		<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
			{#each filteredHpas as hpa}
				<HPAGauge {hpa} />
			{/each}
		</div>
	</div>

	<!-- Pod table -->
	<div>
		<h3 class="text-lg font-semibold mb-3">Pods</h3>
		{#if filteredPods.length > 0}
			<div class="overflow-x-auto">
				<table class="w-full text-sm">
					<thead>
						<tr class="border-b border-surface-300-600">
							<th class="text-left py-2 px-3 font-medium">Forge</th>
							<th class="text-left py-2 px-3 font-medium">Name</th>
							<th class="text-left py-2 px-3 font-medium w-24">Status</th>
							<th class="text-left py-2 px-3 font-medium w-20">Restarts</th>
							<th class="text-left py-2 px-3 font-medium w-20">Age</th>
							<th class="text-left py-2 px-3 font-medium">Runner</th>
						</tr>
					</thead>
					<tbody>
						{#each filteredPods as pod}
							<tr class="border-b border-surface-200-700">
								<td class="py-2 px-3">
									<span
										class="inline-flex items-center px-1.5 py-0.5 text-xs font-medium rounded {forgeBadgeClass(
											pod.forge
										)}"
									>
										{forgeBadge(pod.forge)}
									</span>
								</td>
								<td class="py-2 px-3 font-mono text-xs">{pod.name}</td>
								<td class="py-2 px-3">
									<span
										class="inline-flex items-center px-2 py-0.5 text-xs rounded-full {pod.status ===
										'Running'
											? 'bg-green-500/20 text-green-600 dark:text-green-400'
											: pod.status === 'Pending'
												? 'bg-yellow-500/20 text-yellow-600 dark:text-yellow-400'
												: 'bg-red-500/20 text-red-600 dark:text-red-400'}"
									>
										{pod.status}
									</span>
								</td>
								<td class="py-2 px-3">{pod.restarts}</td>
								<td class="py-2 px-3">{pod.age}</td>
								<td class="py-2 px-3">{pod.runner}</td>
							</tr>
						{/each}
					</tbody>
				</table>
			</div>
		{:else}
			<p class="text-sm text-surface-500">No pods found for the selected filter.</p>
		{/if}
	</div>

	<!-- Data source status -->
	{#if !data.prometheusAvailable}
		<div class="rounded-lg border border-warning-500/30 bg-warning-500/10 p-4">
			<p class="text-sm text-warning-600 dark:text-warning-400">
				Prometheus is not available. Showing mock data. Enable
				<code class="font-mono">service_monitor_enabled</code> in the environment tfvars for live metrics.
			</p>
		</div>
	{/if}
	{#if !data.k8sAvailable}
		<div class="rounded-lg border border-warning-500/30 bg-warning-500/10 p-4">
			<p class="text-sm text-warning-600 dark:text-warning-400">
				Kubernetes API is not reachable. Showing mock data. Run <code class="font-mono">kubectl proxy</code> for live pod data.
			</p>
		</div>
	{/if}
</div>
