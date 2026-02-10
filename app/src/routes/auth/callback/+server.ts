import { redirect, error } from "@sveltejs/kit";
import { exchangeCode, getUserInfo } from "$lib/server/auth/gitlab-oauth";
import { setSession, type Session } from "$lib/server/auth/session";
import type { RequestHandler } from "./$types";

export const GET: RequestHandler = async ({ url, cookies }) => {
  const code = url.searchParams.get("code");
  const state = url.searchParams.get("state");
  const savedState = cookies.get("oauth_state");

  cookies.delete("oauth_state", { path: "/" });

  if (!code || !state || state !== savedState) {
    error(400, "Invalid OAuth callback");
  }

  const tokens = await exchangeCode(code);
  const user = await getUserInfo(tokens.access_token);

  const session: Session = {
    access_token: tokens.access_token,
    refresh_token: tokens.refresh_token,
    expires_at: Date.now() + tokens.expires_in * 1000,
    auth_method: "oauth",
    user: {
      ...user,
      role: "operator", // Default role; refine with group membership check
    },
  };

  setSession(cookies, session);
  redirect(302, "/");
};
