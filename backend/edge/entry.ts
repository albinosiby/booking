import { MessagesService } from "../src/messages/messages.service";
import { projectUrl, publishableKey } from "./project";
import process from "node:process";
import { Buffer } from "node:buffer";
import { EdgeDatabase } from "./database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { BookingService } from "../src/bookings/booking.service";
import { ExpensesService } from "../src/expenses/expenses.service";
import { AccountsService } from "../src/accounts/accounts.service";
import { TurfService } from "../src/turf/turf.service";
import { CourtService } from "../src/court/court.service";
import { PoolService } from "../src/pool/pool.service";
import { HallService } from "../src/hall/hall.service";
import { supabaseActor } from "../src/common/supabase-auth";
import { createHandler } from "./handler";
// The runtime provides Node compatibility; application secrets are server-only.
Object.assign(globalThis, { Buffer, process });
export const db = new EdgeDatabase();
const workspace = new WorkspaceService(db as never);
workspace.publicAppUrl = `${projectUrl}/functions/v1/booking-api`;
const accounts = new AccountsService(db as never, workspace);
export const services = {
  messages: new MessagesService(db as never, workspace),
  expenses: new ExpensesService(db as never, workspace, accounts),
  workspace,
  bookings: new BookingService(db as never, workspace),
  accounts,
  turf: new TurfService(db as never, workspace),
  court: new CourtService(db as never, workspace),
  pool: new PoolService(db as never, workspace),
  hall: new HallService(db as never, workspace),
};
export { createHandler };
export const handler = createHandler(
  services,
  (token) =>
    supabaseActor(token, db, fetch, { url: projectUrl, key: publishableKey }),
  () => db.query("SELECT 1"),
);
if (Deno.env.get("BOOKING_EDGE_TEST") !== "true") Deno.serve(handler);
