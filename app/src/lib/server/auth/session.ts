import type { Cookies } from "@sveltejs/kit";

const SESSION_COOKIE = "dashboard_session";
const SESSION_MAX_AGE = 60 * 60 * 8; // 8 hours

export type AuthMethod = "oauth" | "webauthn" | "tailscale" | "mtls";

export interface Session {
  access_token?: string;
  refresh_token?: string;
  expires_at?: number;
  auth_method: AuthMethod;
  user: {
    id: number;
    username: string;
    name: string;
    email: string;
    role: "viewer" | "operator" | "admin";
  };
}

export function getSession(cookies: Cookies): Session | null {
  const raw = cookies.get(SESSION_COOKIE);
  if (!raw) return null;

  try {
    const decoded = Buffer.from(raw, "base64").toString("utf-8");
    const session = JSON.parse(decoded) as Session;
    // Backfill auth_method for sessions created before this field existed
    if (!session.auth_method) {
      session.auth_method = "oauth";
    }
    return session;
  } catch {
    return null;
  }
}

export function setSession(cookies: Cookies, session: Session) {
  const encoded = Buffer.from(JSON.stringify(session)).toString("base64");
  cookies.set(SESSION_COOKIE, encoded, {
    path: "/",
    httpOnly: true,
    secure: true,
    sameSite: "lax",
    maxAge: SESSION_MAX_AGE,
  });
}

export function clearSession(cookies: Cookies) {
  cookies.delete(SESSION_COOKIE, {
    path: "/",
    secure: true,
    sameSite: "lax",
  });
}
