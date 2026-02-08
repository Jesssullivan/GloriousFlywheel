<script lang="ts">
	interface Props {
		diff: string;
		filename?: string;
	}

	let { diff, filename = 'dev.tfvars' }: Props = $props();

	const lines = $derived(diff.split('\n'));
</script>

<div class="rounded-lg border border-surface-300 dark:border-surface-600 overflow-hidden">
	<div class="bg-surface-200 dark:bg-surface-700 px-4 py-2 text-sm font-mono text-surface-600 dark:text-surface-400">
		{filename}
	</div>
	<div class="overflow-x-auto">
		<pre class="text-xs leading-5 p-0 m-0"><code>{#each lines as line, i}<span
			class="inline-block w-full px-4 {line.startsWith('+')
				? 'bg-success-100 dark:bg-success-900/20 text-success-700 dark:text-success-300'
				: line.startsWith('-')
					? 'bg-error-100 dark:bg-error-900/20 text-error-700 dark:text-error-300'
					: line.startsWith('@@')
						? 'bg-primary-100 dark:bg-primary-900/20 text-primary-600 dark:text-primary-400'
						: 'text-surface-700 dark:text-surface-300'}"
			><span class="inline-block w-8 text-right mr-3 text-surface-400 select-none">{i + 1}</span>{line}
</span>{/each}</code></pre>
	</div>
</div>
