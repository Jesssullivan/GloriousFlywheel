<script lang="ts">
	import { Popover } from '@skeletonlabs/skeleton-svelte';
	import type { HPAStatus, Forge } from '$lib/types';

	let { hpa }: { hpa: HPAStatus } = $props();

	const cpuPercent = $derived(hpa.cpu_current ?? 0);
	const cpuTarget = $derived(hpa.cpu_target ?? 70);
	const memPercent = $derived(hpa.memory_current ?? 0);
	const memTarget = $derived(hpa.memory_target ?? 80);
	const replicaPercent = $derived(
		((hpa.current_replicas - hpa.min_replicas) / Math.max(hpa.max_replicas - hpa.min_replicas, 1)) * 100
	);

	function barColor(value: number, target: number): string {
		const ratio = value / target;
		if (ratio >= 0.9) return 'bg-red-500';
		if (ratio >= 0.7) return 'bg-yellow-500';
		return 'bg-green-500';
	}

	function forgeBadge(forge?: Forge): string {
		return forge === 'github' ? 'GH' : 'GL';
	}

	function forgeBadgeClass(forge?: Forge): string {
		return forge === 'github' ? 'bg-gray-700 text-white' : 'bg-orange-600 text-white';
	}

	function scalingLabel(hpa: HPAStatus): string {
		if (hpa.scaling_model === 'arc') {
			return hpa.min_replicas === 0 ? 'ARC (scale-to-zero)' : 'ARC';
		}
		return 'HPA';
	}

	function conditionIcon(status: string): string {
		return status === 'True' ? '✓' : '✗';
	}
</script>

<Popover positioning={{ placement: 'bottom' }} portalled>
	<Popover.Trigger class="w-full text-left cursor-pointer card p-4 bg-surface-100-800 rounded-lg border border-surface-300-600 hover:border-primary-500/50 transition-colors">
		<div class="flex items-center justify-between mb-3">
			<div class="flex items-center gap-2">
				<span class="font-medium">{hpa.name}</span>
				<span class="inline-flex items-center px-1.5 py-0.5 text-xs font-medium rounded {forgeBadgeClass(hpa.forge)}">
					{forgeBadge(hpa.forge)}
				</span>
				<span class="inline-flex items-center px-1.5 py-0.5 text-xs font-medium rounded bg-surface-300-600 text-surface-700-200">
					{scalingLabel(hpa)}
				</span>
			</div>
			<span class="text-sm text-surface-500">
				{hpa.current_replicas}/{hpa.max_replicas} replicas
			</span>
		</div>

		<div class="space-y-2">
			<div>
				<div class="flex justify-between text-xs text-surface-500 mb-0.5">
					<span>CPU</span>
					<span>{cpuPercent}% / {cpuTarget}%</span>
				</div>
				<div class="w-full h-2 bg-surface-300-600 rounded-full overflow-hidden">
					<div
						class="h-full rounded-full transition-all {barColor(cpuPercent, cpuTarget)}"
						style:width="{Math.min(cpuPercent, 100)}%"
					></div>
				</div>
			</div>

			<div>
				<div class="flex justify-between text-xs text-surface-500 mb-0.5">
					<span>Memory</span>
					<span>{memPercent}% / {memTarget}%</span>
				</div>
				<div class="w-full h-2 bg-surface-300-600 rounded-full overflow-hidden">
					<div
						class="h-full rounded-full transition-all {barColor(memPercent, memTarget)}"
						style:width="{Math.min(memPercent, 100)}%"
					></div>
				</div>
			</div>

			<div>
				<div class="flex justify-between text-xs text-surface-500 mb-0.5">
					<span>Scale</span>
					<span>{hpa.current_replicas} ({hpa.min_replicas}-{hpa.max_replicas})</span>
				</div>
				<div class="w-full h-2 bg-surface-300-600 rounded-full overflow-hidden">
					<div
						class="h-full rounded-full transition-all bg-primary-500"
						style:width="{Math.min(replicaPercent, 100)}%"
					></div>
				</div>
			</div>
		</div>
	</Popover.Trigger>
	<Popover.Positioner>
		<Popover.Content class="card p-4 bg-surface-100-800 border border-surface-300-600 rounded-lg shadow-xl w-80 z-50">
			<Popover.Arrow>
				<Popover.ArrowTip />
			</Popover.Arrow>
			<Popover.Title class="text-sm font-semibold mb-2">{hpa.name}</Popover.Title>
			<Popover.Description>
				<div class="space-y-3 text-xs">
					<div class="grid grid-cols-2 gap-x-4 gap-y-1">
						<span class="text-surface-500">Scaling</span>
						<span>{scalingLabel(hpa)}</span>
						<span class="text-surface-500">Current</span>
						<span>{hpa.current_replicas} replicas</span>
						<span class="text-surface-500">Desired</span>
						<span>{hpa.desired_replicas} replicas</span>
						<span class="text-surface-500">Range</span>
						<span>{hpa.min_replicas}–{hpa.max_replicas}</span>
						{#if hpa.cpu_current != null}
							<span class="text-surface-500">CPU</span>
							<span>{cpuPercent}% of {cpuTarget}% target</span>
						{/if}
						{#if hpa.memory_current != null}
							<span class="text-surface-500">Memory</span>
							<span>{memPercent}% of {memTarget}% target</span>
						{/if}
					</div>
					{#if hpa.conditions.length > 0}
						<div class="border-t border-surface-300-600 pt-2">
							<span class="text-surface-500 font-medium">Conditions</span>
							<ul class="mt-1 space-y-0.5">
								{#each hpa.conditions as cond}
									<li class="flex items-start gap-1.5">
										<span class={cond.status === 'True' ? 'text-green-500' : 'text-red-500'}>
											{conditionIcon(cond.status)}
										</span>
										<span>
											<span class="font-medium">{cond.type}</span>
											{#if cond.message}
												— {cond.message}
											{/if}
										</span>
									</li>
								{/each}
							</ul>
						</div>
					{/if}
				</div>
			</Popover.Description>
		</Popover.Content>
	</Popover.Positioner>
</Popover>
