import "reflect-metadata";
import { before, after, test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import ExcelJS from "exceljs";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { AccountsService } from "../src/accounts/accounts.service";
import { ExpensesService } from "../src/expenses/expenses.service";
import { validInvoice, InvoiceStorage } from "../src/expenses/invoice-storage";
import { renderExpenseReport } from "../src/expenses/expenses.report";
import { Actor } from "../src/common/auth.guard";
delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";
process.env.PGLITE_PATH = "memory://";
const db = new Database(),
  workspace = new WorkspaceService(db),
  accounts = new AccountsService(db, workspace),
  expenses = new ExpensesService(db, workspace, accounts);
const owner: Actor = {
    uid: randomUUID(),
    email: "expense-owner@example.com",
    name: "Owner",
  },
  other: Actor = {
    uid: randomUUID(),
    email: "other-expense@example.com",
    name: "Other",
  };
let category: string, food: string, cash: string, expenseId: string;
const now = new Date().toISOString(),
  today = now.slice(0, 10),
  filter = { from: today, until: today };
const files = new Set<string>();
let uploadCount = 0;
const storage: InvoiceStorage = {
  async upload(path) {
    uploadCount++;
    return `https://example.test/${path}`;
  },
  async verify(path) {
    if (!files.has(path)) throw new Error("Not uploaded");
  },
  async download(path) {
    return `https://example.test/read/${path}`;
  },
  async remove(paths) {
    paths.forEach((p) => files.delete(p));
  },
};
before(async () => {
  await db.onModuleInit();
  for (const actor of [owner, other])
    await workspace.createOrganization(actor, {
      name: "Expense QA",
      contact_phone: "9876543210",
      currency: "INR",
      location: {
        name: "Site",
        address_line_1: "Road",
        address_line_2: null,
        city: "Kochi",
        state_code: "KL",
        country_code: "IN",
        postal_code: "682001",
        timezone: "UTC",
      },
    });
  const c = await expenses.catalog(owner);
  category = (c.categories as any[]).find((c) => c.name === "Maintenance").id;
  food = (c.categories as any[]).find((c) => c.name === "Food").id;
  const a = await accounts.catalog(owner);
  cash = (a.accounts as any[]).find((a) => a.kind === "cash").id;
  expenses.storage = storage;
});
after(() => db.onModuleDestroy());
const input = (cat = category) => ({
  command_key: randomUUID(),
  kind: "expense",
  expense_category_id: cat,
  category: "Old name ignored",
  reason: "Ground repairs",
  reference: "INV-001",
  occurred_at: now,
  business_id: null,
  resource_id: null,
  lines: [
    { account_id: cash, method: "cash", amount_minor: 15000 },
    { account_id: cash, method: "cash", amount_minor: 5000 },
  ],
});
test("structured expense is idempotent, scoped and excludes other categories", async () => {
  const v = input();
  expenseId = (await expenses.create(owner, v)).id;
  assert.equal((await expenses.create(owner, v)).id, expenseId);
  await expenses.create(owner, input(food));
  const s = await expenses.overview(owner, {
    ...filter,
    category_id: category,
  });
  assert.equal(Number(s.total_minor), 20000);
  assert.equal(s.count, 1);
  assert.equal(
    (await expenses.list(owner, { ...filter, category_id: category })).items[0]
      .lines.length,
    2,
  );
  await assert.rejects(() => expenses.detail(other, expenseId));
  await assert.rejects(() => expenses.create(other, input(category)));
});
test("category rename preserves old expenses; archive prevents new entries", async () => {
  await expenses.category(
    owner,
    { name: "Ground upkeep", active: true },
    category,
  );
  assert.equal(
    (await expenses.list(owner, { ...filter, category_id: category })).items[0]
      .category_name,
    "Ground upkeep",
  );
  await expenses.category(
    owner,
    { name: "Ground upkeep", active: false },
    category,
  );
  await assert.rejects(() => expenses.create(owner, input()));
  await expenses.category(
    owner,
    { name: "Ground upkeep", active: true },
    category,
  );
});
test("invoice retry, lost completion and limits never duplicate expenses", async () => {
  const v = {
    id: randomUUID(),
    name: "bill.pdf",
    content_type: "application/pdf",
    size_bytes: 100,
  };
  assert.equal((await expenses.prepare(owner, expenseId, v)).ready, false);
  await assert.rejects(() => expenses.complete(owner, expenseId, v.id));
  const row = (
    await db.query<any>(
      "SELECT object_path FROM expense_attachments WHERE id=$1",
      [v.id],
    )
  ).rows[0];
  files.add(row.object_path);
  assert.equal((await expenses.prepare(owner, expenseId, v)).ready, true);
  assert.equal(uploadCount, 1);
  assert.equal(
    (await expenses.detail(owner, expenseId)).attachments[0].status,
    "ready",
  );
  await assert.rejects(() => expenses.attachment(other, expenseId, v.id));
  await assert.rejects(() =>
    expenses.prepare(owner, expenseId, {
      ...v,
      size_bytes: 15 * 1024 * 1024 + 1,
    }),
  );
  await assert.rejects(() =>
    expenses.prepare(owner, expenseId, { ...v, content_type: "text/html" }),
  );
  for (let i = 0; i < 9; i++)
    await expenses.prepare(owner, expenseId, { ...v, id: randomUUID() });
  await assert.rejects(() =>
    expenses.prepare(owner, expenseId, { ...v, id: randomUUID() }),
  );
  assert.equal(
    (await expenses.list(owner, { ...filter, category_id: category })).items
      .length,
    1,
  );
});
test("exports contain filtered rows, split sources and reversal traceability", async () => {
  await accounts.reverse(owner, expenseId, {
    command_key: randomUUID(),
    reason: "Duplicate bill corrected",
  });
  const d = await expenses.report(owner, { ...filter, category_id: category });
  assert.equal(d.items.length, 2);
  assert.equal(d.total_minor, 0);
  assert.equal(d.categories.length, 1);
  const xlsx = await renderExpenseReport(d, "xlsx"),
    wb = new ExcelJS.Workbook();
  await wb.xlsx.load(xlsx as any);
  assert.equal(wb.getWorksheet("Expenses")!.rowCount, 3);
  assert.equal(wb.getWorksheet("Payment breakdown")!.rowCount, 5);
  const pdf = await renderExpenseReport(d, "pdf");
  assert.equal(pdf.subarray(0, 5).toString(), "%PDF-");
  assert.ok(pdf.length > 1000);
});
test("file signature validation rejects disguised uploads", () => {
  assert.equal(
    validInvoice(new TextEncoder().encode("%PDF-1.7\n"), "application/pdf"),
    true,
  );
  assert.equal(
    validInvoice(new TextEncoder().encode("<html>bad</html>"), "image/png"),
    false,
  );
  assert.equal(
    validInvoice(new Uint8Array([255, 216, 255]), "image/jpeg"),
    true,
  );
  assert.equal(
    validInvoice(
      new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]),
      "image/png",
    ),
    true,
  );
});
