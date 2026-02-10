import { json, error } from "@sveltejs/kit";
import { getSession } from "$lib/server/auth/session";
import {
  getCredentialsByUserId,
  deleteCredential,
} from "$lib/server/auth/webauthn-store";
import type { RequestHandler } from "./$types";

// GET: list user's passkeys
export const GET: RequestHandler = async ({ cookies }) => {
  const session = getSession(cookies);
  if (!session?.user) {
    error(401, "Authentication required");
  }

  const credentials = await getCredentialsByUserId(session.user.id);
  return json(
    credentials.map((c) => ({
      credential_id: c.credential_id,
      device_type: c.device_type,
      backed_up: c.backed_up,
      created_at: c.created_at,
      last_used_at: c.last_used_at,
    })),
  );
};

// DELETE: remove a passkey
export const DELETE: RequestHandler = async ({ cookies, request }) => {
  const session = getSession(cookies);
  if (!session?.user) {
    error(401, "Authentication required");
  }

  const { credential_id } = await request.json();
  if (!credential_id) {
    error(400, "credential_id required");
  }

  await deleteCredential(credential_id, session.user.id);
  return json({ deleted: true });
};
