import { getDb } from "./client";

let migrated = false;

export async function ensureSchema() {
  if (migrated) return;

  const sql = getDb();
  await sql`
    CREATE TABLE IF NOT EXISTS dashboard_webauthn_credentials (
      id              SERIAL PRIMARY KEY,
      user_id         INTEGER NOT NULL,
      username        TEXT NOT NULL,
      credential_id   TEXT NOT NULL UNIQUE,
      public_key      BYTEA NOT NULL,
      counter         BIGINT NOT NULL DEFAULT 0,
      transports      TEXT[] DEFAULT '{}',
      device_type     TEXT DEFAULT 'singleDevice',
      backed_up       BOOLEAN DEFAULT FALSE,
      created_at      TIMESTAMPTZ DEFAULT NOW(),
      last_used_at    TIMESTAMPTZ
    )
  `;
  await sql`
    CREATE INDEX IF NOT EXISTS idx_webauthn_user_id
    ON dashboard_webauthn_credentials(user_id)
  `;

  migrated = true;
}
