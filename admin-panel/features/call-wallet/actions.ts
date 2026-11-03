"use server";
import { revalidatePath } from "next/cache";
import { admin, ApiError } from "../../lib/api";
import { adminPath } from "../../lib/paths";
import type { ActionResult } from "../call-service/actions";

async function execute(
  path: string,
  method: string,
  body: unknown,
  success: string,
  revalidate: string,
): Promise<ActionResult> {
  try {
    const result = await admin<{ duplicate?: boolean }>(path, { method, body });
    revalidatePath(adminPath(revalidate), "layout");
    return {
      success: result.duplicate ? "This entry was already saved." : success,
    };
  } catch (error) {
    if (error instanceof ApiError) return { error: error.message };
    if (
      error instanceof Error &&
      ["TimeoutError", "AbortError", "TypeError"].includes(error.name)
    )
      return {
        error: "The service did not respond. Refresh the page before retrying.",
      };
    throw error;
  }
}

/** "10.80" → 1080. Blank stays null so a client can follow the default. */
function paise(value: FormDataEntryValue | null) {
  const text = String(value ?? "").trim().replace(/[₹,\s]/g, "");
  if (!text) return null;
  if (!/^\d+(\.\d{1,2})?$/.test(text)) return NaN;
  return Math.round(Number(text) * 100);
}
function plans(value: FormDataEntryValue | null) {
  const text = String(value ?? "").trim();
  if (!text) return null;
  return text.split(/[,\s]+/).filter(Boolean).map((p) => paise(p) ?? NaN);
}
const invalid = (fields: Record<string, unknown>) =>
  Object.values(fields).some(
    (v) => Number.isNaN(v) || (Array.isArray(v) && v.some(Number.isNaN)),
  );
const CHECK = "Check the amounts. Use rupees, for example 250 or 10.80.";

export async function saveBillingDefaults(_: ActionResult, form: FormData) {
  const body = {
    version: Number(form.get("version")),
    rate_paise_per_minute: paise(form.get("rate")),
    plans_paise: plans(form.get("plans")),
    custom_enabled: form.get("custom_enabled") === "on",
    custom_above_paise: paise(form.get("custom_above")) ?? 0,
    custom_max_paise: paise(form.get("custom_max")),
    low_balance_paise: paise(form.get("low_balance")) ?? 0,
  };
  if (invalid(body)) return { error: CHECK };
  if (body.rate_paise_per_minute == null)
    return { error: "Enter the per-minute rate." };
  if (!body.plans_paise) return { error: "Add at least one recharge plan." };
  if (body.custom_max_paise == null)
    return { error: "Enter the largest custom amount." };
  return execute(
    "/call-billing",
    "PUT",
    body,
    "Default pricing saved. Clients see it the next time they open the wallet.",
    "/call-billing",
  );
}

export async function saveClientPricing(_: ActionResult, form: FormData) {
  const custom = String(form.get("custom_enabled") ?? "");
  const body = form.get("reset")
    ? {
        rate_paise_per_minute: null,
        plans_paise: null,
        custom_enabled: null,
        custom_above_paise: null,
        custom_max_paise: null,
        low_balance_paise: null,
      }
    : {
        rate_paise_per_minute: paise(form.get("rate")),
        plans_paise: plans(form.get("plans")),
        custom_enabled: custom === "on" ? true : custom === "off" ? false : null,
        custom_above_paise: paise(form.get("custom_above")),
        custom_max_paise: paise(form.get("custom_max")),
        low_balance_paise: paise(form.get("low_balance")),
      };
  if (invalid(body)) return { error: CHECK };
  const org = String(form.get("org"));
  return execute(
    `/organizations/${org}/call-wallet/pricing`,
    "PUT",
    body,
    form.get("reset")
      ? "This client now uses the default pricing."
      : "Client pricing saved.",
    `/organizations/${org}`,
  );
}

export async function adjustWallet(_: ActionResult, form: FormData) {
  const amount = paise(form.get("amount"));
  if (amount == null || Number.isNaN(amount) || amount === 0)
    return { error: "Enter the amount in rupees." };
  const direction = String(form.get("direction") ?? "add");
  const deduct = direction === "deduct",
    free = direction === "free";
  const mode = String(form.get("payment_mode") ?? "");
  const org = String(form.get("org"));
  return execute(
    `/organizations/${org}/call-wallet/adjustments`,
    "POST",
    {
      request_id: String(form.get("request_id")),
      amount_paise: deduct ? -amount : amount,
      // Free credits and deductions record no payment.
      payment_mode: deduct || free || !mode ? null : mode,
      external_reference: String(form.get("external_reference") ?? ""),
      note: String(form.get("note") ?? ""),
    },
    deduct
      ? "Balance deducted."
      : free
        ? "Free credit added to the client's wallet."
        : "Balance added to the client's wallet.",
    `/organizations/${org}`,
  );
}
