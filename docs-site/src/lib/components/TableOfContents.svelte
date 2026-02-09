<script lang="ts">
	import { onMount } from 'svelte';
	import { browser } from '$app/environment';

	interface TocEntry {
		id: string;
		text: string;
		level: number;
	}

	let headings = $state<TocEntry[]>([]);
	let activeId = $state('');

	onMount(() => {
		const elements = document.querySelectorAll('article h2, article h3');
		headings = Array.from(elements).map((el) => ({
			id: el.id,
			text: el.textContent || '',
			level: parseInt(el.tagName[1])
		}));

		const observer = new IntersectionObserver(
			(entries) => {
				for (const entry of entries) {
					if (entry.isIntersecting) {
						activeId = entry.target.id;
					}
				}
			},
			{ rootMargin: '-80px 0px -80% 0px' }
		);

		elements.forEach((el) => observer.observe(el));

		return () => observer.disconnect();
	});
</script>

{#if headings.length > 0}
	<nav class="hidden xl:block sticky top-8 w-56 shrink-0 max-h-[calc(100vh-4rem)] overflow-y-auto">
		<h4 class="text-xs font-semibold uppercase text-surface-500 mb-3">On this page</h4>
		<ul class="space-y-1 text-sm border-l border-surface-700 pl-3">
			{#each headings as heading}
				<li class="{heading.level === 3 ? 'ml-3' : ''}">
					<a
						href="#{heading.id}"
						class="block py-0.5 transition-colors {activeId === heading.id
							? 'text-primary-500 font-medium'
							: 'text-surface-500 hover:text-surface-300'}"
					>
						{heading.text}
					</a>
				</li>
			{/each}
		</ul>
	</nav>
{/if}
