import type { LayoutServerLoad } from "./$types";
import { getEnvironments, getAppConfig } from "$lib/server/config";

export const load: LayoutServerLoad = async ({ locals }) => {
  return {
    user: locals.user ?? null,
    environments: getEnvironments(),
    appConfig: getAppConfig(),
  };
};
