import { json, error } from "@sveltejs/kit";
import { env } from "$env/dynamic/private";
import { listGroupRunners, pauseRunner } from "$lib/server/gitlab/runners";
import { MOCK_RUNNER_MAP } from "$lib/mocks";
import type { RequestHandler } from "./$types";

export const POST: RequestHandler = async ({ params }) => {
  if (!env.GITLAB_TOKEN || !env.GITLAB_GROUP_ID) {
    const runner = MOCK_RUNNER_MAP[params.name];
    if (!runner) {
      error(404, `Runner "${params.name}" not found`);
    }
    runner.status = "paused";
    return json({ success: true, status: runner.status });
  }

  const runners = await listGroupRunners(env.GITLAB_GROUP_ID);
  const runner = runners.find((r) => r.description === params.name);
  if (!runner) {
    error(404, `Runner "${params.name}" not found`);
  }

  await pauseRunner(runner.id);
  return json({ success: true, status: "paused" });
};
