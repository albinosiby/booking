import { createHash, timingSafeEqual } from "node:crypto";
import {
  Injectable,
  ForbiddenException,
  ConflictException,
} from "@nestjs/common";
import { z } from "zod";
import { Database } from "../common/database";
import type { Actor } from "../common/auth.guard";

const registration = z
  .object({
    installation_id: z.uuid(),
    installation_secret: z.string().regex(/^[a-f0-9]{64}$/),
    token: z.string().min(20).max(4096),
    platform: z.enum(["android", "ios"]),
  })
  .strict();
const proof = z
  .object({ installation_secret: registration.shape.installation_secret })
  .strict();
function hash(value: string) {
  return createHash("sha256").update(value).digest("hex");
}
function matches(value: string, expected: string) {
  return timingSafeEqual(
    Buffer.from(hash(value), "hex"),
    Buffer.from(expected, "hex"),
  );
}

@Injectable()
export class NotificationService {
  constructor(private readonly db: Database) {}

  async register(actor: Actor, input: unknown) {
    const v = registration.parse(input);
    if (actor.uid.startsWith("sarvam:"))
      throw new ForbiddenException("User session required.");
    return this.db.transaction(async (db) => {
      // Serializes the first registration too, when no row exists to lock yet.
      await db.query("SELECT pg_advisory_xact_lock(hashtext($1))", [
        v.installation_id,
      ]);
      const old = (
        await db.query<{ id: string; proof_hash: string }>(
          "SELECT id,proof_hash FROM notification_devices WHERE id=$1 FOR UPDATE",
          [v.installation_id],
        )
      ).rows[0];
      if (old && !matches(v.installation_secret, old.proof_hash))
        throw new ForbiddenException("Installation proof is invalid.");
      const collision = (
        await db.query<{ id: string }>(
          "SELECT id FROM notification_devices WHERE token=$1 AND id<>$2",
          [v.token, v.installation_id],
        )
      ).rows[0];
      if (collision)
        throw new ConflictException(
          "Refresh this device's notification registration.",
        );
      await db.query(
        `INSERT INTO notification_devices(id,user_id,proof_hash,token,platform)
         VALUES($1,$2,$3,$4,$5)
         ON CONFLICT(id) DO UPDATE SET user_id=EXCLUDED.user_id,token=EXCLUDED.token,platform=EXCLUDED.platform,
         version=CASE WHEN notification_devices.token<>EXCLUDED.token OR notification_devices.user_id<>EXCLUDED.user_id OR NOT notification_devices.enabled THEN notification_devices.version+1 ELSE notification_devices.version END,
         bound_at=CASE WHEN notification_devices.user_id<>EXCLUDED.user_id OR NOT notification_devices.enabled THEN now() ELSE notification_devices.bound_at END,
         enabled=true,updated_at=now(),last_seen_at=now()`,
        [
          v.installation_id,
          actor.uid,
          hash(v.installation_secret),
          v.token,
          v.platform,
        ],
      );
      return { id: v.installation_id, registered: true };
    });
  }

  async unregister(actor: Actor, id: string, input: unknown) {
    z.uuid().parse(id);
    const v = proof.parse(input);
    return this.disable(id, v.installation_secret, actor.uid);
  }

  /** Allows a logged-out installation to finish its own previously failed unlink. */
  async revokeInstallation(input: unknown) {
    const v = proof.extend({ installation_id: z.uuid() }).parse(input);
    return this.disable(v.installation_id, v.installation_secret);
  }

  private async disable(id: string, secret: string, userId?: string) {
    // The proof is an unguessable 256-bit device credential; never return token/account data.
    await this.db.query(
      `UPDATE notification_devices SET enabled=false,version=version+1,updated_at=now()
       WHERE id=$1 AND proof_hash=$2 AND ($3::text IS NULL OR user_id=$3) AND enabled`,
      [id, hash(secret), userId ?? null],
    );
    return { unregistered: true };
  }
}
