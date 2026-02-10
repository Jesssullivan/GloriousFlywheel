<svelte:head>
	<title>Sign In - Runner Dashboard</title>
</svelte:head>

<div class="flex items-center justify-center h-full">
	<div class="text-center space-y-6">
		<div class="space-y-2">
			<h1 class="text-2xl font-bold">Runner Dashboard</h1>
			<p class="text-surface-400">Sign in to manage your runner fleet</p>
		</div>

		<div class="space-y-3 w-72">
			<a
				href="/auth/login/gitlab"
				class="flex items-center justify-center gap-2 w-full px-4 py-3 rounded bg-primary-500 hover:bg-primary-600 text-white font-medium transition-colors"
			>
				Sign in with GitLab
			</a>
		</div>
	</div>
</div>
