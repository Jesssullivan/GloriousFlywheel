<script lang="ts">
	import { environment } from '$lib/stores';
	import type { Environment } from '$lib/types';

	function toggle() {
		environment.current = environment.current === 'dev' ? 'prod' : 'dev';
	}

	const colors: Record<Environment, string> = {
		dev: 'bg-green-500/20 text-green-400 border-green-500/30',
		prod: 'bg-blue-500/20 text-blue-400 border-blue-500/30'
	};
</script>

<button
	onclick={toggle}
	class="w-full flex items-center justify-between px-3 py-2 rounded border text-sm transition-colors {colors[environment.current]}"
>
	<span class="font-medium">{environment.current}</span>
	<span class="text-xs opacity-70">{environment.domain}</span>
</button>
