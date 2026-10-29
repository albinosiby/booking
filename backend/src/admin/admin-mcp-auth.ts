import { createHash } from "node:crypto";
import {
  ForbiddenException,
  Injectable,
  UnauthorizedException,
} from "@nestjs/common";
import type { Actor } from "../common/auth.guard";
import { Database } from "../common/database";

export const ADMIN_MCP_SCOPES = [
  "voice:read",
  "voice:write",
  "voice:credentials:install",
] as const;
export type AdminMcpScope = (typeof ADMIN_MCP_SCOPES)[number];
type Principal = { id: string; scopes: AdminMcpScope[] };
const principals = new WeakMap<Actor, Principal>();
export const hashAdminMcpToken = (token: string) =>
  createHash("sha256").update(token).digest("hex");

/** The bearer token is intentionally unrelated to panel cookies and signing keys. */
@Injectable()
export class AdminMcpAuthService {
  constructor(private readonly db: Database) {}

  async authenticate(
    authorization: string | null | undefined,
    scope: AdminMcpScope,
  ): Promise<Actor> {
    const token = /^Bearer (bkam_[A-Za-z0-9_-]{43})$/.exec(
      authorization ?? "",
    )?.[1];
    if (!token)
      throw new UnauthorizedException("Admin MCP authorization is required.");
    const row = (
      await this.db.query<{
        id: string;
        name: string;
        operator_email: string;
        scopes: AdminMcpScope[];
      }>(
        `UPDATE admin_mcp_credentials SET last_used_at=now()
        WHERE token_hash=$1 AND revoked_at IS NULL AND expires_at>now()
        RETURNING id,name,operator_email,scopes`,
        [hashAdminMcpToken(token)],
      )
    ).rows[0];
    if (!row)
      throw new UnauthorizedException(
        "Admin MCP authorization is invalid or expired.",
      );
    if (!row.scopes.includes(scope))
      throw new ForbiddenException("Admin MCP scope is not allowed.");
    const actor: Actor = {
      uid: `admin-mcp:${row.id}`,
      email: row.operator_email,
      name: row.name,
    };
    principals.set(actor, { id: row.id, scopes: row.scopes });
    return actor;
  }
}

export function requireAdminMcpScope(actor: Actor, scope: AdminMcpScope) {
  const principal = principals.get(actor);
  if (!principal)
    throw new UnauthorizedException("Admin MCP authorization is required.");
  if (!principal.scopes.includes(scope))
    throw new ForbiddenException("Admin MCP scope is not allowed.");
  return principal;
}

/** Only these voice endpoints accept this credential; broad admin routes do not. */
export function voiceScopeForRequest(
  method: string,
  path: string,
): AdminMcpScope | undefined {
  const prefix = "/v1/admin-mcp/voice";
  if (!path.startsWith(prefix + "/")) return undefined;
  if (
    method === "GET" &&
    (/^\/requests(?:\/[^/]+)?$/.test(path.slice(prefix.length)) ||
      /^\/jobs\/[^/]+$/.test(path.slice(prefix.length)))
  )
    return "voice:read";
  if (
    method === "POST" &&
    /^\/jobs\/[^/]+\/credential$/.test(path.slice(prefix.length))
  )
    return "voice:credentials:install";
  if (
    method === "POST" &&
    (/^\/requests\/[^/]+\/(prepare|start|pause)$/.test(
      path.slice(prefix.length),
    ) ||
      /^\/jobs\/[^/]+\/(claim|checkpoint|release|verify|activate)$/.test(
        path.slice(prefix.length),
      ))
  )
    return "voice:write";
  return undefined;
}
