import { readFileSync, existsSync } from 'fs';
import { env } from '$env/dynamic/private';
import type { EnvironmentConfig, AppConfig } from '$lib/types/environment';
import fallbackConfig from '$lib/config/environments.json';
import fallbackAppConfig from '$lib/config/app-config.json';

let cachedEnvironments: EnvironmentConfig[] | null = null;
let cachedAppConfig: AppConfig | null = null;

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

export function getAppConfig(): AppConfig {
	if (cachedAppConfig) return cachedAppConfig;

	const base = fallbackAppConfig as Omit<AppConfig, 'commits'>;
	cachedAppConfig = {
		...base,
		commits: {
			overlay: env.OVERLAY_COMMIT_SHA || 'dev',
			upstream: env.UPSTREAM_COMMIT_SHA || 'dev'
		}
	};
	return cachedAppConfig;
}
