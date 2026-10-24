const fields = [
  "organizations", "users", "active_users", "businesses", "bookings",
  "customers", "open_tickets", "pending_agent_requests",
] as const;

export type OverviewTotals = Record<(typeof fields)[number], number>;

export function overviewTotals(value: unknown): OverviewTotals {
  if (!value || typeof value !== "object") {
    throw new Error("Live platform totals are unavailable. Please retry.");
  }
  const totals = value as Record<string, unknown>;
  for (const field of fields) {
    if (!Number.isSafeInteger(totals[field]) || Number(totals[field]) < 0) {
      throw new Error("Live platform totals are incomplete. Please retry.");
    }
  }
  return totals as OverviewTotals;
}
