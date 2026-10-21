/** MCP tools for finding, booking, rescheduling and cancelling reservations. */
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import type { BookingClient } from "./client.js";

const date = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Use YYYY-MM-DD");
const selection = z
  .object({
    business_id: z.uuid(),
    resource_id: z.uuid().describe("Space/resource id from list_bookable_options"),
    option_id: z.string().max(100).describe("Booking option id for that resource"),
    date: date.describe("Business-local date, YYYY-MM-DD"),
    time: z
      .string()
      .regex(/^([01]\d|2[0-3]):[0-5]\d$/)
      .describe("Business-local start time, HH:MM (24h)"),
    duration_minutes: z.number().int().min(1).max(1440),
    people: z.number().int().min(1).max(10000).default(1),
  })
  .describe("What, where and when to book");
const quoteToken = z
  .string()
  .regex(/^[a-f0-9]{64}$/)
  .describe("quote_token from quote_booking for this exact selection");
const commandKey = z
  .uuid()
  .optional()
  .describe(
    "Only when retrying an uncertain write: reuse the command_key from the failed attempt with identical inputs",
  );
const version = z
  .number()
  .int()
  .positive()
  .describe("Booking version from get_booking; rejects stale changes");
const reason = z.string().trim().min(2).max(500);

const json = (data: unknown) => ({
  content: [{ type: "text" as const, text: JSON.stringify(data, null, 2) }],
});

async function run(fn: () => Promise<unknown>) {
  try {
    return json(await fn());
  } catch (error) {
    return {
      isError: true,
      content: [{ type: "text" as const, text: (error as Error).message }],
    };
  }
}

/** Booking summary without bulky snapshots, for list results. */
function summary(b: Record<string, any>) {
  return {
    id: b.id,
    reference: b.reference,
    status: b.status,
    version: b.version,
    business_id: b.business_id,
    resource_id: b.resource_id,
    customer: b.customer_snapshot,
    local_start: b.local_start,
    local_end: b.local_end,
    total_minor: b.total_minor,
    payment_status: b.payment_status,
    balance_minor: b.balance_minor,
  };
}

export function registerTools(server: McpServer, api: BookingClient) {
  const read = { readOnlyHint: true, openWorldHint: true };

  server.registerTool(
    "list_bookable_options",
    {
      title: "List bookable businesses",
      description:
        "Businesses, spaces (resource_id) and booking options (option_id) this account can book, with each business's timezone, today's local date, currency and the account's permissions. Call first to build a selection. Money is in minor units (paise/cents).",
      annotations: read,
    },
    () =>
      run(async () => {
        const c = await api.request("GET", "/bookings/catalog");
        return {
          currency: c.currency,
          permissions: {
            can_manage: c.can_manage,
            can_collect: c.can_collect,
            can_refund: c.can_refund,
          },
          businesses: c.businesses.map((b: any) => ({
            ...b,
            resources: b.resources.map((r: any) => ({
              ...r,
              // Flexible options list every 15-minute duration; min/step say the same.
              options: r.options.map(({ durations, ...o }: any) =>
                o.kind === "hourly" ? o : { ...o, durations },
              ),
            })),
          })),
        };
      }),
  );

  server.registerTool(
    "check_availability",
    {
      title: "Check availability",
      description:
        "Priced start times for a space/option/duration on a date. Each slot has time, available, status (available/booked/past) and total_minor. Does not hold the slot; quote before booking. Pass exclude_booking_id when finding a new time for an existing booking.",
      inputSchema: {
        selection,
        exclude_booking_id: z.uuid().optional(),
      },
      annotations: read,
    },
    ({ selection, exclude_booking_id }) =>
      run(() =>
        api.request("POST", "/bookings/availability", {
          body: { selection, exclude_booking_id: exclude_booking_id ?? null },
        }),
      ),
  );

  server.registerTool(
    "quote_booking",
    {
      title: "Quote a booking",
      description:
        "Authoritative price and availability for an exact selection. Returns total_minor, local_start/local_end and a quote_token needed by create_booking or reschedule_booking. Confirm the price with the user before booking. For reschedules pass exclude_booking_id so the booking's own slot is not counted as occupied.",
      inputSchema: {
        selection,
        exclude_booking_id: z.uuid().optional(),
      },
      annotations: read,
    },
    ({ selection, exclude_booking_id }) =>
      run(() =>
        api.request("POST", "/bookings/quote", {
          body: { selection, exclude_booking_id: exclude_booking_id ?? null },
        }),
      ),
  );

  server.registerTool(
    "find_bookings",
    {
      title: "Find bookings",
      description:
        "Search bookings, newest start first, 100 per page. q matches customer name, phone or booking reference. Dates are business-local. Use next_cursor for more.",
      inputSchema: {
        q: z.string().trim().max(100).optional(),
        date: date.optional().describe("Start date (or only date)"),
        date_until: date.optional().describe("Inclusive end date"),
        business_id: z.uuid().optional(),
        resource_id: z.uuid().optional(),
        status: z
          .enum(["confirmed", "completed", "cancelled", "no_show"])
          .optional(),
        cursor: z.number().int().min(0).optional(),
      },
      annotations: read,
    },
    (query) =>
      run(async () => {
        const page = await api.request("GET", "/bookings", { query });
        return {
          items: page.items.map(summary),
          next_cursor: page.next_cursor,
        };
      }),
  );

  server.registerTool(
    "get_booking",
    {
      title: "Get booking",
      description:
        "Full booking with current version, status, times, customer, price, balance, payments and history. Fetch before rescheduling or cancelling to get the version.",
      inputSchema: { booking_id: z.uuid() },
      annotations: read,
    },
    ({ booking_id }) => run(() => api.request("GET", `/bookings/${booking_id}`)),
  );

  server.registerTool(
    "create_booking",
    {
      title: "Create booking",
      description:
        "Book a slot using a fresh quote_token from quote_booking for the same selection. Fails if the slot was taken or the price changed since quoting; re-quote and confirm with the user. Optionally record payments already received.",
      inputSchema: {
        selection,
        quote_token: quoteToken,
        customer: z.object({
          id: z
            .uuid()
            .nullable()
            .default(null)
            .describe("Existing customer id, or null for a new one"),
          name: z.string().trim().min(2).max(100),
          phone: z.string().trim().describe("7–15 digits, optional leading +"),
          email: z.email().max(200).nullable().default(null),
        }),
        notes: z.string().trim().max(1000).default(""),
        payments: z
          .array(
            z.object({
              method: z.enum(["cash", "upi", "card", "bank_transfer"]),
              amount_minor: z.number().int().min(1),
              reference: z.string().trim().max(200).default(""),
              received_at: z
                .string()
                .optional()
                .describe("ISO timestamp with offset; defaults to now"),
            }),
          )
          .max(20)
          .default([]),
        command_key: commandKey,
      },
      annotations: { destructiveHint: false, openWorldHint: true },
    },
    ({ payments, ...input }) =>
      run(async () => {
        const result = await api.command("/bookings", {
          ...input,
          payments: payments.map((p) => ({
            ...p,
            received_at: p.received_at ?? new Date().toISOString(),
          })),
        });
        return {
          ...result,
          booking: await api.request("GET", `/bookings/${result.id}`),
        };
      }),
  );

  server.registerTool(
    "reschedule_booking",
    {
      title: "Reschedule booking",
      description:
        "Move a confirmed booking to a new time/space in the same business, atomically. Steps: get_booking (version), quote_booking with exclude_booking_id=booking_id, confirm the new price with the user, then call this. The agreed price becomes the new quote's total.",
      inputSchema: {
        booking_id: z.uuid(),
        version,
        selection,
        quote_token: quoteToken,
        reason: reason.describe("Why the booking is moving"),
        command_key: commandKey,
      },
      annotations: { destructiveHint: true, openWorldHint: true },
    },
    ({ booking_id, ...input }) =>
      run(async () => {
        const result = await api.command(
          `/bookings/${booking_id}/reschedule`,
          input,
        );
        return {
          ...result,
          booking: await api.request("GET", `/bookings/${booking_id}`),
        };
      }),
  );

  server.registerTool(
    "cancel_booking",
    {
      title: "Cancel booking",
      description:
        "Cancel a confirmed booking and free its slot. Requires the current version from get_booking. Cannot be undone. Any money already collected becomes refund due; refunds are recorded separately by the owner.",
      inputSchema: {
        booking_id: z.uuid(),
        version,
        reason: reason.describe("Why the booking is cancelled"),
        command_key: commandKey,
      },
      annotations: { destructiveHint: true, openWorldHint: true },
    },
    ({ booking_id, ...input }) =>
      run(async () => {
        const result = await api.command(`/bookings/${booking_id}/status`, {
          ...input,
          status: "cancelled",
        });
        return {
          ...result,
          booking: await api.request("GET", `/bookings/${booking_id}`),
        };
      }),
  );
}
