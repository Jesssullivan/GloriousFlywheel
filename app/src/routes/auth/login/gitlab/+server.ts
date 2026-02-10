import { redirect } from "@sveltejs/kit";
import { getAuthorizeUrl } from "$lib/server/auth/gitlab-oauth";
import type { RequestHandler } from "./$types";

export const GET: RequestHandler = async ({ cookies }) => {
  const state = crypto.randomUUID();
  cookies.set("oauth_state", state, {
    path: "/",
    httpOnly: true,
    secure: true,
    sameSite: "lax",
    maxAge: 600,
  });
  redirect(302, getAuthorizeUrl(state));
};
