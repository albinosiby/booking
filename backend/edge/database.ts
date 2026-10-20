import { databaseCertificate } from "./project";
import { Pool } from "npm:pg@8.16.3";
import type { Queryable } from "../src/common/database";

/** Existing private-schema role; no migrations, embedded DB or admin credentials. */
export class EdgeDatabase implements Queryable {
  private pool?: Pool;
  private connection() {
    if (this.pool) return this.pool;
    const connectionString = process.env.BOOKING_DATABASE_URL;
    const ca = process.env.BOOKING_DATABASE_CA ?? databaseCertificate;
    if (!connectionString || !ca)
      throw new Error("Cloud database is not configured");
    const url = new URL(connectionString);
    if (!url.hostname.endsWith(".pooler.supabase.com"))
      throw new Error("Expected Supabase pooler");
    // pg URI sslmode parameters can replace the explicit certificate configuration.
    for (const key of ["sslmode", "sslcert", "sslkey", "sslrootcert"])
      url.searchParams.delete(key);
    this.pool = new Pool({
      connectionString: url.toString(),
      max: 2,
      ssl: { rejectUnauthorized: true, ca },
      options:
        "-c search_path=booking_app,pg_catalog -c statement_timeout=20000 -c lock_timeout=10000",
      connectionTimeoutMillis: 10000,
      idleTimeoutMillis: 10000,
    });
    this.pool.on("error", () =>
      console.error("Idle cloud database connection failed"),
    );
    return this.pool;
  }
  async query<T = Record<string, unknown>>(
    sql: string,
    values: unknown[] = [],
  ): Promise<{ rows: T[] }> {
    return { rows: (await this.connection().query(sql, values)).rows as T[] };
  }
  async transaction<T>(work: (db: Queryable) => Promise<T>): Promise<T> {
    const client = await this.connection().connect();
    try {
      await client.query("BEGIN");
      const result = await work({
        query: async <R = Record<string, unknown>>(
          sql: string,
          values: unknown[] = [],
        ) => ({ rows: (await client.query(sql, values)).rows as R[] }),
      });
      await client.query("COMMIT");
      return result;
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }
  async close() {
    await this.pool?.end();
  }
}
