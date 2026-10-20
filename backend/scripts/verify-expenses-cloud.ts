// Read-only verification against the existing restricted API database role.
import "reflect-metadata";
import process from "node:process";
import { Database } from "../src/common/database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { AccountsService } from "../src/accounts/accounts.service";
import { ExpensesService } from "../src/expenses/expenses.service";
import { renderExpenseReport } from "../src/expenses/expenses.report";
async function main() {
  process.loadEnvFile(".env");
  process.env.DATABASE_MIGRATE = "false";
  process.env.DATABASE_SCHEMA = "booking_app";
  process.env.DATABASE_SSL = "true";
  process.env.DATABASE_CA_FILE = "../.local/supabase-ca.crt";
  const db = new Database();
  try {
    await db.onModuleInit();
    const workspace = new WorkspaceService(db),
      accounts = new AccountsService(db, workspace),
      s = new ExpensesService(db, workspace, accounts);
    const a = (
      await db.query<any>(
        "SELECT user_id,email,display_name FROM memberships WHERE role='owner' AND active=true LIMIT 1",
      )
    ).rows[0];
    if (!a) throw new Error("Existing owner not found");
    const actor = { uid: a.user_id, email: a.email, name: a.display_name };
    const year = new Date().getUTCFullYear(),
      f = { from: `${year}-01-01`, until: `${year}-12-31` };
    const categories = await db.query<any>(
      "SELECT id,name FROM expense_categories WHERE organization_id=(SELECT organization_id FROM memberships WHERE user_id=$1)",
      [actor.uid],
    );
    const overview = await s.overview(actor, f),
      list = await s.list(actor, f),
      report = await s.report(actor, f);
    if (Number(overview.total_minor) !== report.total_minor)
      throw new Error("Summary/report total mismatch");
    const pdf = await renderExpenseReport(report, "pdf"),
      xlsx = await renderExpenseReport(report, "xlsx");
    if (
      pdf.subarray(0, 5).toString() !== "%PDF-" ||
      xlsx.subarray(0, 2).toString() !== "PK"
    )
      throw new Error("Report format mismatch");
    const grants = (
      await db.query<any>(
        "SELECT count(*)::int AS count FROM information_schema.role_table_grants WHERE table_schema='booking_app' AND table_name IN ('expense_categories','expense_attachments') AND grantee IN ('anon','authenticated')",
      )
    ).rows[0].count;
    if (grants !== 0) throw new Error("Unexpected client table grants");
    console.log(
      JSON.stringify({
        verified: true,
        categories: categories.rows.length,
        visible_expense_movements: list.items.length,
        summary_matches_export: true,
        pdf_bytes: pdf.length,
        excel_bytes: xlsx.length,
        direct_client_table_grants: grants,
      }),
    );
  } catch (e: any) {
    console.error(
      "Cloud expenses verification failed:",
      e.code ?? e.name,
      e.message?.replace(/postgres(?:ql)?:\/\/\S+/g, "[redacted]"),
    );
    process.exitCode = 1;
  } finally {
    await db.onModuleDestroy();
  }
}
void main();
