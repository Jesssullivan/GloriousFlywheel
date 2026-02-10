import { json, error } from "@sveltejs/kit";
import { getSession } from "$lib/server/auth/session";
import { startRegistration, finishRegistration } from "$lib/server/auth/webauthn";
import type { RequestHandler } from "./$types";

// GET: generate registration options (requires OAuth session)
export const GET: RequestHandler = async ({ cookies }) => {
  const session = getSession(cookies);
  if (!session?.user || session.auth_method !== "oauth") {
    error(403, "OAuth session required to register passkeys");
  }

  const options = await startRegistration(session.user.id, session.user.username);
  return json(options);
};

// POST: verify registration response
export const POST: RequestHandler = async ({ cookies, request }) => {
  const session = getSession(cookies);
  if (!session?.user || session.auth_method !== "oauth") {
    error(403, "OAuth session required to register passkeys");
  }

  const body = await request.json();
  const verification = await finishRegistration(
    session.user.id,
    session.user.username,
    body,
  );

  return json({ verified: verification.verified });
};
