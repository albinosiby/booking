import type { NotificationService } from "../src/notifications/notification.service";
import type { SupportService } from "../src/support/support.service";
import type { AgentCallService } from "../src/agent-calls/agent-calls.service";
import type { AdminService } from "../src/admin/admin.service";
import type { AdminSarvamService } from "../src/admin/admin-sarvam.service";
import { panelActor } from "../src/admin/panel-auth";
import type { WebsiteService } from "../src/website/website.service";
import type { SlotBlocksService } from "../src/slot-blocks/slot-blocks.service";
import { AdmissionService } from "../src/admissions/admission.service";
import type { MessagesService } from "../src/messages/messages.service";
import type { SarvamService } from "../src/sarvam/sarvam.service";
import type { VoiceService } from "../src/sarvam/voice.service";
import { voiceResult } from "../src/sarvam/voice-result";
import { z, ZodError } from "zod";
import {
  HttpException,
  BadRequestException,
  UnauthorizedException,
} from "@nestjs/common";
import { Country, State } from "country-state-city";
import type { Actor } from "../src/common/auth.guard";
import type { WorkspaceService } from "../src/workspace/workspace.service";
import type { BookingService } from "../src/bookings/booking.service";
import type { AccountsService } from "../src/accounts/accounts.service";
import type { TurfService } from "../src/turf/turf.service";
import type { CourtService } from "../src/court/court.service";
import type { PoolService } from "../src/pool/pool.service";
import type { HallService } from "../src/hall/hall.service";
import { acceptanceSchema } from "../src/workspace/validation";
import { renderReport } from "../src/accounts/accounts.report";

import type { ExpensesService } from "../src/expenses/expenses.service";
import { renderExpenseReport } from "../src/expenses/expenses.report";
import type { IncomeService } from "../src/income/income.service";
import { renderIncomeReport } from "../src/income/income.report";
type Services = {
  notifications: NotificationService;
  admin: AdminService;
  adminSarvam: AdminSarvamService;
  support: SupportService;
  agentCalls: AgentCallService;
  website: WebsiteService;
  blocks: SlotBlocksService;
  admissions: AdmissionService;
  messages: MessagesService;
  sarvam: SarvamService;
  voice: VoiceService;
  expenses: ExpensesService;
  income: IncomeService;
  workspace: WorkspaceService;
  bookings: BookingService;
  accounts: AccountsService;
  turf: TurfService;
  court: CourtService;
  pool: PoolService;
  hall: HallService;
};
type Input = {
  actor: Actor;
  body: unknown;
  query: Record<string, string>;
  params: Record<string, string>;
};
type Route = { method: string; path: string; run: (i: Input) => unknown };
const MAX_BODY = 3 * 1024 * 1024;
async function body(req: Request, limit = MAX_BODY) {
  if (!["POST", "PATCH", "PUT"].includes(req.method)) return undefined;
  if (!req.body) return undefined;
  if (Number(req.headers.get("content-length")) > limit)
    throw new HttpException("Request body is too large.", 413);
  const reader = req.body?.getReader();
  if (!reader) throw new BadRequestException("JSON body is required.");
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > limit) {
        await reader.cancel();
        throw new HttpException("Request body is too large.", 413);
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  if (size === 0) return undefined;
  if (
    !req.headers
      .get("content-type")
      ?.toLowerCase()
      .startsWith("application/json")
  )
    throw new HttpException("JSON content type is required.", 415);
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const part of chunks) {
    bytes.set(part, offset);
    offset += part.length;
  }
  try {
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    throw new BadRequestException("Invalid JSON body.");
  }
}
export function createHandler(
  services: Services,
  authenticate: (token: string) => Promise<Actor>,
  health: () => Promise<unknown>,
) {
  const { workspace: w, bookings: b, accounts: a } = services;
  const routes: Route[] = [];
  const add = (method: string, path: string, run: Route["run"]) =>
    routes.push({ method, path, run });
  add("POST", "/v1/notifications/devices", (i) =>
    services.notifications.register(i.actor, i.body),
  );
  add("POST", "/v1/notifications/devices/:id/unregister", (i) =>
    services.notifications.unregister(i.actor, i.params.id, i.body),
  );
  const ad = services.admin;
  const sm = services.adminSarvam;
  add("GET", "/v1/admin/sarvam", (i) => sm.status(i.actor));
  add("PUT", "/v1/admin/sarvam", (i) => sm.save(i.actor, i.body));
  add("POST", "/v1/admin/sarvam/connect", (i) => sm.connect(i.actor));
  add("POST", "/v1/admin/sarvam/callback", (i) => sm.callback(i.actor, i.body));
  add("GET", "/v1/admin/sarvam/inventory", (i) => sm.inventory(i.actor));
  add("GET", "/v1/admin/sarvam/jobs/:id", (i) => sm.job(i.actor, i.params.id));
  add("POST", "/v1/admin/sarvam/jobs/:id/approve", (i) =>
    sm.approve(i.actor, i.params.id, i.body),
  );
  add("POST", "/v1/admin/sarvam/jobs/:id/resume", (i) =>
    sm.resume(i.actor, i.params.id),
  );
  add("GET", "/v1/admin/me", (i) => ad.me(i.actor));
  add("GET", "/v1/admin/overview", (i) => ad.overview(i.actor));
  add("GET", "/v1/admin/organizations", (i) =>
    ad.organizations(i.actor, i.query),
  );
  add("GET", "/v1/admin/organizations/:id", (i) =>
    ad.organization(i.actor, i.params.id),
  );
  add("GET", "/v1/admin/users", (i) => ad.users(i.actor, i.query));
  add("PUT", "/v1/admin/users/:id/active", (i) =>
    ad.setUserActive(i.actor, i.params.id, i.body),
  );
  add("GET", "/v1/admin/support/tickets", (i) => ad.tickets(i.actor, i.query));
  add("GET", "/v1/admin/support/tickets/:id", (i) =>
    ad.ticket(i.actor, i.params.id),
  );
  add("POST", "/v1/admin/support/tickets/:id/reply", (i) =>
    ad.reply(i.actor, i.params.id, i.body),
  );
  add("PUT", "/v1/admin/support/tickets/:id/status", (i) =>
    ad.setTicketStatus(i.actor, i.params.id, i.body),
  );
  add("GET", "/v1/admin/agent-requests", (i) =>
    ad.agentRequests(i.actor, i.query),
  );
  add("PUT", "/v1/admin/agent-requests/:id", (i) =>
    ad.updateAgentRequest(i.actor, i.params.id, i.body),
  );
  add("GET", "/v1/admin/audit", (i) => ad.auditLog(i.actor, i.query));
  add("GET", "/v1/booking-website", (i) => services.website.settings(i.actor));
  add("PUT", "/v1/booking-website", (i) =>
    services.website.save(i.actor, i.body),
  );
  add("POST", "/v1/booking-website/publish", (i) =>
    services.website.publication(i.actor, "published", i.body),
  );
  add("POST", "/v1/booking-website/pause", (i) =>
    services.website.publication(i.actor, "paused", i.body),
  );
  add("POST", "/v1/booking-website/unpublish", (i) =>
    services.website.publication(i.actor, "unpublished", i.body),
  );
  add("POST", "/v1/booking-website/images", (i) =>
    services.website.uploadImage(i.actor, i.body),
  );
  add("POST", "/v1/booking-website/images/:id/remove", (i) =>
    services.website.removeImage(i.actor, i.params.id, i.body),
  );
  add("GET", "/v1/booking-website/images/:id", async (i) => {
    const image = await services.website.ownerImage(i.actor, i.params.id);
    return new Response(new Uint8Array(image.data), {
      headers: {
        "Content-Type": image.content_type,
        "Cache-Control": "private, no-store",
        "X-Content-Type-Options": "nosniff",
      },
    });
  });
  add("POST", "/v1/booking-website/preview", (i) =>
    services.website.preview(i.actor),
  );
  add("GET", "/v1/admissions/customers", (i) =>
    services.admissions.customers(i.actor, i.query.q ?? ""),
  );
  add("GET", "/v1/admissions/catalog", (i) =>
    services.admissions.catalog(i.actor),
  );
  add("POST", "/v1/admissions/preview", (i) =>
    services.admissions.preview(i.actor, i.body),
  );
  add("POST", "/v1/admissions/coach-conflicts", (i) =>
    services.admissions.coachConflicts(i.actor, i.body),
  );
  add("GET", "/v1/admissions/classes", (i) =>
    services.admissions.classes(i.actor, i.query),
  );
  add("GET", "/v1/admissions", (i) =>
    services.admissions.list(i.actor, i.query),
  );
  add("POST", "/v1/admissions", (i) =>
    services.admissions.create(i.actor, i.body),
  );
  add("GET", "/v1/admissions/:id", (i) =>
    services.admissions.detail(i.actor, i.params.id),
  );
  add("POST", "/v1/admissions/:id/check-ins", (i) =>
    services.admissions.checkIn(i.actor, i.params.id, i.body),
  );
  add("POST", "/v1/admissions/:id/sessions/:visitId/attendance", (i) =>
    services.admissions.attendance(
      i.actor,
      i.params.id,
      i.params.visitId,
      i.body,
    ),
  );
  add("POST", "/v1/admissions/:id/sessions/:visitId/change", (i) =>
    services.admissions.sessionChange(
      i.actor,
      i.params.id,
      i.params.visitId,
      i.body,
    ),
  );
  add("POST", "/v1/admissions/:id/payments", (i) =>
    services.admissions.payments(i.actor, i.params.id, i.body),
  );
  add("POST", "/v1/admissions/:id/cancel", (i) =>
    services.admissions.cancel(i.actor, i.params.id, i.body),
  );
  add("GET", "/v1/message-templates", (i) =>
    services.messages.catalog(i.actor),
  );
  add("POST", "/v1/message-templates", (i) =>
    services.messages.create(i.actor, i.body),
  );
  add("PUT", "/v1/message-templates/primary", (i) =>
    services.messages.primary(i.actor, i.body),
  );
  add("DELETE", "/v1/message-templates/:id", (i) =>
    services.messages.remove(i.actor, i.params.id),
  );
  add("GET", "/v1/support/tickets", (i) => services.support.list(i.actor));
  add("POST", "/v1/support/tickets", (i) =>
    services.support.create(i.actor, i.body),
  );
  add("GET", "/v1/support/tickets/:id", (i) =>
    services.support.detail(i.actor, i.params.id),
  );
  add("POST", "/v1/support/tickets/:id/messages", (i) =>
    services.support.addMessage(i.actor, i.params.id, i.body),
  );
  add("GET", "/v1/agent-calls", (i) => services.agentCalls.status(i.actor));
  add("POST", "/v1/agent-calls/request", (i) =>
    services.agentCalls.request(i.actor, i.body),
  );
  add("PUT", "/v1/agent-calls/enabled", (i) =>
    services.agentCalls.setEnabled(i.actor, i.body),
  );
  add("PUT", "/v1/agent-calls/spaces", (i) =>
    services.agentCalls.setSpaces(i.actor, i.body),
  );
  add("GET", "/v1/agent-calls/calls", (i) =>
    services.agentCalls.calls(i.actor, i.query),
  );
  add("GET", "/v1/agent-calls/transcript", (i) =>
    services.agentCalls.transcript(i.actor, i.query.interaction_id),
  );
  add("GET", "/v1/agent-calls/recording", async (i) => {
    const audio = await services.agentCalls.recording(
      i.actor,
      i.query.interaction_id,
    );
    return new Response(audio.data, {
      headers: {
        "Content-Type": audio.content_type,
        "Content-Disposition": 'attachment; filename="call.wav"',
      },
    });
  });
  add("GET", "/v1/admin/agent-requests/:id/connection", (i) =>
    ad.connection(i.actor, i.params.id),
  );
  add("PUT", "/v1/admin/agent-requests/:id/connection", (i) =>
    ad.saveConnection(i.actor, i.params.id, i.body),
  );
  add("POST", "/v1/admin/agent-requests/:id/verify", (i) =>
    ad.verifyConnection(i.actor, i.params.id, i.body),
  );
  add("POST", "/v1/admin/agent-requests/:id/tool-key", (i) =>
    ad.rotateToolKey(i.actor, i.params.id),
  );
  const voiceRoutes: Record<
    string,
    (actor: Actor, body: unknown) => Promise<unknown>
  > = {
    "/voice/v1/call-events": (a, b) => services.agentCalls.recordEvent(a, b),
    "/voice/v1/catalog": (a) => services.voice.catalog(a),
    "/voice/v1/availability": (a, b) => services.voice.availability(a, b),
    "/voice/v1/bookings": (a, b) => services.voice.book(a, b),
    "/voice/v1/my-bookings": (a, b) => services.voice.mine(a, b),
    "/voice/v1/reschedule": (a, b) => services.voice.reschedule(a, b),
    "/voice/v1/cancel": (a, b) => services.voice.cancel(a, b),
  };
  add("GET", "/v1/workspace", (i) => w.workspace(i.actor));
  add("GET", "/v1/organization/details", (i) => w.organizationDetails(i.actor));
  add("PATCH", "/v1/organization/details", (i) =>
    w.updateOrganization(i.actor, i.body),
  );
  add("POST", "/v1/organizations", (i) =>
    w.createOrganization(i.actor, i.body),
  );
  add("POST", "/v1/businesses", (i) => w.createBusiness(i.actor, i.body));
  add("PUT", "/v1/businesses/order", (i) =>
    w.reorderBusinesses(i.actor, i.body),
  );
  add("PATCH", "/v1/businesses/:id", (i) =>
    w.renameBusiness(i.actor, i.params.id, i.body),
  );
  add("POST", "/v1/businesses/:id/resources", (i) =>
    w.addResource(i.actor, i.params.id, i.body),
  );
  add("DELETE", "/v1/businesses/:id/resources/:resourceId", (i) =>
    w.deleteResource(i.actor, i.params.id, i.params.resourceId),
  );
  add("PATCH", "/v1/businesses/:id/configuration", (i) =>
    w.configure(i.actor, i.params.id, i.body),
  );
  for (const kind of ["turf", "court", "pool", "hall"] as const)
    add("PATCH", `/v1/businesses/:id/${kind}-configuration`, (i) =>
      services[kind].configure(i.actor, i.params.id, i.body),
    );
  add("POST", "/v1/businesses/:id/activate", (i) =>
    w.activate(i.actor, i.params.id),
  );
  add("GET", "/v1/team", (i) => w.team(i.actor));
  add("POST", "/v1/invitations", (i) => w.invite(i.actor, i.body));
  add("POST", "/v1/workspace/session", (i) => w.session(i.actor));
  add("POST", "/v1/team", (i) => w.emailTeamAccess.add(i.actor, i.body));
  add("POST", "/v1/invitations/:id/email", (i) =>
    w.emailTeamAccess.deliver(i.actor, i.params.id),
  );
  add("PATCH", "/v1/invitations/:id/access", (i) =>
    w.emailTeamAccess.update(i.actor, i.params.id, i.body),
  );
  add("POST", "/v1/invitations/accept", (i) =>
    w.accept(i.actor, acceptanceSchema.parse(i.body).token),
  );
  add("DELETE", "/v1/invitations/:id", (i) =>
    w.revoke(i.actor, i.params.id, true),
  );
  add("DELETE", "/v1/team/:id/permanent", (i) =>
    w.deleteTeamRecord(i.actor, i.params.id, false),
  );
  add("DELETE", "/v1/invitations/:id/permanent", (i) =>
    w.deleteTeamRecord(i.actor, i.params.id, true),
  );
  add("DELETE", "/v1/team/:id", (i) => w.revoke(i.actor, i.params.id, false));
  add("PUT", "/v1/team/me/coach", (i) => w.ownerCoach(i.actor, i.body));
  add("PATCH", "/v1/businesses/:id/plan-coaches", (i) =>
    w.planCoaches(i.actor, i.params.id, i.body),
  );
  add("PATCH", "/v1/team/:id", (i) =>
    w.updateMember(i.actor, i.params.id, i.body),
  );
  add("POST", "/v1/organization/logo", (i) =>
    w.uploadLogo(
      i.actor,
      i.body as Parameters<WorkspaceService["uploadLogo"]>[1],
    ),
  );
  add("GET", "/v1/organization/logo", async (i) => {
    const logo = await w.logo(i.actor);
    return new Response(new Uint8Array(logo.data), {
      headers: { "Content-Type": logo.content_type },
    });
  });
  add("GET", "/v1/booking-blocks", (i) =>
    services.blocks.list(i.actor, i.query),
  );
  add("GET", "/v1/booking-blocks/slots", (i) =>
    services.blocks.slots(i.actor, i.query),
  );
  add("POST", "/v1/booking-blocks", (i) =>
    services.blocks.create(i.actor, i.body),
  );
  add("POST", "/v1/booking-blocks/:id/unblock", (i) =>
    services.blocks.unblock(i.actor, i.params.id, i.body),
  );
  add("GET", "/v1/bookings/catalog", (i) => b.catalog(i.actor));
  add("GET", "/v1/bookings/date-counts", (i) => b.dateCounts(i.actor, i.query));
  add("GET", "/v1/bookings/customers", (i) =>
    b.customers(i.actor, i.query.q ?? ""),
  );
  add("GET", "/v1/bookings/customer-directory", (i) =>
    b.customerDirectory(i.actor, i.query),
  );
  add("GET", "/v1/bookings/customer-directory/:id", (i) =>
    b.customerHistory(i.actor, i.params.id, i.query),
  );
  add("GET", "/v1/bookings/dashboard", (i) =>
    b.dashboard(i.actor, i.query.business_id),
  );
  add("GET", "/v1/bookings/outstanding", (i) =>
    b.outstanding(i.actor, i.query),
  );
  add("GET", "/v1/bookings/collections", (i) =>
    b.paymentList(i.actor, i.query),
  );
  add("GET", "/v1/bookings/commands/:key", (i) =>
    b.commandResult(i.actor, i.params.key),
  );
  add("POST", "/v1/bookings/quote", (i) => b.quote(i.actor, i.body));
  add("POST", "/v1/bookings/availability", (i) =>
    b.availability(i.actor, i.body),
  );
  add("POST", "/v1/bookings", (i) => b.create(i.actor, i.body));
  add("GET", "/v1/bookings", (i) => b.list(i.actor, i.query));
  add("GET", "/v1/bookings/:id", (i) => b.detail(i.actor, i.params.id));
  add("POST", "/v1/bookings/:id/reschedule", (i) =>
    b.reschedule(i.actor, i.params.id, i.body),
  );
  add("POST", "/v1/bookings/:id/payments", (i) =>
    b.payments(i.actor, i.params.id, i.body),
  );
  add("POST", "/v1/bookings/:id/status", (i) =>
    b.status(i.actor, i.params.id, i.body),
  );
  add("POST", "/v1/bookings/:id/customer", (i) =>
    b.editCustomer(i.actor, i.params.id, i.body),
  );
  add("GET", "/v1/accounts/catalog", (i) => a.catalog(i.actor));
  add("GET", "/v1/accounts/website-payments", (i) =>
    a.websitePayments(i.actor),
  );
  add("POST", "/v1/accounts/website-payments", (i) =>
    a.saveWebsitePayments(i.actor, i.body),
  );
  add("GET", "/v1/accounts/overview", (i) => a.overview(i.actor, i.query));
  add("GET", "/v1/accounts/transactions", (i) =>
    a.transactions(i.actor, i.query),
  );
  add("POST", "/v1/accounts/cash/opening", (i) =>
    a.cashOpening(i.actor, i.body),
  );
  add("POST", "/v1/accounts/banks", (i) => a.createAccount(i.actor, i.body));
  add("PATCH", "/v1/accounts/banks/:id", (i) =>
    a.updateAccount(i.actor, i.params.id, i.body),
  );
  add("POST", "/v1/accounts/routes", (i) => a.route(i.actor, i.body));
  add("POST", "/v1/accounts/entries", (i) => a.createEntry(i.actor, i.body));
  add("POST", "/v1/accounts/entries/:id/reverse", (i) =>
    a.reverse(i.actor, i.params.id, i.body),
  );
  add("GET", "/v1/accounts/reports/:format", async (i) => {
    const format = z.enum(["pdf", "xlsx"]).parse(i.params.format),
      type = z
        .enum(["monthly", "yearly", "bookings", "cash_flow"])
        .parse(i.query.type);
    const { type: _, ...filter } = i.query,
      data = await a.report(i.actor, filter),
      bytes = await renderReport(data, format, type);
    return new Response(new Uint8Array(bytes), {
      headers: {
        "Content-Type":
          format === "pdf"
            ? "application/pdf"
            : "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "Content-Disposition": `attachment; filename="booking-os-${type}-${data.from}-${data.until}.${format}"`,
      },
    });
  });
  const e = services.expenses;
  add("GET", "/v1/expenses/catalog", (i) => e.catalog(i.actor));
  add("POST", "/v1/expenses/categories", (i) => e.category(i.actor, i.body));
  add("PATCH", "/v1/expenses/categories/:id", (i) =>
    e.category(i.actor, i.body, i.params.id),
  );
  add("GET", "/v1/expenses/overview", (i) => e.overview(i.actor, i.query));
  add("GET", "/v1/expenses", (i) => e.list(i.actor, i.query));
  add("POST", "/v1/expenses", (i) => e.create(i.actor, i.body));
  add("GET", "/v1/expenses/reports/:format", async (i) => {
    const format = z.enum(["pdf", "xlsx"]).parse(i.params.format);
    const data = await e.report(i.actor, i.query),
      bytes = await renderExpenseReport(data, format);
    return new Response(new Uint8Array(bytes), {
      headers: {
        "Content-Type":
          format === "pdf"
            ? "application/pdf"
            : "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "Content-Disposition": `attachment; filename="expenses-${data.from}-${data.until}.${format}"`,
      },
    });
  });
  add("GET", "/v1/expenses/:id", (i) => e.detail(i.actor, i.params.id));
  add("POST", "/v1/expenses/:id/attachments", (i) =>
    e.prepare(i.actor, i.params.id, i.body),
  );
  add("POST", "/v1/expenses/:id/attachments/:attachmentId/complete", (i) =>
    e.complete(i.actor, i.params.id, i.params.attachmentId),
  );
  add("GET", "/v1/expenses/:id/attachments/:attachmentId", (i) =>
    e.attachment(i.actor, i.params.id, i.params.attachmentId),
  );
  add("DELETE", "/v1/expenses/:id/attachments/:attachmentId", (i) =>
    e.removePending(i.actor, i.params.id, i.params.attachmentId),
  );
  const inc = services.income;
  add("GET", "/v1/income/catalog", (i) => inc.catalog(i.actor));
  add("POST", "/v1/income/categories", (i) => inc.category(i.actor, i.body));
  add("PATCH", "/v1/income/categories/:id", (i) =>
    inc.category(i.actor, i.body, i.params.id),
  );
  add("GET", "/v1/income/overview", (i) => inc.overview(i.actor, i.query));
  add("GET", "/v1/income", (i) => inc.list(i.actor, i.query));
  add("POST", "/v1/income", (i) => inc.create(i.actor, i.body));
  add("GET", "/v1/income/reports/:format", async (i) => {
    const format = z.enum(["pdf", "xlsx"]).parse(i.params.format);
    const data = await inc.report(i.actor, i.query),
      bytes = await renderIncomeReport(data, format);
    return new Response(new Uint8Array(bytes), {
      headers: {
        "Content-Type":
          format === "pdf"
            ? "application/pdf"
            : "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "Content-Disposition": `attachment; filename="income-${data.from}-${data.until}.${format}"`,
      },
    });
  });
  // Bounded, per-worker burst protection; authorization stays in shared services.
  const bursts = new Map<string, { until: number; count: number }>();
  return async (req: Request): Promise<Response> => {
    const requestId = crypto.randomUUID();
    const started = performance.now();
    let authenticationMs = 0;
    const timing = () =>
      headers.set(
        "Server-Timing",
        `app;dur=${(performance.now() - started).toFixed(1)}, auth;dur=${authenticationMs.toFixed(1)}`,
      );
    const headers = new Headers({
      "Cache-Control": "private, no-store",
      "X-Content-Type-Options": "nosniff",
      "X-Request-Id": requestId,
    });
    const origin = req.headers.get("origin");
    // Keep exact origins for both hosts during a public-domain transition.
    const allowed = [
      ...(process.env.BOOKING_CORS_ORIGINS ?? "").split(","),
      ...(process.env.BOOKING_WEB_ORIGIN ?? "").split(","),
    ]
      .map((value) => value.trim())
      .filter(Boolean);
    if (origin && allowed.includes(origin)) {
      headers.set("Access-Control-Allow-Origin", origin);
      headers.set("Vary", "Origin");
      headers.set(
        "Access-Control-Allow-Headers",
        "authorization, apikey, content-type, x-client-info",
      );
      headers.set(
        "Access-Control-Allow-Methods",
        "GET,POST,PUT,PATCH,DELETE,OPTIONS",
      );
      headers.set(
        "Access-Control-Expose-Headers",
        "Content-Disposition,X-Request-Id,Server-Timing",
      );
    }
    const respond = (data: unknown, status = 200) => {
      timing();
      return Response.json(data, { status, headers });
    };
    try {
      if (origin && !allowed.includes(origin))
        throw new HttpException("Origin is not allowed.", 403);
      if (req.method === "OPTIONS")
        return new Response(null, { status: 204, headers });
      const url = new URL(req.url),
        path =
          url.pathname
            .replace(/^\/(?:functions\/v1\/)?booking-api(?=\/|$)/, "")
            .replace(/\/$/, "") || "/";
      if (req.method === "GET" && path === "/invite") {
        const { token } = acceptanceSchema.parse(
          Object.fromEntries(url.searchParams),
        );
        const target = new URL("com.bookingos.app://invite/invite");
        target.searchParams.set("token", token);
        headers.set("Location", target.toString());
        headers.set("Referrer-Policy", "no-referrer");
        return new Response(null, { status: 302, headers });
      }
      if (req.method === "GET" && path === "/v1/sarvam/oauth/callback") {
        await services.sarvam.oauthCallback(
          Object.fromEntries(url.searchParams),
        );
        headers.set("Content-Type", "text/html; charset=utf-8");
        headers.set("Referrer-Policy", "no-referrer");
        return new Response(
          "<!doctype html><title>BookingOS</title><p>Authorization processed. Return to BookingOS to continue setup.</p>",
          { headers },
        );
      }
      if (req.method === "GET" && path === "/health") {
        await health();
        return respond({
          status: "ok",
          runtime: "supabase-edge",
          revision: "2026-10-24-flexible-coach-attendance",
        });
      }
      if (req.method === "GET" && path === "/v1/catalog")
        return respond({
          countries: Country.getAllCountries().map((c) => ({
            code: c.isoCode,
            name: c.name,
          })),
          timezones: [
            ...new Set([
              "Asia/Kolkata",
              "UTC",
              ...Intl.supportedValuesOf("timeZone"),
            ]),
          ].sort(),
        });
      if (
        req.method === "GET" &&
        /^\/v1\/catalog\/states\/[A-Z]{2}$/.test(path)
      )
        return respond(
          State.getStatesOfCountry(path.split("/").at(-1)!).map((s) => ({
            code: s.isoCode,
            name: s.name,
          })),
        );
      const publicWebsite =
        /^\/public\/v1\/sites\/([^/]+)(?:\/(catalog|logo|payment-qr|images\/[a-f0-9-]{36}|availability|quote|bookings))?$/.exec(
          path,
        );
      if (publicWebsite) {
        const slug = decodeURIComponent(publicWebsite[1]),
          operation = publicWebsite[2] ?? "catalog";
        const preview = url.searchParams.get("preview") ?? undefined;
        if (req.method === "GET" && operation === "catalog")
          return respond(await services.website.catalog(slug, preview));
        if (req.method === "GET" && operation === "payment-qr") {
          const image = await services.website.paymentQr(
            slug,
            preview,
            url.searchParams.get("v") ?? undefined,
          );
          headers.set("Content-Type", image.content_type);
          return new Response(new Uint8Array(image.data), { headers });
        }
        if (req.method === "GET" && operation.startsWith("images/")) {
          const image = await services.website.image(
            slug,
            operation.slice(7),
            preview,
          );
          headers.set("Content-Type", image.content_type);
          return new Response(new Uint8Array(image.data), { headers });
        }
        if (req.method === "GET" && operation === "logo") {
          const logo = await services.website.logo(slug, preview);
          headers.set("Content-Type", logo.content_type);
          return new Response(new Uint8Array(logo.data), { headers });
        }
        if (
          req.method === "POST" &&
          ["availability", "quote", "bookings"].includes(operation)
        ) {
          if (Number(req.headers.get("content-length")) > 16384)
            throw new HttpException("Request body is too large.", 413);
          const input = await body(req);
          if (JSON.stringify(input ?? {}).length > 16384)
            throw new HttpException("Request body is too large.", 413);
          const result =
            operation === "availability"
              ? await services.website.availability(slug, input, preview)
              : operation === "quote"
                ? await services.website.quote(slug, input, preview)
                : await services.website.book(slug, input, preview);
          return respond(result, operation === "bookings" ? 201 : 200);
        }
        throw new HttpException("Route not found.", 404);
      }
      if (
        req.method === "POST" &&
        path === "/v1/notifications/installations/revoke"
      ) {
        const key = "installation-cleanup";
        const now = Date.now();
        const burst = bursts.get(key) ?? { until: now + 60000, count: 0 };
        if (burst.until <= now)
          Object.assign(burst, { until: now + 60000, count: 0 });
        if (++burst.count > 120)
          throw new HttpException("Try again shortly.", 429);
        bursts.set(key, burst);
        if (Number(req.headers.get("content-length")) > 1024)
          throw new HttpException("Request body is too large.", 413);
        return respond(
          await services.notifications.revokeInstallation(
            await body(req, 1024),
          ),
        );
      }
      const voice = voiceRoutes[path];
      if (voice && req.method === "POST") {
        // Sarvam tool calls: tool key instead of a user session.
        const actor = await services.sarvam.authenticateToolKey(
          req.headers.get("x-api-key"),
          path === "/voice/v1/call-events",
        );
        const now = Date.now();
        const burst = bursts.get(actor.uid) ?? { until: now + 60000, count: 0 };
        if (burst.until <= now)
          Object.assign(burst, { until: now + 60000, count: 0 });
        if (++burst.count > 120)
          throw new HttpException(
            "Too many requests. Please try again shortly.",
            429,
          );
        bursts.set(actor.uid, burst);
        return respond(
          await voiceResult(async () => voice(actor, await body(req))),
        );
      }
      const segments = path.split("/");
      let match: Route | undefined;
      const params: Record<string, string> = {};
      for (const route of routes) {
        if (route.method !== req.method) continue;
        const parts = route.path.split("/");
        if (parts.length !== segments.length) continue;
        const candidate: Record<string, string> = {};
        if (
          parts.every((part, n) =>
            part.startsWith(":")
              ? ((candidate[part.slice(1)] = decodeURIComponent(segments[n])),
                true)
              : part === segments[n],
          )
        ) {
          match = route;
          Object.assign(params, candidate);
          break;
        }
      }
      if (!match) throw new HttpException("Route not found.", 404);
      const token = /^Bearer (\S+)$/.exec(
        req.headers.get("authorization") ?? "",
      )?.[1];
      const isAdmin = path.startsWith("/v1/admin/");
      if (!isAdmin && !token)
        throw new UnauthorizedException("Sign in to continue.");
      const authStarted = performance.now();
      const input = isAdmin ? await body(req) : undefined;
      const actor = await (
        isAdmin
          ? Promise.resolve().then(() =>
              panelActor(
                req.headers.get("x-bookingos-admin"),
                req.method,
                path + url.search,
                input,
              ),
            )
          : authenticate(token!)
      ).finally(() => {
        authenticationMs = performance.now() - authStarted;
      });
      const now = Date.now();
      for (const [key, v] of bursts) if (v.until <= now) bursts.delete(key);
      if (bursts.size >= 1000 && !bursts.has(actor.uid))
        throw new HttpException("Server busy. Please try again.", 429);
      const burst = bursts.get(actor.uid) ?? { until: now + 60000, count: 0 };
      if (++burst.count > 120)
        throw new HttpException(
          "Too many requests. Please try again shortly.",
          429,
        );
      bursts.set(actor.uid, burst);
      for (const [key, value] of Object.entries(params))
        if (key !== "format") z.uuid().parse(value);
      const result = await match.run({
        actor,
        params,
        body: isAdmin ? input : await body(req),
        query: Object.fromEntries(url.searchParams),
      });
      if (result instanceof Response) {
        timing();
        for (const [key, value] of headers) result.headers.set(key, value);
        return result;
      }
      return respond(result ?? {}, req.method === "POST" ? 201 : 200);
    } catch (error) {
      let status = 500,
        message = "Something went wrong. Please try again.",
        code = "INTERNAL_ERROR";
      if (error instanceof ZodError) {
        status = 422;
        message = error.issues
          .map((i) => `${i.path.join(".")}: ${i.message}`)
          .join("; ");
        code = "VALIDATION_ERROR";
      } else if (error instanceof HttpException) {
        status = error.getStatus();
        message = error.message;
        code =
          status === 409
            ? "CONFLICT"
            : status === 403
              ? "FORBIDDEN"
              : status === 401
                ? "UNAUTHENTICATED"
                : "REQUEST_ERROR";
      } else if ((error as { code?: string })?.code === "23505") {
        status = 409;
        message = "A record with these details already exists.";
        code = "CONFLICT";
      } else
        console.error(
          JSON.stringify({
            request_id: requestId,
            error: error instanceof Error ? error.name : "UnknownError",
          }),
        );
      return respond({ code, message, request_id: requestId }, status);
    }
  };
}
