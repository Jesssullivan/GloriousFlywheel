import { json, redirect } from "@sveltejs/kit";
import { getSession, clearSession } from "$lib/server/auth/session";
import { revokeToken } from "$lib/server/auth/gitlab-oauth";
import { env } from "$env/dynamic/private";
import type { RequestHandler } from "./$types";

async function performLogout(
  cookies: Parameters<RequestHandler>[0]["cookies"],
): Promise<void> {
  const session = getSession(cookies);
  if (session?.access_token) {
    await revokeToken(session.access_token);
  }
  clearSession(cookies);
  // Also clear the oauth_state cookie if it exists
  cookies.delete("oauth_state", { path: "/", secure: true, sameSite: "lax" });
}

export const POST: RequestHandler = async ({ cookies, request }) => {
  const body = await request.json().catch(() => ({}));
  const mode = body.mode === "full" ? "full" : "app_only";

  await performLogout(cookies);

  if (mode === "full") {
    const gitlabUrl = env.GITLAB_URL ?? "https://gitlab.com";
    return json({ redirect: `${gitlabUrl}/users/sign_out` });
  }

  return json({ redirect: "/auth/logged-out" });
};

// Backward-compatible GET fallback
export const GET: RequestHandler = async ({ cookies }) => {
  await performLogout(cookies);
  redirect(302, "/auth/logged-out");
};
