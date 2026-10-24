"use server";
import { cookies, headers } from "next/headers";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { admin } from "../lib/api";
import { createHash, timingSafeEqual } from "node:crypto";
import { loginAttempts } from "../lib/login-attempts";
import { SESSION_COOKIE } from "../lib/session-name";
import { createSession } from "../lib/session-token";
import { ADMIN_BASE_PATH, adminPath } from "../lib/paths";
import { adminRedirectUrl } from "../lib/redirect-url";

export async function signIn(_: string | null, form: FormData) {
  const requestHeaders = await headers();
  const source = requestHeaders.get("x-forwarded-for") ?? "unknown";
  const attemptKey = createHash("sha256").update(source).digest("hex");
  if (!loginAttempts.reserve(attemptKey)) {
    return "Too many sign-in attempts. Please try again in 10 minutes.";
  }
  const expected = process.env.ADMIN_PANEL_PASSWORD ?? "";
  const given = String(form.get("password") ?? "");
  const givenBytes = Buffer.from(given);
  const expectedBytes = Buffer.from(expected);
  const same =
    expected.length > 0 &&
    givenBytes.length === expectedBytes.length &&
    timingSafeEqual(givenBytes, expectedBytes);
  if (!same) {
    await new Promise((r) => setTimeout(r, 1000));
    return "Incorrect password.";
  }
  (await cookies()).set(SESSION_COOKIE, await createSession(), {
    httpOnly: true,
    sameSite: "strict",
    secure: process.env.NODE_ENV === "production",
    path: ADMIN_BASE_PATH,
    maxAge: 12 * 3600,
  });
  loginAttempts.clear(attemptKey);
  redirect(await adminRedirectUrl("/"));
}

export async function signOut() {
  (await cookies()).set(SESSION_COOKIE, "", {
    httpOnly: true,
    sameSite: "strict",
    secure: process.env.NODE_ENV === "production",
    path: ADMIN_BASE_PATH,
    maxAge: 0,
  });
  redirect(await adminRedirectUrl("/login"));
}

export async function setUserActive(form: FormData) {
  await admin(`/users/${form.get("id")}/active`, {
    method: "PUT",
    body: { active: form.get("active") === "true" },
  });
  revalidatePath(adminPath("/"), "layout");
}

export async function replyToTicket(form: FormData) {
  const id = String(form.get("id"));
  await admin(`/support/tickets/${id}/reply`, {
    method: "POST",
    body: { body: String(form.get("body") ?? "") },
  });
  revalidatePath(adminPath(`/support/${id}`));
}

export async function setTicketStatus(form: FormData) {
  const id = String(form.get("id"));
  await admin(`/support/tickets/${id}/status`, {
    method: "PUT",
    body: { status: String(form.get("status")) },
  });
  revalidatePath(adminPath("/support"), "layout");
}
