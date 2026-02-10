<script lang="ts">
	import { browserSupportsWebAuthn, startAuthentication } from '@simplewebauthn/browser';

	let webauthnSupported = $state(false);
	let webauthnLoading = $state(false);
	let webauthnError = $state('');

	$effect(() => {
		webauthnSupported = browserSupportsWebAuthn();
	});

	async function loginWithPasskey() {
		webauthnLoading = true;
		webauthnError = '';
		try {
			const optionsRes = await fetch('/auth/webauthn/authenticate');
			const options = await optionsRes.json();

			const credential = await startAuthentication({ optionsJSON: options });

			const verifyRes = await fetch('/auth/webauthn/authenticate', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify(credential)
			});
			const result = await verifyRes.json();

			if (result.verified && result.redirect) {
				window.location.href = result.redirect;
			} else {
				webauthnError = 'Authentication failed';
			}
		} catch (e) {
			webauthnError = e instanceof Error ? e.message : 'Passkey authentication failed';
		} finally {
			webauthnLoading = false;
		}
	}
</script>

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

			{#if webauthnSupported}
				<button
					onclick={loginWithPasskey}
					disabled={webauthnLoading}
					class="flex items-center justify-center gap-2 w-full px-4 py-3 rounded border border-surface-300-600 hover:bg-surface-200-700 font-medium transition-colors disabled:opacity-50"
				>
					{webauthnLoading ? 'Authenticating...' : 'Sign in with Passkey'}
				</button>
			{/if}

			{#if webauthnError}
				<p class="text-sm text-error-500">{webauthnError}</p>
			{/if}
		</div>
	</div>
</div>
