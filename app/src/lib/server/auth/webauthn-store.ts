import { getDb } from "$lib/server/db/client";
import { ensureSchema } from "$lib/server/db/migrate";

export interface StoredCredential {
  id: number;
  user_id: number;
  username: string;
  credential_id: string;
  public_key: Buffer;
  counter: number;
  transports: string[];
  device_type: string;
  backed_up: boolean;
  created_at: Date;
  last_used_at: Date | null;
}

export async function getCredentialsByUserId(
  userId: number,
): Promise<StoredCredential[]> {
  await ensureSchema();
  const sql = getDb();
  const rows = await sql`
    SELECT * FROM dashboard_webauthn_credentials
    WHERE user_id = ${userId}
    ORDER BY created_at DESC
  `;
  return rows as unknown as StoredCredential[];
}

export async function getCredentialByCredentialId(
  credentialId: string,
): Promise<StoredCredential | null> {
  await ensureSchema();
  const sql = getDb();
  const rows = await sql`
    SELECT * FROM dashboard_webauthn_credentials
    WHERE credential_id = ${credentialId}
    LIMIT 1
  `;
  return (rows[0] as unknown as StoredCredential) ?? null;
}

export async function saveCredential(cred: {
  user_id: number;
  username: string;
  credential_id: string;
  public_key: Buffer;
  counter: number;
  transports: string[];
  device_type: string;
  backed_up: boolean;
}): Promise<void> {
  await ensureSchema();
  const sql = getDb();
  await sql`
    INSERT INTO dashboard_webauthn_credentials
      (user_id, username, credential_id, public_key, counter, transports, device_type, backed_up)
    VALUES
      (${cred.user_id}, ${cred.username}, ${cred.credential_id}, ${cred.public_key},
       ${cred.counter}, ${cred.transports}, ${cred.device_type}, ${cred.backed_up})
  `;
}

export async function updateCounter(
  credentialId: string,
  counter: number,
): Promise<void> {
  await ensureSchema();
  const sql = getDb();
  await sql`
    UPDATE dashboard_webauthn_credentials
    SET counter = ${counter}, last_used_at = NOW()
    WHERE credential_id = ${credentialId}
  `;
}

export async function deleteCredential(
  credentialId: string,
  userId: number,
): Promise<void> {
  await ensureSchema();
  const sql = getDb();
  await sql`
    DELETE FROM dashboard_webauthn_credentials
    WHERE credential_id = ${credentialId} AND user_id = ${userId}
  `;
}
