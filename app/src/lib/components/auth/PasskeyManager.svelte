<script lang="ts">
	import { browserSupportsWebAuthn, startRegistration } from '@simplewebauthn/browser';

	let { authMethod = 'oauth' }: { authMethod: string } = $props();

	interface PasskeyInfo {
		credential_id: string;
		device_type: string;
		backed_up: boolean;
		created_at: string;
		last_used_at: string | null;
	}

	let passkeys = $state<PasskeyInfo[]>([]);
	let loading = $state(true);
	let registering = $state(false);
	let error = $state('');

	$effect(() => {
		loadPasskeys();
	});

	async function loadPasskeys() {
		loading = true;
		try {
			const res = await fetch('/auth/webauthn/credentials');
			if (res.ok) {
				passkeys = await res.json();
			}
		} catch {
			// Ignore — WebAuthn may not be configured
		} finally {
			loading = false;
		}
	}

	async function registerPasskey() {
		registering = true;
		error = '';
		try {
			const optionsRes = await fetch('/auth/webauthn/register');
			if (!optionsRes.ok) {
				throw new Error('Failed to get registration options');
			}
			const options = await optionsRes.json();

			const credential = await startRegistration({ optionsJSON: options });

			const verifyRes = await fetch('/auth/webauthn/register', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify(credential)
			});
			const result = await verifyRes.json();

			if (result.verified) {
				await loadPasskeys();
			} else {
				error = 'Registration failed';
			}
		} catch (e) {
			error = e instanceof Error ? e.message : 'Passkey registration failed';
		} finally {
			registering = false;
		}
	}

	async function removePasskey(credentialId: string) {
		try {
			await fetch('/auth/webauthn/credentials', {
				method: 'DELETE',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ credential_id: credentialId })
			});
			await loadPasskeys();
		} catch {
			error = 'Failed to remove passkey';
		}
	}

	function formatDate(date: string | null) {
		if (!date) return 'Never';
		return new Date(date).toLocaleDateString(undefined, {
			year: 'numeric',
			month: 'short',
			day: 'numeric'
		});
	}

	const canRegister = $derived(authMethod === 'oauth' && browserSupportsWebAuthn());
</script>

<div class="space-y-3">
	<div class="flex items-center justify-between">
		<h4 class="text-sm font-medium">Passkeys</h4>
		{#if canRegister}
			<button
				onclick={registerPasskey}
				disabled={registering}
				class="text-xs px-3 py-1 rounded border border-primary-500 text-primary-500 hover:bg-primary-500/10 transition-colors disabled:opacity-50"
			>
				{registering ? 'Registering...' : 'Add Passkey'}
			</button>
		{/if}
	</div>

	{#if loading}
		<p class="text-sm text-surface-400">Loading...</p>
	{:else if passkeys.length === 0}
		<p class="text-sm text-surface-400">No passkeys registered.</p>
	{:else}
		<ul class="space-y-2">
			{#each passkeys as passkey}
				<li class="flex items-center justify-between text-sm p-2 rounded bg-surface-200-700">
					<div>
						<span class="capitalize">{passkey.device_type}</span>
						{#if passkey.backed_up}
							<span class="text-xs text-success-500 ml-1">synced</span>
						{/if}
						<div class="text-xs text-surface-400">
							Added {formatDate(passkey.created_at)} · Last used {formatDate(passkey.last_used_at)}
						</div>
					</div>
					<button
						onclick={() => removePasskey(passkey.credential_id)}
						class="text-xs text-error-500 hover:text-error-400 transition-colors"
					>
						Remove
					</button>
				</li>
			{/each}
		</ul>
	{/if}

	{#if error}
		<p class="text-sm text-error-500">{error}</p>
	{/if}

	{#if authMethod !== 'oauth'}
		<p class="text-xs text-surface-400">Sign in with GitLab to manage passkeys.</p>
	{/if}
</div>
