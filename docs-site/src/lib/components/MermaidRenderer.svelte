<script lang="ts">
	import { onMount } from 'svelte';
	import { browser } from '$app/environment';

	let rendered = $state(false);

	async function renderDiagrams() {
		if (!browser) return;

		const mermaid = (await import('mermaid')).default;
		mermaid.initialize({
			startOnLoad: false,
			theme: 'dark',
			securityLevel: 'loose'
		});

		const elements = document.querySelectorAll('[data-mermaid-code]');

		for (const el of elements) {
			const encoded = el.getAttribute('data-mermaid-code');
			const id = el.getAttribute('data-mermaid-id') || `mermaid-${Math.random().toString(36).substr(2, 9)}`;

			if (!encoded) continue;

			try {
				const source = atob(encoded);
				const { svg } = await mermaid.render(id, source);
				el.innerHTML = svg;
				el.classList.add('mermaid-rendered');
			} catch (err) {
				console.warn(`Failed to render Mermaid diagram ${id}:`, err);
				el.innerHTML = `<pre class="text-error-500">${err}</pre>`;
			}
		}

		rendered = true;
	}

	onMount(() => {
		renderDiagrams();
	});

	$effect(() => {
		if (browser && !rendered) {
			renderDiagrams();
		}
	});
</script>
