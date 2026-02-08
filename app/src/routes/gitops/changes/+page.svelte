<script lang="ts">
	import DiffViewer from '$lib/components/gitops/DiffViewer.svelte';

	let previewDiff = $state('');
	let submitting = $state(false);
	let description = $state('');

	// Example: show a static diff preview for now
	const sampleDiff = `--- a/dev.tfvars
+++ b/dev.tfvars
 docker_concurrent_jobs = 8
-dind_concurrent_jobs   = 4
+dind_concurrent_jobs   = 6
 rocky8_concurrent_jobs = 4`;

	function showPreview() {
		previewDiff = sampleDiff;
	}
</script>

<svelte:head>
	<title>Propose Changes - Runner Dashboard</title>
</svelte:head>

<div class="space-y-6">
	<div class="flex items-center justify-between">
		<h2 class="text-2xl font-bold">Propose Changes</h2>
		<a
			href="/gitops"
			class="px-3 py-1.5 rounded text-sm border border-surface-300 dark:border-surface-600 hover:bg-surface-100 dark:hover:bg-surface-700 transition-colors"
		>
			Back to GitOps
		</a>
	</div>

	<div class="card p-6 bg-surface-100-800 rounded-lg border border-surface-300-600">
		<h3 class="font-semibold mb-4">Change Description</h3>
		<textarea
			bind:value={description}
			placeholder="Describe why these changes are needed..."
			class="w-full rounded border border-surface-300 dark:border-surface-600 bg-surface-50 dark:bg-surface-800 p-3 text-sm resize-y min-h-[80px]"
		></textarea>
	</div>

	<div class="card p-6 bg-surface-100-800 rounded-lg border border-surface-300-600">
		<div class="flex items-center justify-between mb-4">
			<h3 class="font-semibold">Preview</h3>
			<button
				onclick={showPreview}
				class="px-3 py-1 rounded text-sm bg-surface-200 dark:bg-surface-700 hover:bg-surface-300 dark:hover:bg-surface-600"
			>
				Generate Preview
			</button>
		</div>

		{#if previewDiff}
			<DiffViewer diff={previewDiff} />
		{:else}
			<p class="text-surface-500 text-sm text-center py-4">
				Edit runner configuration and click "Generate Preview" to see changes.
			</p>
		{/if}
	</div>

	{#if previewDiff}
		<div class="flex gap-3">
			<button
				disabled={submitting || !description}
				onclick={() => {
					submitting = true;
					// TODO: Wire to submitChanges() API
					setTimeout(() => (submitting = false), 1000);
				}}
				class="px-4 py-2 rounded bg-primary-500 text-white text-sm font-medium hover:bg-primary-600 disabled:opacity-50"
			>
				{submitting ? 'Creating MR...' : 'Create Merge Request'}
			</button>
		</div>
	{/if}
</div>
