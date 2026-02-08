import type { EnvironmentConfig } from "$lib/types";
import { buildEnvironmentLookups } from "$lib/types/environment";

let configs = $state<EnvironmentConfig[]>([]);
let currentEnv = $state<string>("dev");

export function initEnvironments(envConfigs: EnvironmentConfig[]) {
	configs = envConfigs;
	if (envConfigs.length > 0 && !envConfigs.some((e) => e.name === currentEnv)) {
		currentEnv = envConfigs[0].name;
	}
}

export function getEnvironment(): string {
	return currentEnv;
}

export function setEnvironment(env: string) {
	currentEnv = env;
}

export const environment = {
	get current() {
		return currentEnv;
	},
	set current(env: string) {
		currentEnv = env;
	},
	get domain() {
		const config = configs.find((e) => e.name === currentEnv);
		return config?.domain ?? "";
	},
	get configs() {
		return configs;
	},
	get lookups() {
		return buildEnvironmentLookups(configs);
	},
};
