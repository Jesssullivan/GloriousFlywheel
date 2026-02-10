import { json, error } from "@sveltejs/kit";
import { setSession, type Session } from "$lib/server/auth/session";
import {
  startAuthentication,
  finishAuthentication,
} from "$lib/server/auth/webauthn";
import type { RequestHandler } from "./$types";

// GET: generate authentication options (public — no session required)
export const GET: RequestHandler = async () => {
  const options = await startAuthentication();
  return json(options);
};

// POST: verify authentication response, create session
export const POST: RequestHandler = async ({ cookies, request }) => {
  const body = await request.json();

  let result;
  try {
    result = await finishAuthentication(body);
  } catch (e) {
    error(400, e instanceof Error ? e.message : "Authentication failed");
  }

  if (!result.verified) {
    error(401, "Authentication failed");
  }

  const session: Session = {
    auth_method: "webauthn",
    user: {
      id: result.userId,
      username: result.username,
      name: result.username,
      email: `${result.username}@passkey`,
      role: "viewer",
    },
  };

  setSession(cookies, session);
  return json({ verified: true, redirect: "/" });
};
