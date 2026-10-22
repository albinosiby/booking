import { createHash, createHmac, randomUUID } from "node:crypto";

/** Server-to-server proof, scoped to one API request and separate from cookies. */
export function signAdminRequest(method: string, path: string, body = "") {
  const secret = process.env.ADMIN_SESSION_SECRET;
  if (!secret || secret.length < 32)
    throw new Error("ADMIN_SESSION_SECRET must contain at least 32 characters.");
  const timestamp = String(Date.now());
  const nonce = randomUUID();
  const digest = createHash("sha256").update(body).digest("hex");
  const signature = createHmac("sha256", secret)
    .update(["booking-admin-v1", timestamp, nonce, method, path, digest].join("\n"))
    .digest("hex");
  return `${timestamp}.${nonce}.${signature}`;
}
