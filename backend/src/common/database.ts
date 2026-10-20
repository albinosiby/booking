import { Injectable, OnModuleDestroy, OnModuleInit } from "@nestjs/common";
import { PGlite } from "@electric-sql/pglite";
import { Pool } from "pg";
import { readFileSync, mkdirSync, readdirSync } from "node:fs";
import { resolve, dirname } from "node:path";
export interface Queryable {
  query<T = Record<string, unknown>>(
    sql: string,
    values?: unknown[],
  ): Promise<{ rows: T[] }>;
}
@Injectable()
export class Database implements Queryable, OnModuleInit, OnModuleDestroy {
  private embedded?: PGlite;
  private pool?: Pool;
  async onModuleInit() {
    if (process.env.DATABASE_URL)
      this.pool = new Pool({
        connectionString: process.env.DATABASE_URL,
        max: 10,
        ssl:
          process.env.NODE_ENV === "production" ||
          process.env.DATABASE_SSL === "true"
            ? {
                rejectUnauthorized: true,
                ...(process.env.DATABASE_CA_FILE
                  ? { ca: readFileSync(process.env.DATABASE_CA_FILE, "utf8") }
                  : {}),
              }
            : undefined,
        ...(process.env.DATABASE_SCHEMA
          ? { options: `-c search_path=${this.databaseSchema()},pg_catalog` }
          : {}),
        connectionTimeoutMillis: 15000,
        idleTimeoutMillis: 30000,
      });
    else {
      if (process.env.NODE_ENV === "production")
        throw new Error("DATABASE_URL is required in production");
      const path = process.env.PGLITE_PATH || "../.local/postgres";
      if (path !== "memory://")
        mkdirSync(dirname(resolve(path)), { recursive: true });
      this.embedded = new PGlite(path);
      await this.embedded.waitReady;
    }
    if (process.env.DATABASE_MIGRATE === "false") {
      const applied = new Set(
        (
          await this.query<{ name: string }>(
            "SELECT name FROM schema_migrations",
          )
        ).rows.map((row) => row.name),
      );
      if (
        readdirSync(resolve("migrations")).some(
          (name) => name.endsWith(".sql") && !applied.has(name),
        )
      )
        throw new Error(
          "Database migrations must be applied before starting the API.",
        );
      return;
    }
    await this.query(
      "CREATE TABLE IF NOT EXISTS schema_migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())",
    );
    for (const name of readdirSync(resolve("migrations"))
      .filter((n) => n.endsWith(".sql"))
      .sort()) {
      if (
        (
          await this.query("SELECT name FROM schema_migrations WHERE name=$1", [
            name,
          ])
        ).rows.length
      )
        continue;
      const sql = readFileSync(resolve("migrations", name), "utf8");
      if (this.embedded)
        await this.embedded.transaction(async (tx) => {
          await tx.exec(sql);
          await tx.query("INSERT INTO schema_migrations(name) VALUES($1)", [
            name,
          ]);
        });
      else
        await this.transaction(async (db) => {
          await db.query(sql);
          await db.query("INSERT INTO schema_migrations(name) VALUES($1)", [
            name,
          ]);
        });
    }
  }
  private databaseSchema() {
    const value = process.env.DATABASE_SCHEMA!;
    if (!/^[a-z][a-z0-9_]{0,62}$/.test(value))
      throw new Error("Invalid DATABASE_SCHEMA");
    return value;
  }
  async query<T = Record<string, unknown>>(
    sql: string,
    values: unknown[] = [],
  ): Promise<{ rows: T[] }> {
    if (this.embedded) return this.embedded.query<T>(sql, values);
    return { rows: (await this.pool!.query(sql, values)).rows as T[] };
  }
  async transaction<T>(work: (db: Queryable) => Promise<T>): Promise<T> {
    if (this.embedded) return this.embedded.transaction((tx) => work(tx));
    const client = await this.pool!.connect();
    try {
      await client.query("BEGIN");
      const result = await work(client);
      await client.query("COMMIT");
      return result;
    } catch (e) {
      await client.query("ROLLBACK");
      throw e;
    } finally {
      client.release();
    }
  }
  async onModuleDestroy() {
    await this.embedded?.close();
    await this.pool?.end();
  }
}
