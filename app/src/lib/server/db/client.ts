import postgres from "postgres";
import { env } from "$env/dynamic/private";

let sql: ReturnType<typeof postgres> | null = null;

export function getDb() {
  if (!sql) {
    const url = env.DATABASE_URL;
    if (!url) {
      throw new Error("DATABASE_URL is not set");
    }
    sql = postgres(url, {
      max: 5,
      idle_timeout: 20,
      connect_timeout: 10,
    });
  }
  return sql;
}
