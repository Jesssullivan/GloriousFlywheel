/**
 * GitOps configuration helpers
 *
 * Provides functions to construct paths and config values based on the current environment.
 */

import { env } from '$env/dynamic/private';
import type { Environment } from '$lib/types/environment';

/**
 * Get the tfvars file path for a given environment and runner stack.
 *
 * @param environment - Target environment name (e.g., "dev", "prod")
 * @param stack - Stack name (reads from RUNNER_STACK_NAME env var, defaults to "gitlab-runners")
 * @returns Path to the tfvars file relative to repo root
 */
export function getTfvarsPath(
	environment: Environment | string,
	stack: string = env.RUNNER_STACK_NAME ?? 'gitlab-runners'
): string {
	return `tofu/stacks/${stack}/${environment}.tfvars`;
}

/**
 * Get the default environment for GitOps operations.
 * This is typically the first/primary cluster in the organization config.
 *
 * @returns Default environment name
 */
export function getDefaultEnvironment(): string {
	return env.ATTIC_DEFAULT_ENV ?? 'dev';
}
