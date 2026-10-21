import "reflect-metadata";
import { test } from "node:test";
import assert from "node:assert/strict";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { systemAccounts } from "../src/accounts/ledger";
test("workspace has two database round trips regardless of number of fields", async () => {
  const queries: string[] = [];
  const db = {
    query: async (sql: string) => {
      queries.push(sql);
      return {
        rows: sql.includes("WITH visible")
          ? [
              {
                organization: { id: "org", name: "Eden" },
                businesses: [],
                assignments: [],
                locations: [],
                resources: [],
              },
            ]
          : [
              {
                id: "member",
                organization_id: "org",
                active: true,
                role: "owner",
              },
            ],
      };
    },
  };
  const result = await new WorkspaceService(db as never).workspace({
    uid: "owner",
    email: "owner@example.com",
    name: "Owner",
  });
  assert.equal(queries.length, 2);
  assert.equal(result.organization?.id, "org");
  assert.deepEqual(result.businesses, []);
});
test("system account initialization is one conditional statement for both accounts", async () => {
  const queries: string[] = [];
  await systemAccounts(
    {
      query: async (sql) => {
        queries.push(sql);
        return { rows: [] };
      },
    },
    "org",
  );
  assert.equal(queries.length, 1);
  assert.match(queries[0], /WHERE NOT EXISTS/);
  assert.match(queries[0], /ON CONFLICT/);
});
