<script lang="ts">
	import { page } from '$app/stores';
	import EnvBadge from './EnvBadge.svelte';

	const navItems = [
		{ href: '/', label: 'Dashboard', icon: 'H' },
		{ href: '/runners', label: 'Runners', icon: 'R' },
		{ href: '/monitoring', label: 'Monitoring', icon: 'M' },
		{ href: '/gitops', label: 'GitOps', icon: 'G' },
		{ href: '/settings', label: 'Settings', icon: 'S' }
	];

	function isActive(href: string, pathname: string): boolean {
		if (href === '/') return pathname === '/';
		return pathname.startsWith(href);
	}

	function navClass(href: string, pathname: string): string {
		const base = 'flex items-center gap-3 px-3 py-2 rounded transition-colors';
		if (isActive(href, pathname)) {
			return `${base} bg-primary-500/20 text-primary-400`;
		}
		return `${base} hover:bg-surface-200-700`;
	}
</script>

<aside class="w-64 bg-surface-100-800 border-r border-surface-300-600 flex flex-col h-full">
	<div class="p-4 border-b border-surface-300-600">
		<h1 class="text-xl font-bold">Runner Dashboard</h1>
		<p class="text-sm text-surface-500">Runner Fleet</p>
	</div>

	<div class="p-3 border-b border-surface-300-600">
		<EnvBadge />
	</div>

	<nav class="flex-1 p-2">
		<ul class="space-y-1">
			{#each navItems as item}
				<li>
					<a href={item.href} class={navClass(item.href, $page.url.pathname)}>
						<span
							class="w-7 h-7 flex items-center justify-center rounded bg-surface-200-700 text-xs font-bold"
						>
							{item.icon}
						</span>
						<span>{item.label}</span>
					</a>
				</li>
			{/each}
		</ul>
	</nav>

	<div class="p-4 border-t border-surface-300-600 text-xs text-surface-500">v0.1.0</div>
</aside>
