<script lang="ts">
	import HPAGauge from '$lib/components/metrics/HPAGauge.svelte';
	import MetricCard from '$lib/components/metrics/MetricCard.svelte';
	import DataTable from '$lib/components/common/DataTable.svelte';
	import type { HPAStatus, PodInfo, MetricCardData } from '$lib/types';

	let { data } = $props();

	const metrics = $derived(data.metrics as MetricCardData[]);
	const hpas = $derived(data.hpas as HPAStatus[]);
	const pods = $derived(data.pods as PodInfo[]);
</script>

<svelte:head>
	<title>Monitoring - Runner Dashboard</title>
</svelte:head>

<div class="space-y-6">
	<h2 class="text-2xl font-bold">Monitoring</h2>

	<!-- Overview metrics -->
	<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
		{#each metrics as metric}
			<MetricCard {metric} />
		{/each}
	</div>

	<!-- HPA gauges -->
	<div>
		<h3 class="text-lg font-semibold mb-3">Autoscaling</h3>
		<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
			{#each hpas as hpa}
				<HPAGauge {hpa} />
			{/each}
		</div>
	</div>

	<!-- Pod table -->
	<div>
		<h3 class="text-lg font-semibold mb-3">Pods</h3>
		<DataTable
			data={pods as unknown as Record<string, unknown>[]}
			columns={[
				{ key: 'name', label: 'Name' },
				{ key: 'status', label: 'Status', width: '100px' },
				{ key: 'restarts', label: 'Restarts', width: '80px' },
				{ key: 'age', label: 'Age', width: '80px' },
				{ key: 'runner', label: 'Runner' }
			]}
		/>
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
