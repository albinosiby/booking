import "server-only";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { SESSION_COOKIE } from "./session-name";
import { validSession } from "./session-token";
import { signAdminRequest } from "./request-signature";
import { adminRedirectUrl } from "./redirect-url";
import { configuredApiBase } from "./api-origin";

export function apiBase() {
  return configuredApiBase(process.env.BOOKING_API_BASE_URL);
}

export class ApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message);
  }
}

/** A valid password session permits signed, server-only admin API calls. */
export async function admin<T = any>(
  path: string,
  init: { method?: string; body?: unknown } = {},
): Promise<T> {
  if (!(await validSession((await cookies()).get(SESSION_COOKIE)?.value)))
    redirect(await adminRedirectUrl("/login"));
  const method = init.method ?? "GET";
  const body = init.body === undefined ? undefined : JSON.stringify(init.body);
  const target = new URL(`${apiBase()}/v1/admin${path}`);
  const logical = new URL(`/v1/admin${path}`, "https://admin.internal");
  const response = await fetch(target, {
    method,
    headers: {
      "x-bookingos-admin": signAdminRequest(
        method,
        logical.pathname + logical.search,
        body,
      ),
      apikey: process.env.BOOKING_API_PUBLISHABLE_KEY ?? "",
      ...(init.body === undefined
        ? {}
        : { "Content-Type": "application/json" }),
    },
    body,
    cache: "no-store",
    signal: AbortSignal.timeout(20000),
  });
  if (!response.ok) {
    let message = "Request failed.";
    try {
      const data = await response.json();
      message =
        typeof data.message === "string"
          ? data.message
          : (data.message?.[0] ?? message);
    } catch {}
    throw new ApiError(message, response.status);
  }
  return (await response.json()) as T;
}
