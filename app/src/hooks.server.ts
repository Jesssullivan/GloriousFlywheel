import type { Handle } from "@sveltejs/kit";
import { redirect } from "@sveltejs/kit";
import { env } from "$env/dynamic/private";
import { getSession } from "$lib/server/auth/session";

const PUBLIC_PATHS = [
  "/api/health",
  "/auth/login",
  "/auth/callback",
  "/auth/logout",
  "/auth/logged-out",
  "/auth/webauthn/authenticate",
];

export const handle: Handle = async ({ event, resolve }) => {
  // Always allow public paths
  if (PUBLIC_PATHS.some((p) => event.url.pathname.startsWith(p))) {
    return resolve(event);
  }

  // Check session cookie first
  const session = getSession(event.cookies);
  if (session) {
    event.locals.user = session.user;
    event.locals.auth_method = session.auth_method;
  }

  // Proxy header auth (Tailscale/mTLS via Caddy sidecar)
  if (!session && env.TRUST_PROXY_HEADERS === "true") {
    const proxyUser = event.request.headers.get("x-webauth-user");
    const proxyEmail = event.request.headers.get("x-webauth-email");
    const certCN = event.request.headers.get("x-client-cert-cn");

    if (proxyUser || certCN) {
      const username = proxyUser ?? certCN ?? "proxy-user";
      event.locals.user = {
        id: 0,
        username,
        name: username,
        email: proxyEmail ?? `${username}@proxy`,
        role: "viewer",
      };
      event.locals.auth_method = certCN ? "mtls" : "tailscale";
    }
  }

  // In development mode, skip auth requirement
  if (import.meta.env.DEV) {
    if (!event.locals.user) {
      event.locals.user = {
        id: 0,
        username: "dev",
        name: "Developer",
        email: "dev@localhost",
        role: "operator",
      };
      event.locals.auth_method = "oauth";
    }
    return resolve(event);
  }

  // Require auth for non-public paths in production
  if (!event.locals.user && !event.url.pathname.startsWith("/api/")) {
    redirect(302, "/auth/login");
  }

  const response = await resolve(event);

  // Cache control for auth-dependent responses
  if (session) {
    response.headers.set(
      "Cache-Control",
      "no-store, no-cache, must-revalidate, private",
    );
    response.headers.set("Pragma", "no-cache");
  }

  // Security headers
  response.headers.set("X-Frame-Options", "DENY");
  response.headers.set("X-Content-Type-Options", "nosniff");
  response.headers.set("Referrer-Policy", "strict-origin-when-cross-origin");
  response.headers.set(
    "Permissions-Policy",
    "camera=(), microphone=(), geolocation=()",
  );
  response.headers.set(
    "Content-Security-Policy",
    [
      "default-src 'self'",
      "script-src 'self' 'unsafe-inline'",
      "style-src 'self' 'unsafe-inline'",
      "img-src 'self' data:",
      "font-src 'self'",
      "connect-src 'self' https://gitlab.com",
      "frame-ancestors 'none'",
    ].join("; "),
  );

  return response;
};
