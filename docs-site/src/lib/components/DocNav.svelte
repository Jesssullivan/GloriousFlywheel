<script lang="ts">
	import { page } from '$app/stores';
	import { base } from '$app/paths';
	import DocNav from './DocNav.svelte';

	interface NavItem {
		title: string;
		slug: string;
		children?: NavItem[];
	}

	interface Props {
		items: NavItem[];
		depth?: number;
	}

	let { items, depth = 0 }: Props = $props();

	function isActive(slug: string): boolean {
		const currentPath = $page.url.pathname;
		const itemPath = `${base}/docs/${slug}`;
		return currentPath === itemPath || currentPath.startsWith(itemPath + '/');
	}

	function formatTitle(title: string): string {
		return title
			.replace(/-/g, ' ')
			.replace(/\b\w/g, (c) => c.toUpperCase());
	}
</script>

<ul class="space-y-1 {depth > 0 ? 'ml-4 border-l border-surface-300 pl-3' : ''}">
	{#each items as item}
		<li>
			{#if item.children && item.children.length > 0}
				<details open={isActive(item.slug)}>
					<summary class="cursor-pointer py-1 text-sm font-medium text-surface-600 hover:text-surface-900 dark:text-surface-400 dark:hover:text-surface-100">
						{formatTitle(item.title)}
					</summary>
					<DocNav items={item.children} depth={depth + 1} />
				</details>
			{:else}
				<a
					href="{base}/docs/{item.slug}"
					class="block py-1 text-sm {isActive(item.slug)
						? 'font-medium text-primary-500'
						: 'text-surface-600 hover:text-surface-900 dark:text-surface-400 dark:hover:text-surface-100'}"
				>
					{formatTitle(item.title)}
				</a>
			{/if}
		</li>
	{/each}
</ul>
