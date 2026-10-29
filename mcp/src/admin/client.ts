import { lstat, readFile } from "node:fs/promises";
import { resolve } from "node:path";

export type Json = Record<string, any>;
export class AdminMcpError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly status?: number,
  ) {
    super(message);
  }
}

export type AdminConfig = {
  apiUrl: string;
  token?: string;
  workspaceApiKey?: string;
  templateAgentId?: string;
  templateVersion?: number;
  templateLanguage?: string;
  templateLanguagePath?: string;
  templateLanguageValue?: string;
};

/** An optional private file is loaded once, never printed or returned as a tool result. */
export async function loadAdminEnvironment(env = process.env) {
  const filename = env.BOOKINGOS_ADMIN_ENV_FILE;
  if (!filename) return;
  const path = resolve(filename);
  const stat = await lstat(path).catch((error: NodeJS.ErrnoException) => {
    if (error.code === "ENOENT") return undefined;
    throw error;
  });
  if (!stat) return;
  if (!stat.isFile() || stat.isSymbolicLink() || stat.mode & 0o077)
    throw new AdminMcpError(
      "CONFIG_REQUIRED",
      "The admin environment file must be a private regular file (mode 0600).",
    );
  const source = await readFile(path, "utf8");
  for (const line of source.split(/\r?\n/)) {
    const m = /^\s*([A-Z][A-Z0-9_]*)\s*=\s*(.*?)\s*$/.exec(line);
    if (!m || m[2].startsWith("#")) continue;
    let value = m[2];
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    )
      value = value.slice(1, -1);
    if (env[m[1]] === undefined) env[m[1]] = value;
  }
}

export function adminConfigFromEnv(env = process.env): AdminConfig {
  const url = new URL(
    env.BOOKINGOS_ADMIN_API_URL ??
      "https://scwwkaywewecspsrskft.supabase.co/functions/v1/booking-api/v1/admin-mcp/voice",
  );
  if (
    url.username ||
    url.password ||
    url.search ||
    url.hash ||
    (url.protocol !== "https:" &&
      !(
        url.protocol === "http:" &&
        ["127.0.0.1", "localhost", "[::1]"].includes(url.hostname)
      ))
  )
    throw new AdminMcpError(
      "CONFIG_REQUIRED",
      "Use an HTTPS BookingOS admin API URL, or a loopback development URL, without credentials/query/fragment.",
    );
  const version = env.BOOKINGOS_SARVAM_TEMPLATE_VERSION;
  if (version && (!/^\d+$/.test(version) || Number(version) < 1))
    throw new AdminMcpError(
      "CONFIG_REQUIRED",
      "BOOKINGOS_SARVAM_TEMPLATE_VERSION must be a committed positive version.",
    );
  return {
    apiUrl: url.toString().replace(/\/$/, ""),
    token: env.BOOKINGOS_ADMIN_MCP_TOKEN,
    workspaceApiKey: env.BOOKINGOS_SARVAM_WORKSPACE_API_KEY,
    templateAgentId: env.BOOKINGOS_SARVAM_TEMPLATE_AGENT_ID,
    templateVersion: version ? Number(version) : undefined,
    templateLanguage: env.BOOKINGOS_SARVAM_TEMPLATE_LANGUAGE,
    templateLanguagePath: env.BOOKINGOS_SARVAM_TEMPLATE_LANGUAGE_PATH,
    templateLanguageValue: env.BOOKINGOS_SARVAM_TEMPLATE_LANGUAGE_VALUE,
  };
}

/** Backend and provider responses are untrusted; never serialize credential-bearing fields. */
export function safeOutput(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(safeOutput);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value)
        .filter(
          ([key]) =>
            !/(?:^|_)(?:password|access_token|refresh_token|client_secret|tool_key|workspace_api_key|api_key|ciphertext|authorization|credential_value)(?:$|_)/i.test(
              key,
            ),
        )
        .map(([key, v]) => [key, safeOutput(v)]),
    );
  }
  if (typeof value === "string")
    return value
      .replace(/\b(?:bkv|bkam)_[A-Za-z0-9_-]+/g, "[redacted key]")
      .replace(/Bearer\s+\S+/gi, "Bearer [redacted]");
  return value;
}

export class AdminClient {
  constructor(
    readonly config: AdminConfig,
    private http: typeof fetch = fetch,
  ) {}
  async request<T = Json>(
    method: "GET" | "POST",
    path: string,
    body?: unknown,
    query?: Json,
  ): Promise<T> {
    if (!this.config.token)
      throw new AdminMcpError(
        "CONFIG_REQUIRED",
        "Install a scoped BOOKINGOS_ADMIN_MCP_TOKEN privately, then restart this MCP server.",
      );
    if (
      !/^\/(?:requests|jobs)(?:\/|$)/.test(path) ||
      path.includes("..") ||
      path.includes("?") ||
      path.includes("#")
    )
      throw new AdminMcpError(
        "FORBIDDEN",
        "This client permits only narrow voice administration routes.",
      );
    const url = new URL(this.config.apiUrl + path);
    for (const [key, value] of Object.entries(query ?? {}))
      if (value !== undefined) url.searchParams.set(key, String(value));
    let response: Response;
    try {
      response = await this.http(url, {
        method,
        redirect: "error",
        signal: AbortSignal.timeout(20000),
        headers: {
          authorization: `Bearer ${this.config.token}`,
          ...(body === undefined ? {} : { "content-type": "application/json" }),
        },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      });
    } catch {
      throw new AdminMcpError(
        "OUTCOME_UNKNOWN",
        "BookingOS did not confirm this request. Read the existing job before retrying with the same operation key.",
      );
    }
    if (!response.ok) {
      const fallback =
        response.status === 401
          ? "UNAUTHENTICATED"
          : response.status === 403
            ? "FORBIDDEN"
            : response.status === 409
              ? "STALE_PLAN"
              : response.status >= 500
                ? "OUTCOME_UNKNOWN"
                : "REQUEST_REJECTED";
      const error = await response.json().catch(() => null);
      const codes = [
        "UNAUTHENTICATED",
        "FORBIDDEN",
        "CONFIGURATION_REQUIRED",
        "CONNECTION_EXISTS",
        "INVALID_STEP",
        "LEASE_BUSY",
        "LEASE_EXPIRED",
        "NOT_FOUND",
        "NUMBER_IN_USE",
        "OUTCOME_UNKNOWN",
        "PROVIDER_AUTH_REQUIRED",
        "PROVIDER_CAPABILITY_MISSING",
        "PROVIDER_ERROR",
        "RESOURCE_MISMATCH",
        "STALE_PLAN",
        "VALIDATION_ERROR",
        "VERIFICATION_FAILED",
      ];
      const code =
        typeof error?.code === "string" && codes.includes(error.code)
          ? error.code
          : fallback;
      // Only the allowlisted code crosses this boundary; messages can echo private inputs.
      throw new AdminMcpError(
        code,
        `BookingOS voice administration returned HTTP ${response.status}. Refresh the request/job and check authorization or the selected plan.`,
        response.status,
      );
    }
    try {
      return (await response.json()) as T;
    } catch {
      throw new AdminMcpError(
        "OUTCOME_UNKNOWN",
        "BookingOS returned an unreadable result. Reconcile the existing job before retrying.",
      );
    }
  }
}
