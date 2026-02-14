<script lang="ts">
	import { page } from '$app/stores';
	import EnvBadge from './EnvBadge.svelte';
	import type { AppConfig } from '$lib/types/environment';

	let { appConfig }: { appConfig?: AppConfig } = $props();

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

	{#if appConfig?.links}
		<div class="p-2 border-t border-surface-300-600 space-y-1">
			{#if appConfig.links.pages_url}
				<a
					href={appConfig.links.pages_url}
					target="_blank"
					rel="noopener noreferrer"
					class="flex items-center gap-2 px-2 py-1 text-xs text-surface-500 hover:text-primary-400 transition-colors"
				>
					<span class="w-5 h-5 flex items-center justify-center rounded bg-surface-200-700 text-[10px] font-bold">D</span>
					<span>Docs</span>
				</a>
			{/if}
			{#if appConfig.links.source_repo}
				<a
					href={appConfig.links.source_repo}
					target="_blank"
					rel="noopener noreferrer"
					class="flex items-center gap-2 px-2 py-1 text-xs text-surface-500 hover:text-primary-400 transition-colors"
				>
					<span class="w-5 h-5 flex items-center justify-center rounded bg-surface-200-700 text-[10px] font-bold">S</span>
					<span>Source</span>
				</a>
			{/if}
			{#if appConfig.links.upstream_repo}
				<a
					href={appConfig.links.upstream_repo}
					target="_blank"
					rel="noopener noreferrer"
					class="flex items-center gap-2 px-2 py-1 text-xs text-surface-500 hover:text-primary-400 transition-colors"
				>
					<span class="w-5 h-5 flex items-center justify-center rounded bg-surface-200-700 text-[10px] font-bold">U</span>
					<span>Upstream</span>
				</a>
			{/if}
		</div>
	{/if}

	<div class="p-4 border-t border-surface-300-600 text-xs text-surface-500 space-y-1">
		<div>v{appConfig?.version ?? '0.1.0'}</div>
		{#if appConfig?.commits}
			<div class="flex gap-2">
				<span class="text-surface-400">overlay</span>
				{#if appConfig.links?.source_repo && appConfig.commits.overlay !== 'dev'}
					<a
						href="{appConfig.links.source_repo}/-/commit/{appConfig.commits.overlay}"
						target="_blank"
						rel="noopener noreferrer"
						class="font-mono hover:text-primary-400 transition-colors"
					>{appConfig.commits.overlay.slice(0, 7)}</a>
				{:else}
					<span class="font-mono">{appConfig.commits.overlay.slice(0, 7)}</span>
				{/if}
			</div>
			<div class="flex gap-2">
				<span class="text-surface-400">upstream</span>
				{#if appConfig.links?.upstream_repo && appConfig.commits.upstream !== 'dev'}
					<a
						href="{appConfig.links.upstream_repo}/commit/{appConfig.commits.upstream}"
						target="_blank"
						rel="noopener noreferrer"
						class="font-mono hover:text-primary-400 transition-colors"
					>{appConfig.commits.upstream.slice(0, 7)}</a>
				{:else}
					<span class="font-mono">{appConfig.commits.upstream.slice(0, 7)}</span>
				{/if}
			</div>
		{/if}
		<div class="pt-1 text-surface-500">
			GloriousFlywheel
		</div>
	</div>
</aside>
