// See https://svelte.dev/docs/kit/types#app.d.ts
declare global {
  namespace App {
    interface Error {
      message: string;
      code?: string;
    }
    interface Locals {
      user?: {
        id: number;
        username: string;
        name: string;
        email: string;
        role: "viewer" | "operator" | "admin";
      };
      auth_method?: "oauth" | "webauthn" | "tailscale" | "mtls";
    }
    interface PageData {}
    interface PageState {}
    interface Platform {}
  }
}

export {};
