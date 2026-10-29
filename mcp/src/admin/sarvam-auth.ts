import { constants } from "node:fs";
import { open, mkdir, lstat, rename, unlink } from "node:fs/promises";
import { createServer, type Server } from "node:http";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { randomBytes, timingSafeEqual } from "node:crypto";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import {
  auth,
  type OAuthClientProvider,
  type OAuthDiscoveryState,
} from "@modelcontextprotocol/sdk/client/auth.js";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";
import {
  OAuthClientInformationFullSchema,
  OAuthClientInformationSchema,
  OAuthTokensSchema,
  type OAuthClientInformationMixed,
  type OAuthTokens,
} from "@modelcontextprotocol/sdk/shared/auth.js";
import { z } from "zod";

export const SARVAM_MCP_URL = "https://mcp.sarvam.ai/voice-agents";
const PROVIDER_ORIGIN = new URL(SARVAM_MCP_URL).origin;
export const DEFAULT_SARVAM_TOKEN_FILE = join(
  homedir(),
  ".config",
  "bookingos-admin",
  "sarvam-oauth.json",
);
export const DEFAULT_SARVAM_CALLBACK_PORT = 42827;

export class ProviderAuthRequiredError extends Error {
  readonly code = "PROVIDER_AUTH_REQUIRED";
  constructor() {
    super(
      "Sarvam authorization is missing or expired. Run the BookingOS admin Sarvam login command, then resume the same setup job.",
    );
  }
}
export class ProviderLoginError extends Error {
  readonly code = "PROVIDER_AUTH_FAILED";
  constructor(
    message = "Sarvam sign-in could not complete. Check that this workspace permits a loopback OAuth callback; if registration is restricted, configure its approved client ID and issuer.",
  ) {
    super(message);
  }
}

const SavedSchema = z.object({
  version: z.literal(1),
  server: z.literal(SARVAM_MCP_URL),
  client: z
    .union([OAuthClientInformationFullSchema, OAuthClientInformationSchema])
    .optional(),
  tokens: OAuthTokensSchema.optional(),
  expiresAt: z.number().finite().nonnegative().optional(),
  redirectUrl: z.string().url().optional(),
});
type Saved = z.infer<typeof SavedSchema>;
export type SarvamAuthStatus = {
  authorized: boolean;
  expires_at?: string;
  login_required: boolean;
};

/** A private store owned by this integration, never Codex's OAuth credential store. */
export class SarvamTokenStore {
  constructor(readonly path = DEFAULT_SARVAM_TOKEN_FILE) {}
  async load(): Promise<Saved> {
    let handle;
    try {
      handle = await open(this.path, constants.O_RDONLY | constants.O_NOFOLLOW);
      const stat = await handle.stat();
      if (
        !stat.isFile() ||
        stat.mode & 0o077 ||
        (process.getuid && stat.uid !== process.getuid()) ||
        stat.size > 64 * 1024
      )
        throw new ProviderLoginError(
          "Sarvam token file must be a private, owner-controlled regular file (0600).",
        );
      const saved = SavedSchema.parse(
        JSON.parse(await handle.readFile("utf8")),
      );
      if (saved.tokens?.issuer) assertProviderUrl(saved.tokens.issuer);
      if (saved.client?.issuer) assertProviderUrl(saved.client.issuer);
      return saved;
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT")
        return { version: 1, server: SARVAM_MCP_URL };
      if (error instanceof ProviderLoginError) throw error;
      throw new ProviderLoginError(
        "Sarvam token file is invalid or cannot be read safely. Remove it with the logout command and sign in again.",
      );
    } finally {
      await handle?.close();
    }
  }
  async save(value: Saved) {
    const saved = SavedSchema.parse(value);
    const serialized = JSON.stringify(saved);
    if (Buffer.byteLength(serialized) > 64 * 1024)
      throw new ProviderLoginError(
        "Sarvam returned an unexpectedly large credential record.",
      );
    const directory = dirname(this.path);
    await mkdir(directory, { recursive: true, mode: 0o700 });
    const stat = await lstat(directory);
    if (
      !stat.isDirectory() ||
      stat.isSymbolicLink() ||
      stat.mode & 0o077 ||
      (process.getuid && stat.uid !== process.getuid())
    )
      throw new ProviderLoginError(
        "Use a private, owner-controlled directory (0700) for the Sarvam token file.",
      );
    const temporary = join(
      directory,
      `.sarvam-${randomBytes(12).toString("hex")}.tmp`,
    );
    let handle;
    try {
      handle = await open(
        temporary,
        constants.O_WRONLY |
          constants.O_CREAT |
          constants.O_EXCL |
          constants.O_NOFOLLOW,
        0o600,
      );
      await handle.writeFile(serialized);
      await handle.sync();
      await handle.close();
      handle = undefined;
      await rename(temporary, this.path);
    } finally {
      await handle?.close();
      await unlink(temporary).catch(() => undefined);
    }
  }
  async remove() {
    await unlink(this.path).catch((error) => {
      if (error.code !== "ENOENT")
        throw new ProviderLoginError("Sarvam token file could not be removed.");
    });
  }
  async status(now = Date.now()): Promise<SarvamAuthStatus> {
    const saved = await this.load();
    const authorized =
      !!saved.tokens?.access_token &&
      !!saved.expiresAt &&
      saved.expiresAt > now + 60_000;
    return {
      authorized,
      login_required: !authorized,
      ...(saved.expiresAt
        ? { expires_at: new Date(saved.expiresAt).toISOString() }
        : {}),
    };
  }
}

function assertProviderUrl(value: string | URL) {
  const url = new URL(String(value));
  if (
    url.origin !== PROVIDER_ORIGIN ||
    url.username ||
    url.password ||
    url.hash
  )
    throw new ProviderLoginError(
      "Sarvam OAuth metadata referenced an unexpected origin.",
    );
  return url;
}

/** No redirects, cookies, tokens in URLs, or credentials sent outside the fixed provider origin. */
export function sarvamFetch(http: typeof fetch = fetch): typeof fetch {
  return async (input, init) => {
    assertProviderUrl(input instanceof Request ? input.url : String(input));
    const response = await http(input, {
      ...init,
      redirect: "error",
      signal: init?.signal ?? AbortSignal.timeout(20_000),
    });
    if (response.status >= 300 && response.status < 400)
      throw new ProviderLoginError(
        "Sarvam unexpectedly redirected a programmatic request.",
      );
    return response;
  };
}

/** Noninteractive factory: never starts OAuth or launches a browser during a tool call. */
export async function createSarvamClient(
  options: { tokenFile?: string; http?: typeof fetch } = {},
) {
  const store = new SarvamTokenStore(options.tokenFile);
  const saved = await store.load();
  if (
    !saved.tokens?.access_token ||
    !saved.expiresAt ||
    saved.expiresAt <= Date.now() + 60_000
  )
    throw new ProviderAuthRequiredError();
  const checkedFetch = sarvamFetch(options.http);
  const client = new Client({
    name: "bookingos-admin-private-installer",
    version: "1.0.0",
  });
  const transport = new StreamableHTTPClientTransport(new URL(SARVAM_MCP_URL), {
    requestInit: {
      headers: { Authorization: `Bearer ${saved.tokens.access_token}` },
      redirect: "error",
    },
    fetch: async (input, init) => {
      const response = await checkedFetch(input, init);
      if (response.status === 401 || response.status === 403)
        throw new ProviderAuthRequiredError();
      return response;
    },
    reconnectionOptions: {
      maxRetries: 0,
      initialReconnectionDelay: 1000,
      maxReconnectionDelay: 1000,
      reconnectionDelayGrowFactor: 1,
    },
  });
  try {
    await client.connect(transport);
  } catch (error) {
    await transport.close().catch(() => undefined);
    if (
      error instanceof ProviderAuthRequiredError ||
      /PROVIDER_AUTH_REQUIRED|authorization is missing or expired/.test(
        String(error),
      )
    )
      throw new ProviderAuthRequiredError();
    throw new ProviderLoginError(
      "Sarvam MCP could not connect. Check its availability and sign-in, then retry the same operation.",
    );
  }
  return {
    client,
    close: async () => {
      await client.close();
    },
  };
}

type LoginOptions = {
  tokenFile?: string;
  port?: number;
  clientId?: string;
  clientSecret?: string;
  issuer?: string;
  onAuthorizationUrl: (url: URL) => void | Promise<void>;
  http?: typeof fetch;
  timeoutMs?: number;
};

/** Explicit user-run login. PKCE is supplied by the SDK; state and optional issuer are checked locally. */
export async function loginSarvam(
  options: LoginOptions,
): Promise<SarvamAuthStatus> {
  const store = new SarvamTokenStore(options.tokenFile);
  const saved = await store.load();
  const state = randomBytes(32).toString("base64url");
  let verifier = "";
  let discovery: OAuthDiscoveryState | undefined;
  let redirectUrl = "";
  let client: OAuthClientInformationMixed | undefined = saved.client;
  let tokens: OAuthTokens | undefined;
  let resolveCode!: (code: string) => void;
  let rejectCode!: (error: Error) => void;
  const codeReady = new Promise<string>((resolve, reject) => {
    resolveCode = resolve;
    rejectCode = reject;
  });
  // A timeout or provider failure can arrive before we begin awaiting the callback.
  void codeReady.catch(() => undefined);
  if (options.clientSecret && !options.clientId)
    throw new ProviderLoginError(
      "A pre-registered client secret also requires its approved client ID.",
    );
  if (options.clientId) {
    const issuer = assertProviderUrl(
      options.issuer ?? SARVAM_MCP_URL,
    ).toString();
    client = {
      client_id: options.clientId,
      ...(options.clientSecret ? { client_secret: options.clientSecret } : {}),
      issuer,
    };
  }
  const server = createServer((request, response) => {
    const finish = (status: number, message: string) => {
      response.writeHead(status, {
        "Content-Type": "text/plain; charset=utf-8",
        "Cache-Control": "no-store",
        "Referrer-Policy": "no-referrer",
        "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'",
      });
      response.end(message);
    };
    let callback: URL;
    try {
      callback = new URL(request.url ?? "", redirectUrl);
    } catch {
      return finish(400, "Invalid sign-in callback.");
    }
    if (
      request.method !== "GET" ||
      callback.pathname !== "/callback" ||
      request.headers.host !== new URL(redirectUrl).host
    )
      return finish(404, "Not found.");
    const received = callback.searchParams.get("state") ?? "";
    if (
      received.length !== state.length ||
      !timingSafeEqual(Buffer.from(received), Buffer.from(state))
    )
      return finish(
        400,
        "Sign-in state did not match. Return to the login command.",
      );
    const expectedIssuer = discovery?.authorizationServerMetadata?.issuer;
    const metadata = discovery?.authorizationServerMetadata as
      (Record<string, unknown> & { issuer?: string }) | undefined;
    const requiresIssuer =
      metadata?.authorization_response_iss_parameter_supported === true;
    const receivedIssuer = callback.searchParams.get("iss");
    if (
      (requiresIssuer && !receivedIssuer) ||
      (receivedIssuer && receivedIssuer !== expectedIssuer)
    ) {
      rejectCode(
        new ProviderLoginError("Sarvam returned an unexpected OAuth issuer."),
      );
      return finish(400, "Sign-in issuer did not match.");
    }
    if (callback.searchParams.has("error")) {
      rejectCode(
        new ProviderLoginError(
          "Sarvam sign-in was declined or could not complete.",
        ),
      );
      return finish(
        400,
        "Sign-in was not completed. Return to the login command.",
      );
    }
    const code = callback.searchParams.get("code");
    if (!code || code.length > 8192)
      return finish(400, "Missing authorization code.");
    finish(
      200,
      "Sign-in received. Return to the BookingOS login command to confirm completion.",
    );
    resolveCode(code);
  });
  const port = options.port ?? DEFAULT_SARVAM_CALLBACK_PORT;
  if (!Number.isInteger(port) || port < 0 || port > 65535)
    throw new ProviderLoginError("Set a valid loopback callback port.");
  await listen(server, port);
  const address = server.address();
  if (!address || typeof address === "string") throw new ProviderLoginError();
  redirectUrl = `http://127.0.0.1:${address.port}/callback`;
  // DCR registrations may bind the exact redirect. Do not reuse one registered for a different port.
  if (!options.clientId && saved.redirectUrl !== redirectUrl)
    client = undefined;
  const provider: OAuthClientProvider = {
    redirectUrl,
    clientMetadata: {
      client_name: "BookingOS admin private credential installer",
      redirect_uris: [redirectUrl],
      grant_types: ["authorization_code"],
      response_types: ["code"],
      token_endpoint_auth_method: options.clientSecret
        ? "client_secret_basic"
        : "none",
    },
    state: () => state,
    clientInformation: () => client,
    saveClientInformation: (value) => {
      assertProviderUrl(value.issuer ?? SARVAM_MCP_URL);
      client = value;
    },
    tokens: () => undefined,
    saveTokens: (value) => {
      tokens = value;
    },
    redirectToAuthorization: async (url) => {
      assertProviderUrl(url);
      await options.onAuthorizationUrl(url);
    },
    saveCodeVerifier: (value) => {
      verifier = value;
    },
    codeVerifier: () => verifier,
    validateResourceURL: async (_server, resource) => {
      if (resource && resource !== SARVAM_MCP_URL)
        throw new ProviderLoginError(
          "Sarvam returned an unexpected protected resource.",
        );
      return new URL(SARVAM_MCP_URL);
    },
    saveDiscoveryState: (value) => {
      assertProviderUrl(value.authorizationServerUrl);
      for (const endpoint of [
        value.authorizationServerMetadata?.issuer,
        value.authorizationServerMetadata?.authorization_endpoint,
        value.authorizationServerMetadata?.token_endpoint,
        value.authorizationServerMetadata?.registration_endpoint,
        value.resourceMetadataUrl,
      ])
        if (endpoint) assertProviderUrl(endpoint);
      discovery = value;
    },
    discoveryState: () => discovery,
    invalidateCredentials: (scope) => {
      if (scope === "all" || scope === "client")
        client = options.clientId ? client : undefined;
      if (scope === "all" || scope === "discovery") discovery = undefined;
      if (scope === "all" || scope === "verifier") verifier = "";
    },
  };
  const timeout = setTimeout(
    () =>
      rejectCode(
        new ProviderLoginError(
          "Sarvam sign-in timed out. Run the login command again.",
        ),
      ),
    options.timeoutMs ?? 300_000,
  );
  timeout.unref();
  try {
    const result = await auth(provider, {
      serverUrl: SARVAM_MCP_URL,
      fetchFn: sarvamFetch(options.http),
    });
    if (result === "REDIRECT")
      await auth(provider, {
        serverUrl: SARVAM_MCP_URL,
        authorizationCode: await codeReady,
        fetchFn: sarvamFetch(options.http),
      });
    if (
      !tokens ||
      !client ||
      !tokens.expires_in ||
      tokens.expires_in <= 60 ||
      tokens.expires_in > 31 * 24 * 3600 ||
      tokens.token_type.toLowerCase() !== "bearer"
    )
      throw new ProviderLoginError(
        "Sarvam did not return a supported token lifetime and type.",
      );
    assertProviderUrl(tokens.issuer ?? SARVAM_MCP_URL);
    await store.save({
      version: 1,
      server: SARVAM_MCP_URL,
      client,
      tokens,
      expiresAt: Date.now() + tokens.expires_in * 1000,
      redirectUrl,
    });
    return store.status();
  } catch (error) {
    if (error instanceof ProviderLoginError) throw error;
    // Provider errors can echo a code, token, secret or request body; never expose them.
    throw new ProviderLoginError();
  } finally {
    clearTimeout(timeout);
    verifier = "";
    await close(server);
  }
}

function listen(server: Server, port: number) {
  return new Promise<void>((resolve, reject) => {
    server.once("error", () =>
      reject(
        new ProviderLoginError(
          "The private loopback callback port is unavailable. Stop the other login or choose an approved callback port.",
        ),
      ),
    );
    server.listen(port, "127.0.0.1", () => resolve());
  });
}
function close(server: Server) {
  return new Promise<void>((resolve) => {
    server.close(() => resolve());
    server.closeAllConnections();
  });
}
