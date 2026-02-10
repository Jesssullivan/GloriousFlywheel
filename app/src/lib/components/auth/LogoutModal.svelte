<script lang="ts">
	let {
		open = $bindable(false),
		authMethod = 'oauth'
	}: {
		open: boolean;
		authMethod: string;
	} = $props();

	let loading = $state(false);

	async function logout(mode: 'app_only' | 'full') {
		loading = true;
		try {
			const res = await fetch('/auth/logout', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ mode })
			});
			const data = await res.json();
			if (data.redirect) {
				window.location.href = data.redirect;
			}
		} catch {
			window.location.href = '/auth/logout';
		}
	}
</script>

{#if open}
	<!-- svelte-ignore a11y_no_static_element_interactions -->
	<div
		class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
		onkeydown={(e) => e.key === 'Escape' && (open = false)}
	>
		<!-- svelte-ignore a11y_click_events_have_key_events -->
		<div class="fixed inset-0" onclick={() => (open = false)}></div>
		<div class="relative bg-surface-100-800 rounded-lg border border-surface-300-600 p-6 w-96 shadow-xl space-y-4">
			<h3 class="text-lg font-semibold">Sign Out</h3>
			<p class="text-sm text-surface-400">Choose how you'd like to sign out.</p>

			<div class="space-y-2">
				<button
					onclick={() => logout('app_only')}
					disabled={loading}
					class="w-full px-4 py-2 rounded border border-surface-300-600 text-sm hover:bg-surface-200-700 transition-colors disabled:opacity-50"
				>
					Sign out of Dashboard
				</button>

				{#if authMethod === 'oauth'}
					<button
						onclick={() => logout('full')}
						disabled={loading}
						class="w-full px-4 py-2 rounded border border-error-500/50 text-error-600 dark:text-error-400 text-sm hover:bg-error-50 dark:hover:bg-error-900/20 transition-colors disabled:opacity-50"
					>
						Sign out of Everything (incl. GitLab)
					</button>
				{/if}
			</div>

			<button
				onclick={() => (open = false)}
				disabled={loading}
				class="w-full text-center text-sm text-surface-400 hover:text-surface-300 transition-colors"
			>
				Cancel
			</button>
		</div>
	</div>
{/if}
