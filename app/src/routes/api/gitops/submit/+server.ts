import { json, error } from "@sveltejs/kit";
import { submitChanges } from "$lib/server/gitops/pipeline";
import type { RequestHandler } from "./$types";

export const POST: RequestHandler = async ({ request }) => {
  const body = await request.json();
  const { changes, description, environment } = body;

  if (!changes || !description) {
    error(400, "Missing changes or description");
  }

  try {
    const result = await submitChanges({ changes, description }, environment);
    return json(result);
  } catch (e) {
    error(
      500,
      `GitOps submit failed: ${e instanceof Error ? e.message : String(e)}`,
    );
  }
};
