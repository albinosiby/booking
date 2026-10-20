import {
  UnauthorizedException,
  ServiceUnavailableException,
} from "@nestjs/common";
import type { Queryable } from "./database";
import type { Actor } from "./auth.guard";

interface SupabaseUser {
  id: string;
  email?: string;
  email_confirmed_at?: string | null;
  is_anonymous?: boolean;
  user_metadata?: { full_name?: unknown };
}

/** Validate with the Auth server; client metadata never grants permissions. */
export async function supabaseActor(
  accessToken: string,
  db: Queryable,
  request: typeof fetch = fetch,
  configuration = {
    url: process.env.SUPABASE_URL,
    key: process.env.SUPABASE_PUBLISHABLE_KEY,
  },
): Promise<Actor> {
  const { url, key } = configuration;
  if (!url?.startsWith("https://") || !key?.startsWith("sb_publishable_"))
    throw new ServiceUnavailableException("Authentication is not configured.");
  let response: Response;
  try {
    response = await request(`${url.replace(/\/$/, "")}/auth/v1/user`, {
      headers: { apikey: key, Authorization: `Bearer ${accessToken}` },
      signal: AbortSignal.timeout(10000),
    });
  } catch {
    throw new ServiceUnavailableException(
      "Cannot reach authentication. Please try again.",
    );
  }
  if (response.status >= 500 || response.status === 429)
    throw new ServiceUnavailableException(
      "Authentication is temporarily unavailable.",
    );
  if (!response.ok)
    throw new UnauthorizedException("Your session expired. Sign in again.");
  const user = (await response.json()) as SupabaseUser;
  if (!user.id || !user.email || user.is_anonymous || !user.email_confirmed_at)
    throw new UnauthorizedException("Verify your email before continuing.");
  const email = user.email.toLowerCase();
  // Only trusted migration code inserts claims. A verified email can bind its
  // original actor once; changing user metadata cannot claim organization access.
  const existing = await db.query<{
    actor_id: string;
    email: string;
    supabase_subject: string | null;
  }>(
    "SELECT actor_id,email,supabase_subject FROM migrated_identities WHERE supabase_subject=$1 OR email=$2",
    [user.id, email],
  );
  const claim = existing.rows.find((row) => row.email === email);
  let uid: string;
  if (claim?.supabase_subject === user.id) {
    // The normal path is read-only: do not rewrite and lock an already-linked
    // account for every parallel page, availability and quote request.
    uid = claim.actor_id;
  } else if (claim) {
    if (claim.supabase_subject !== null)
      throw new UnauthorizedException(
        "This migrated account is already linked. Contact your owner.",
      );
    const bound = await db.query<{ actor_id: string }>(
      `UPDATE migrated_identities SET supabase_subject=$1
       WHERE email=$2 AND (supabase_subject IS NULL OR supabase_subject=$1)
       RETURNING actor_id`,
      [user.id, email],
    );
    // A concurrent request may bind first; the conditional write accepts only
    // that same verified subject, never a different claimant.
    if (!bound.rows[0])
      throw new UnauthorizedException(
        "This migrated account is already linked. Contact your owner.",
      );
    uid = bound.rows[0].actor_id;
  } else {
    // A verified identity keeps its original actor after an email change.
    uid =
      existing.rows.find((row) => row.supabase_subject === user.id)?.actor_id ??
      user.id;
  }
  return {
    uid,
    email,
    name:
      typeof user.user_metadata?.full_name === "string"
        ? user.user_metadata.full_name
        : email.split("@")[0],
  };
}
