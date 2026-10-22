import { createHash, createHmac, timingSafeEqual } from "node:crypto";
import {
  ServiceUnavailableException,
  UnauthorizedException,
} from "@nestjs/common";
import type { Actor } from "../common/auth.guard";

const verified = new WeakSet<Actor>();
const MAX_AGE = 60_000;

export function isPanelActor(actor: Actor) {
  return verified.has(actor);
}

/** A panel proof never grants access to owner/staff routes or Supabase Auth. */
export function panelActor(
  proof: string | null | undefined,
  method: string,
  path: string,
  body: unknown,
): Actor {
  const secret = process.env.ADMIN_SESSION_SECRET;
  if (!secret || secret.length < 32)
    throw new ServiceUnavailableException(
      "Admin request signing is not configured.",
    );
  const match = /^(\d{13})\.([a-f0-9-]{36})\.([a-f0-9]{64})$/.exec(proof ?? "");
  if (!match || Math.abs(Date.now() - Number(match[1])) > MAX_AGE)
    throw new UnauthorizedException("Admin request is invalid or expired.");
  const [, timestamp, nonce, mac] = match;
  const digest = createHash("sha256")
    .update(body === undefined ? "" : JSON.stringify(body))
    .digest("hex");
  const expected = createHmac("sha256", secret)
    .update(
      ["booking-admin-v1", timestamp, nonce, method, path, digest].join("\n"),
    )
    .digest();
  if (!timingSafeEqual(expected, Buffer.from(mac, "hex")))
    throw new UnauthorizedException("Admin request is invalid or expired.");
  const actor = {
    uid: "admin-panel",
    email: "admin-panel@bookingos.internal",
    name: "Platform admin",
  };
  verified.add(actor);
  return actor;
}
