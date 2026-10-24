import { NextRequest, NextResponse } from "next/server";
import { admin, ApiError } from "../../../../../lib/api";
import { adminPath } from "../../../../../lib/paths";
import { adminRedirectUrl } from "../../../../../lib/redirect-url";
const headers = {
  "Cache-Control": "no-store",
  "Referrer-Policy": "no-referrer",
  "Content-Security-Policy":
    "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'",
  "X-Content-Type-Options": "nosniff",
};
function escape(value: string) {
  return value.replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ]!,
  );
}
// The admin cookie is SameSite=Strict. A same-origin Continue POST restores it
// after the external SSO return without weakening the panel's session policy.
export async function GET(req: NextRequest) {
  const fields = ["state", "code", "error", "iss"]
    .filter((k) => req.nextUrl.searchParams.has(k))
    .map(
      (k) =>
        `<input type="hidden" name="${k}" value="${escape(req.nextUrl.searchParams.get(k)!.slice(0, 4000))}">`,
    )
    .join("");
  return new NextResponse(
    `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Return to BookingOS</title><body style="font:16px system-ui;max-width:520px;margin:12vh auto;padding:24px"><h1>Return to BookingOS</h1><p>Continue to complete Sarvam authorization in your admin session.</p><form method="post" action="${adminPath("/agent-requests/mcp/callback")}">${fields}<button style="padding:12px 18px">Continue to admin panel</button></form></body></html>`,
    { headers: { ...headers, "Content-Type": "text/html; charset=utf-8" } },
  );
}
export async function POST(req: NextRequest) {
  const form = await req.formData();
  const input = Object.fromEntries(
    ["state", "code", "error", "iss"]
      .filter((k) => form.has(k))
      .map((k) => [k, String(form.get(k))]),
  );
  try {
    await admin("/sarvam/callback", { method: "POST", body: input });
  } catch (e) {
    if (e instanceof ApiError)
      return NextResponse.redirect(
        await adminRedirectUrl("/agent-requests/mcp?error=authorization"),
        { status: 303, headers },
      );
    throw e;
  }
  return NextResponse.redirect(
    await adminRedirectUrl("/agent-requests/mcp?connected=1"),
    { status: 303, headers },
  );
}
