import "server-only";
import { headers } from "next/headers";
import { adminPath } from "./paths";

/** Absolute URLs work for both enhanced Server Actions and ordinary HTML forms. */
export async function adminRedirectUrl(path: string) {
  const values = await headers();
  const host = values.get("x-forwarded-host") || values.get("host");
  const protocol = values.get("x-forwarded-proto") || "http";
  if (!host || !["http", "https"].includes(protocol))
    throw new Error("Invalid admin request origin.");
  return new URL(adminPath(path), `${protocol}://${host}`).toString();
}
