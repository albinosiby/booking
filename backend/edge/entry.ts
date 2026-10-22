import { SupportService } from "../src/support/support.service";
import { AgentCallService } from "../src/agent-calls/agent-calls.service";
import { AdminService } from "../src/admin/admin.service";
import { WebsiteService } from "../src/website/website.service";
import { SlotBlocksService } from "../src/slot-blocks/slot-blocks.service";
import { AdmissionService } from "../src/admissions/admission.service";
import { MessagesService } from "../src/messages/messages.service";
import { SarvamService } from "../src/sarvam/sarvam.service";
import { VoiceService } from "../src/sarvam/voice.service";
import { projectUrl, publishableKey } from "./project";
import process from "node:process";
import { Buffer } from "node:buffer";
import { EdgeDatabase } from "./database";
import { WorkspaceService } from "../src/workspace/workspace.service";
import { BookingService } from "../src/bookings/booking.service";
import { ExpensesService } from "../src/expenses/expenses.service";
import { IncomeService } from "../src/income/income.service";
import { AccountsService } from "../src/accounts/accounts.service";
import { TurfService } from "../src/turf/turf.service";
import { CourtService } from "../src/court/court.service";
import { PoolService } from "../src/pool/pool.service";
import { HallService } from "../src/hall/hall.service";
import {
  supabaseActor,
  coalesceActorChecks,
} from "../src/common/supabase-auth";
import { createHandler } from "./handler";
// The runtime provides Node compatibility; application secrets are server-only.
Object.assign(globalThis, { Buffer, process });
export const db = new EdgeDatabase();
const workspace = new WorkspaceService(db as never);
workspace.publicAppUrl = `${projectUrl}/functions/v1/booking-api`;
const accounts = new AccountsService(db as never, workspace);
const bookings = new BookingService(db as never, workspace);
const sarvam = new SarvamService(db as never, workspace);
export const services = {
  website: new WebsiteService(db as never, workspace),
  blocks: new SlotBlocksService(db as never),
  admissions: new AdmissionService(db as never),
  messages: new MessagesService(db as never, workspace),
  expenses: new ExpensesService(db as never, workspace, accounts),
  income: new IncomeService(db as never, workspace, accounts),
  workspace,
  bookings,
  sarvam,
  admin: new AdminService(db as never, sarvam),
  support: new SupportService(db as never, workspace),
  agentCalls: new AgentCallService(db as never, workspace, sarvam),
  voice: new VoiceService(db as never, bookings),
  accounts,
  turf: new TurfService(db as never, workspace),
  court: new CourtService(db as never, workspace),
  pool: new PoolService(db as never, workspace),
  hall: new HallService(db as never, workspace),
};
export { createHandler };
export const handler = createHandler(
  services,
  coalesceActorChecks((token) =>
    supabaseActor(token, db, fetch, { url: projectUrl, key: publishableKey }),
  ),
  () => db.query("SELECT 1"),
);
if (Deno.env.get("BOOKING_EDGE_TEST") !== "true") Deno.serve(handler);
