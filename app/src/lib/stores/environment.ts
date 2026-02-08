import type { Environment } from "$lib/types";
import environmentsConfig from "$lib/config/environments.json";

let currentEnv = $state<Environment>("dev");

export function getEnvironment(): Environment {
  return currentEnv;
}

export function setEnvironment(env: Environment) {
  currentEnv = env;
}

export const environment = {
  get current() {
    return currentEnv;
  },
  set current(env: Environment) {
    currentEnv = env;
  },
  get domain() {
    const config = environmentsConfig.find(e => e.name === currentEnv);
    return config?.domain ?? '';
  },
};
