<script lang="ts">
	import MetricCard from '$lib/components/metrics/MetricCard.svelte';
	import HPAGauge from '$lib/components/metrics/HPAGauge.svelte';
	import RunnerCard from '$lib/components/runner/RunnerCard.svelte';

	let { data } = $props();
</script>

<svelte:head>
	<title>Dashboard - Runner Dashboard</title>
</svelte:head>

<div class="space-y-6">
	<h2 class="text-2xl font-bold">Dashboard Overview</h2>

	<!-- Metric cards -->
	<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
		{#each data.metrics as metric}
			<MetricCard {metric} />
		{/each}
	</div>

	<!-- Runner fleet -->
	<div>
		<h3 class="text-lg font-semibold mb-3">Runner Fleet</h3>
		<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
			{#each data.runners as runner}
				<RunnerCard {runner} />
			{/each}
		</div>
	</div>

	<!-- HPA Status -->
	<div>
		<h3 class="text-lg font-semibold mb-3">Autoscaling Status</h3>
		<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
			{#each data.hpas as hpa}
				<HPAGauge {hpa} />
			{/each}
		</div>
	</div>
</div>
