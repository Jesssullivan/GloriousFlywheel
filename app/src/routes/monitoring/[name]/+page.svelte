<script lang="ts">
	import RunnerTypeBadge from '$lib/components/runner/RunnerTypeBadge.svelte';
	import MetricCard from '$lib/components/metrics/MetricCard.svelte';
	import TimeSeriesChart from '$lib/components/charts/TimeSeriesChart.svelte';
	import type { TimeSeriesData } from '$lib/types';

	let { data } = $props();

	const windows = ['1h', '6h', '24h', '7d'] as const;
	let selectedWindow = $state(data.window);

	const cpuData = $derived((data.metricsData.timeSeries?.cpu ?? []) as TimeSeriesData[]);
	const memoryData = $derived((data.metricsData.timeSeries?.memory ?? []) as TimeSeriesData[]);
	const jobsData = $derived((data.metricsData.timeSeries?.jobs ?? []) as TimeSeriesData[]);
</script>

<svelte:head>
	<title>{data.runner.name} Metrics - Runner Dashboard</title>
</svelte:head>

<div class="space-y-6">
	<div class="flex items-center justify-between">
		<div class="flex items-center gap-3">
			<h2 class="text-2xl font-bold">{data.runner.name}</h2>
			<RunnerTypeBadge type={data.runner.type} />
		</div>
		<div class="flex gap-1">
			{#each windows as w}
				<a
					href="?window={w}"
					class="px-3 py-1 rounded text-sm transition-colors
						{selectedWindow === w
						? 'bg-primary-500 text-white'
						: 'bg-surface-200 dark:bg-surface-700 hover:bg-surface-300 dark:hover:bg-surface-600'}"
					onclick={() => (selectedWindow = w)}
				>
					{w}
				</a>
			{/each}
		</div>
	</div>

	<!-- Current metrics -->
	<div class="grid grid-cols-1 md:grid-cols-3 gap-4">
		<MetricCard
			metric={{
				label: 'Total Jobs',
				value: data.metricsData.current?.totalJobs ?? 0,
				unit: '',
				trend: 'stable'
			}}
		/>
		<MetricCard
			metric={{
				label: 'Failed Jobs',
				value: data.metricsData.current?.failedJobs ?? 0,
				unit: '',
				trend: 'stable'
			}}
		/>
		<MetricCard
			metric={{
				label: 'Jobs/min',
				value: Math.round((data.metricsData.current?.jobsPerMinute ?? 0) * 100) / 100,
				unit: '/min',
				trend: 'stable'
			}}
		/>
	</div>

	<!-- Charts -->
	{#if data.metricsData.available}
		<div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
			<div class="card p-4 bg-surface-100-800 rounded-lg border border-surface-300-600">
				<TimeSeriesChart title="CPU Usage" data={cpuData} yLabel="cores" height={250} />
			</div>
			<div class="card p-4 bg-surface-100-800 rounded-lg border border-surface-300-600">
				<TimeSeriesChart title="Memory Usage" data={memoryData} yLabel="bytes" height={250} />
			</div>
			<div class="card p-4 bg-surface-100-800 rounded-lg border border-surface-300-600 lg:col-span-2">
				<TimeSeriesChart title="Jobs per Minute" data={jobsData} yLabel="jobs/min" height={250} />
			</div>
		</div>
	{:else}
		<div class="rounded-lg border border-warning-500/30 bg-warning-500/10 p-6 text-center">
			<p class="text-warning-600 dark:text-warning-400">
				Prometheus is not available. Charts will appear when metrics are being collected.
			</p>
			<p class="text-sm text-surface-500 mt-2">
				Enable <code class="font-mono">service_monitor_enabled = true</code> in the environment tfvars
			</p>
		</div>
	{/if}
</div>
