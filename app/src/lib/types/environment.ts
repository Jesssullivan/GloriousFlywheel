// Environment configuration interface
export interface EnvironmentConfig {
	name: string;
	label: string;
	domain: string;
	namespace: string;
	gitlab_url: string;
	gitlab_project_id: string;
	role: string;
	context: string;
}

// Build lookup records from environment config array
export function buildEnvironmentLookups(configs: EnvironmentConfig[]) {
	const names = configs.map((env) => env.name);
	const labels: Record<string, string> = Object.fromEntries(
		configs.map((env) => [env.name, env.label])
	);
	const domains: Record<string, string> = Object.fromEntries(
		configs.map((env) => [env.name, env.domain])
	);
	const byName: Record<string, EnvironmentConfig> = Object.fromEntries(
		configs.map((env) => [env.name, env])
	);
	return { names, labels, domains, byName };
}

export type Environment = string;
