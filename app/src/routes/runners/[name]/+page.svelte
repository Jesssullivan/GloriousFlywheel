<script lang="ts">
	import RunnerTypeBadge from '$lib/components/runner/RunnerTypeBadge.svelte';
	import RunnerStatusIndicator from '$lib/components/runner/RunnerStatusIndicator.svelte';
	import RunnerTagList from '$lib/components/runner/RunnerTagList.svelte';
	import RunnerConfigForm from '$lib/components/forms/RunnerConfigForm.svelte';
	import type { RunnerConfig, RunnerStatus, RunnerType } from '$lib/types';

	let { data } = $props();

	let editing = $state(false);
	let status = $state<RunnerStatus>(data.runner.status);
	let actionLoading = $state(false);
	let saveResult: { mr_url: string; branch: string } | null = $state(null);
	let saveError: string | null = $state(null);
	let saving = $state(false);

	async function togglePause() {
		actionLoading = true;
		const action = status === 'paused' ? 'resume' : 'pause';
		try {
			const res = await fetch(`/api/runners/${data.runner.name}/${action}`, { method: 'POST' });
			if (res.ok) {
				const result = await res.json();
				status = result.status;
			}
		} finally {
			actionLoading = false;
		}
	}

	/** Map RunnerConfig fields to flat tfvars keys based on runner type prefix. */
	function configToTfvarsChanges(
		type: RunnerType,
		config: RunnerConfig
	): Record<string, string | number | boolean> {
		const prefix = type;
		return {
			[`${prefix}_concurrent`]: config.concurrent_jobs,
			[`${prefix}_default_image`]: config.default_image,
			[`${prefix}_run_untagged`]: config.run_untagged,
			[`${prefix}_protected`]: config.protected,
			[`${prefix}_privileged`]: config.privileged,
			[`${prefix}_manager_cpu_request`]: config.manager_resources.cpu_request,
			[`${prefix}_manager_cpu_limit`]: config.manager_resources.cpu_limit,
			[`${prefix}_manager_memory_request`]: config.manager_resources.memory_request,
			[`${prefix}_manager_memory_limit`]: config.manager_resources.memory_limit,
			[`${prefix}_job_cpu_request`]: config.job_resources.cpu_request,
			[`${prefix}_job_cpu_limit`]: config.job_resources.cpu_limit,
			[`${prefix}_job_memory_request`]: config.job_resources.memory_request,
			[`${prefix}_job_memory_limit`]: config.job_resources.memory_limit
		};
	}

	async function handleConfigSave(config: RunnerConfig) {
		saving = true;
		saveError = null;
		saveResult = null;

		try {
			const changes = configToTfvarsChanges(data.runner.type, config);
			const response = await fetch('/api/gitops/submit', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({
					changes,
					description: `Update ${data.runner.name} configuration via dashboard`
				})
			});

			if (!response.ok) {
				const text = await response.text();
				throw new Error(text);
			}

			saveResult = await response.json();
			editing = false;
		} catch (e) {
			saveError = e instanceof Error ? e.message : 'Save failed';
		} finally {
			saving = false;
		}
	}
</script>

<svelte:head>
	<title>{data.runner.name} - Runner Dashboard</title>
</svelte:head>

<div class="space-y-6">
	{#if saveResult}
		<div class="p-4 rounded-lg border border-success-500 bg-success-50 dark:bg-success-900/20 text-sm">
			Configuration change submitted as
			<a href={saveResult.mr_url} target="_blank" rel="noopener" class="underline font-medium">
				merge request
			</a>
			on branch <code class="text-xs">{saveResult.branch}</code>.
		</div>
	{/if}

	{#if saveError}
		<div class="p-4 rounded-lg border border-error-500 bg-error-50 dark:bg-error-900/20 text-sm">
			Failed to save configuration: {saveError}
		</div>
	{/if}

	<div class="flex items-start justify-between">
		<div>
			<h2 class="text-2xl font-bold">{data.runner.name}</h2>
			<div class="flex items-center gap-3 mt-2">
				<RunnerTypeBadge type={data.runner.type} />
				<RunnerStatusIndicator {status} />
			</div>
		</div>
		<div class="flex gap-2">
			<button
				onclick={togglePause}
				disabled={actionLoading}
				class="px-3 py-1.5 rounded text-sm border transition-colors
					{status === 'paused'
					? 'border-success-500 text-success-600 hover:bg-success-50 dark:hover:bg-success-900/20'
					: 'border-warning-500 text-warning-600 hover:bg-warning-50 dark:hover:bg-warning-900/20'}
					disabled:opacity-50"
			>
				{status === 'paused' ? 'Resume' : 'Pause'}
			</button>
			<button
				onclick={() => (editing = !editing)}
				disabled={saving}
				class="px-3 py-1.5 rounded text-sm border border-surface-300 dark:border-surface-600 hover:bg-surface-100 dark:hover:bg-surface-700 transition-colors disabled:opacity-50"
			>
				{editing ? 'Cancel Edit' : 'Edit Config'}
			</button>
		</div>
	</div>

	{#if editing}
		<div class="card p-6 bg-surface-100-800 rounded-lg border border-surface-300-600">
			<h3 class="font-semibold mb-4">
				{saving ? 'Submitting changes...' : 'Edit Configuration'}
			</h3>
			<RunnerConfigForm
				config={data.runner.config}
				onsubmit={handleConfigSave}
				oncancel={() => (editing = false)}
			/>
		</div>
	{:else}
		<div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
			<!-- Config panel -->
			<div class="card p-6 bg-surface-100-800 rounded-lg border border-surface-300-600">
				<h3 class="font-semibold mb-4">Configuration</h3>
				<dl class="space-y-2 text-sm">
					<div class="flex justify-between">
						<dt class="text-surface-500">Default Image</dt>
						<dd class="font-mono text-xs">{data.runner.config.default_image}</dd>
					</div>
					<div class="flex justify-between">
						<dt class="text-surface-500">Concurrent Jobs</dt>
						<dd>{data.runner.config.concurrent_jobs}</dd>
					</div>
					<div class="flex justify-between">
						<dt class="text-surface-500">Privileged</dt>
						<dd>{data.runner.config.privileged ? 'Yes' : 'No'}</dd>
					</div>
					<div class="flex justify-between">
						<dt class="text-surface-500">Run Untagged</dt>
						<dd>{data.runner.config.run_untagged ? 'Yes' : 'No'}</dd>
					</div>
					<div class="flex justify-between">
						<dt class="text-surface-500">Protected</dt>
						<dd>{data.runner.config.protected ? 'Yes' : 'No'}</dd>
					</div>
				</dl>
			</div>

			<!-- Resources panel -->
			<div class="card p-6 bg-surface-100-800 rounded-lg border border-surface-300-600">
				<h3 class="font-semibold mb-4">Resources</h3>
				<div class="space-y-4">
					<div>
						<h4 class="text-xs uppercase text-surface-500 mb-2">Manager Pod</h4>
						<dl class="grid grid-cols-2 gap-2 text-sm">
							<div>
								<dt class="text-surface-500">CPU</dt>
								<dd>
									{data.runner.config.manager_resources.cpu_request} /
									{data.runner.config.manager_resources.cpu_limit}
								</dd>
							</div>
							<div>
								<dt class="text-surface-500">Memory</dt>
								<dd>
									{data.runner.config.manager_resources.memory_request} /
									{data.runner.config.manager_resources.memory_limit}
								</dd>
							</div>
						</dl>
					</div>
					<div>
						<h4 class="text-xs uppercase text-surface-500 mb-2">Job Pods</h4>
						<dl class="grid grid-cols-2 gap-2 text-sm">
							<div>
								<dt class="text-surface-500">CPU</dt>
								<dd>
									{data.runner.config.job_resources.cpu_request} /
									{data.runner.config.job_resources.cpu_limit}
								</dd>
							</div>
							<div>
								<dt class="text-surface-500">Memory</dt>
								<dd>
									{data.runner.config.job_resources.memory_request} /
									{data.runner.config.job_resources.memory_limit}
								</dd>
							</div>
						</dl>
					</div>
				</div>
			</div>
		</div>

		<!-- HPA Status -->
		{#if data.runner.config.hpa.enabled}
			<div class="card p-6 bg-surface-100-800 rounded-lg border border-surface-300-600">
				<h3 class="font-semibold mb-3">Autoscaling</h3>
				<dl class="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
					<div>
						<dt class="text-surface-500">Replicas</dt>
						<dd>{data.runner.config.hpa.min_replicas} - {data.runner.config.hpa.max_replicas}</dd>
					</div>
					<div>
						<dt class="text-surface-500">CPU Target</dt>
						<dd>{data.runner.config.hpa.cpu_target}%</dd>
					</div>
					<div>
						<dt class="text-surface-500">Memory Target</dt>
						<dd>{data.runner.config.hpa.memory_target}%</dd>
					</div>
					<div>
						<dt class="text-surface-500">Scale Down Window</dt>
						<dd>{data.runner.config.hpa.scale_down_window}s</dd>
					</div>
				</dl>
			</div>
		{/if}

		<!-- Tags -->
		<div class="card p-6 bg-surface-100-800 rounded-lg border border-surface-300-600">
			<h3 class="font-semibold mb-3">Tags</h3>
			<RunnerTagList tags={data.runner.tags} limit={20} />
		</div>
	{/if}
</div>
