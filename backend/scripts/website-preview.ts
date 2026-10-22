import "reflect-metadata";
import { createServer } from "node:http";
import { Database } from "../src/common/database";
import { createHandler } from "../edge/handler";
import { seedWebsite } from "./website-fixtures";
async function main() {
  // This process cannot use a persistent or remote database, even through inherited env.
  delete process.env.DATABASE_URL;
  delete process.env.DATABASE_SCHEMA;
  delete process.env.DATABASE_MIGRATE;
  process.env.PGLITE_PATH = "memory://";
  process.env.NODE_ENV = "test";
  process.env.BOOKING_WEBSITE_URL = "http://localhost:3000";
  const db = new Database();
  await db.onModuleInit();
  const { website } = await seedWebsite(db, "eden-sports");
  const handler = createHandler(
    { website } as never,
    async () => {
      throw new Error(
        "Owner authentication is unavailable in the isolated preview",
      );
    },
    () => db.query("SELECT 1"),
  );
  const server = createServer(async (req, res) => {
    try {
      const chunks: Buffer[] = [];
      let size = 0;
      for await (const raw of req) {
        const chunk = Buffer.from(raw);
        size += chunk.length;
        if (size > 16384) {
          res.writeHead(413).end();
          return;
        }
        chunks.push(chunk);
      }
      const response = await handler(
        new Request(`http://127.0.0.1:3101${req.url}`, {
          method: req.method,
          headers: req.headers as Record<string, string>,
          body: chunks.length ? Buffer.concat(chunks) : undefined,
        }),
      );
      res.writeHead(response.status, Object.fromEntries(response.headers));
      res.end(Buffer.from(await response.arrayBuffer()));
    } catch {
      res
        .writeHead(500, { "Content-Type": "application/json" })
        .end(JSON.stringify({ message: "Local preview request failed." }));
    }
  });
  server.listen(3101, "127.0.0.1", () =>
    console.log(
      "Isolated booking API: http://127.0.0.1:3101\nWebsite: http://localhost:3000/eden-sports\nAll records are in memory and disappear when this process stops.",
    ),
  );
  const close = () => {
    server.close();
    void db.onModuleDestroy().finally(() => process.exit(0));
  };
  process.on("SIGTERM", close);
  process.on("SIGINT", close);
}
main().catch((e) => {
  console.error(e instanceof Error ? e.message : "Preview failed");
  process.exit(1);
});
