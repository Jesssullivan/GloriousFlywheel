import { readFileSync, existsSync } from 'fs';
import { env } from '$env/dynamic/private';
import type { EnvironmentConfig } from '$lib/types/environment';
import fallbackConfig from '$lib/config/environments.json';

let cachedEnvironments: EnvironmentConfig[] | null = null;

export function getEnvironments(): EnvironmentConfig[] {
	if (cachedEnvironments) return cachedEnvironments;

	const configPath = env.ENVIRONMENTS_CONFIG_PATH || '';
	if (configPath && existsSync(configPath)) {
		const raw = readFileSync(configPath, 'utf-8');
		cachedEnvironments = JSON.parse(raw);
	} else {
		cachedEnvironments = fallbackConfig as EnvironmentConfig[];
	}
	return cachedEnvironments!;
}
