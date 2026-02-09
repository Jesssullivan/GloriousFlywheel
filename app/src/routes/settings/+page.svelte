<script lang="ts">
	import { page } from '$app/stores';

	const user = $derived($page.data.user);
</script>

<svelte:head>
	<title>Settings - Runner Dashboard</title>
</svelte:head>

<div class="space-y-6">
	<h2 class="text-2xl font-bold">Settings</h2>

	<!-- User Info -->
	<div class="card p-6 bg-surface-100-800 rounded-lg border border-surface-300-600">
		<h3 class="font-semibold mb-3">User</h3>
		{#if user}
			<dl class="space-y-2 text-sm">
				<div class="flex justify-between">
					<dt class="text-surface-500">Username</dt>
					<dd>{user.username}</dd>
				</div>
				<div class="flex justify-between">
					<dt class="text-surface-500">Name</dt>
					<dd>{user.name}</dd>
				</div>
				<div class="flex justify-between">
					<dt class="text-surface-500">Email</dt>
					<dd>{user.email}</dd>
				</div>
				<div class="flex justify-between">
					<dt class="text-surface-500">Role</dt>
					<dd class="capitalize">{user.role}</dd>
				</div>
			</dl>
		{:else}
			<p class="text-surface-500 text-sm">Not authenticated.</p>
		{/if}
	</div>

	<!-- About -->
	<div class="card p-6 bg-surface-100-800 rounded-lg border border-surface-300-600">
		<h3 class="font-semibold mb-3">About</h3>
		<dl class="space-y-2 text-sm">
			<div class="flex justify-between">
				<dt class="text-surface-500">Version</dt>
				<dd class="font-mono">0.1.0</dd>
			</div>
			<div class="flex justify-between">
				<dt class="text-surface-500">Platform</dt>
				<dd>SvelteKit + Skeleton UI</dd>
			</div>
			<div class="flex justify-between">
				<dt class="text-surface-500">Data Sources</dt>
				<dd>GitLab API, Prometheus, K8s API</dd>
			</div>
		</dl>
	</div>

	<!-- Danger Zone -->
	<div class="card p-6 bg-surface-100-800 rounded-lg border border-error-500/30">
		<h3 class="font-semibold text-error-600 dark:text-error-400 mb-3">Session</h3>
		<a
			href="/auth/logout"
			data-sveltekit-reload
			class="px-4 py-2 rounded border border-error-500 text-error-600 dark:text-error-400 text-sm hover:bg-error-50 dark:hover:bg-error-900/20 transition-colors"
		>
			Sign Out
		</a>
	</div>
</div>
