import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, rm, stat, chmod, readFile, symlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createHash } from "node:crypto";
import {
  SARVAM_MCP_URL,
  SarvamTokenStore,
  ProviderAuthRequiredError,
  ProviderLoginError,
  createSarvamClient,
  loginSarvam,
  sarvamFetch,
} from "../src/admin/sarvam-auth.js";

const json = (value: unknown, status = 200) =>
  new Response(JSON.stringify(value), {
    status,
    headers: { "content-type": "application/json" },
  });
// Parallel backend suites can saturate the host; keep the mock callback deadline
// generous without changing state, PKCE, issuer or credential-store assertions.
const MOCK_LOGIN_TIMEOUT_MS = 10_000;
async function fixture() {
  const directory = await mkdtemp(join(tmpdir(), "bookingos-auth-"));
  return {
    directory,
    path: join(directory, "tokens.json"),
    cleanup: () => rm(directory, { recursive: true, force: true }),
  };
}
function saved(expiresAt = Date.now() + 3600_000) {
  return {
    version: 1 as const,
    server: SARVAM_MCP_URL as typeof SARVAM_MCP_URL,
    tokens: {
      access_token: "fixture-private-token",
      token_type: "Bearer",
      expires_in: 3600,
      issuer: SARVAM_MCP_URL,
    },
    expiresAt,
  };
}

test("private store is atomic and safe status never includes a token", async () => {
  const f = await fixture();
  try {
    const store = new SarvamTokenStore(f.path);
    assert.deepEqual(await store.status(), {
      authorized: false,
      login_required: true,
    });
    await store.save(saved());
    assert.equal((await stat(f.path)).mode & 0o777, 0o600);
    const status = await store.status();
    assert.equal(status.authorized, true);
    assert.equal(
      JSON.stringify(status).includes("fixture-private-token"),
      false,
    );
    await store.save(saved(Date.now() - 1));
    assert.equal((await store.status()).login_required, true);
    await store.remove();
    assert.equal((await store.status()).authorized, false);
  } finally {
    await f.cleanup();
  }
});

test("store refuses permissive files and symbolic links", async () => {
  const f = await fixture();
  try {
    const store = new SarvamTokenStore(f.path);
    await store.save(saved());
    await chmod(f.path, 0o644);
    await assert.rejects(store.load(), /0600/);
    await chmod(f.path, 0o600);
    const linked = new SarvamTokenStore(join(f.directory, "link.json"));
    await symlink(f.path, linked.path);
    await assert.rejects(linked.load(), ProviderLoginError);
  } finally {
    await f.cleanup();
  }
});

test("normal tool startup with missing or expired auth never starts a login or sends a request", async () => {
  const f = await fixture();
  let calls = 0;
  const http: typeof fetch = async () => {
    calls++;
    throw new Error("unexpected");
  };
  try {
    await assert.rejects(
      createSarvamClient({ tokenFile: f.path, http }),
      ProviderAuthRequiredError,
    );
    await new SarvamTokenStore(f.path).save(saved(Date.now() - 1));
    await assert.rejects(
      createSarvamClient({ tokenFile: f.path, http }),
      ProviderAuthRequiredError,
    );
    assert.equal(calls, 0);
  } finally {
    await f.cleanup();
  }
});

test("programmatic provider fetch blocks other origins before transmitting and refuses redirects", async () => {
  let calls = 0;
  const guarded = sarvamFetch(async (_input, init) => {
    calls++;
    assert.equal(init?.redirect, "error");
    return new Response(null, {
      status: 302,
      headers: { location: "https://example.org" },
    });
  });
  await assert.rejects(
    guarded("https://example.org/token", {
      headers: { authorization: "Bearer fixture-private-token" },
    }),
    ProviderLoginError,
  );
  assert.equal(calls, 0);
  await assert.rejects(guarded(SARVAM_MCP_URL), /redirected/);
  assert.equal(calls, 1);
});

function oauthServer() {
  const calls: { url: string; body?: unknown }[] = [];
  let challenge = "";
  const http: typeof fetch = async (input, init) => {
    const url = String(input);
    calls.push({ url, body: init?.body });
    if (url.includes("oauth-protected-resource"))
      return json({
        resource: SARVAM_MCP_URL,
        authorization_servers: [SARVAM_MCP_URL],
      });
    if (url.includes("oauth-authorization-server"))
      return json({
        issuer: SARVAM_MCP_URL,
        authorization_endpoint: `${SARVAM_MCP_URL}/authorize`,
        token_endpoint: `${SARVAM_MCP_URL}/token`,
        registration_endpoint: `${SARVAM_MCP_URL}/register`,
        response_types_supported: ["code"],
        grant_types_supported: ["authorization_code"],
        token_endpoint_auth_methods_supported: ["none"],
        code_challenge_methods_supported: ["S256"],
        authorization_response_iss_parameter_supported: true,
      });
    if (url.endsWith("/register"))
      return json(
        {
          ...JSON.parse(String(init?.body)),
          client_id: "registered-test-client",
        },
        201,
      );
    if (url.endsWith("/token")) {
      const params = new URLSearchParams(String(init?.body));
      assert.equal(params.get("code"), "fixture-code");
      assert.equal(params.get("resource"), SARVAM_MCP_URL);
      assert.equal(
        createHash("sha256")
          .update(params.get("code_verifier")!)
          .digest("base64url"),
        challenge,
      );
      return json({
        access_token: "fixture-private-token",
        token_type: "Bearer",
        expires_in: 86400,
      });
    }
    throw new Error(`Unexpected fixture URL ${url}`);
  };
  return {
    calls,
    http,
    setChallenge(value: string) {
      challenge = value;
    },
  };
}

test("explicit login verifies state and PKCE and saves a separate private token", async () => {
  const f = await fixture();
  const server = oauthServer();
  try {
    const result = await loginSarvam({
      tokenFile: f.path,
      port: 0,
      http: server.http,
      timeoutMs: MOCK_LOGIN_TIMEOUT_MS,
      async onAuthorizationUrl(url) {
        assert.equal(url.origin, "https://mcp.sarvam.ai");
        assert.equal(url.searchParams.get("code_challenge_method"), "S256");
        server.setChallenge(url.searchParams.get("code_challenge")!);
        const callback = new URL(url.searchParams.get("redirect_uri")!);
        callback.searchParams.set("state", "incorrect-state");
        callback.searchParams.set("code", "fixture-code");
        assert.equal((await fetch(callback)).status, 400);
        assert.equal(
          server.calls.filter((c) => c.url.endsWith("/token")).length,
          0,
        );
        callback.searchParams.set("state", url.searchParams.get("state")!);
        callback.searchParams.set("iss", SARVAM_MCP_URL);
        assert.equal((await fetch(callback)).status, 200);
      },
    });
    assert.equal(result.authorized, true);
    assert.equal(
      server.calls.filter((c) => c.url.endsWith("/token")).length,
      1,
    );
    assert.equal((await stat(f.path)).mode & 0o777, 0o600);
    assert.equal(
      JSON.stringify(result).includes("fixture-private-token"),
      false,
    );
    assert.equal(
      (await new SarvamTokenStore(f.path).load()).tokens?.access_token,
      "fixture-private-token",
    );
    assert.equal(
      (await readFile(f.path, "utf8")).includes("code_verifier"),
      false,
    );
  } finally {
    await f.cleanup();
  }
});

test("issuer mismatch never exchanges the authorization code", async () => {
  const f = await fixture();
  const server = oauthServer();
  try {
    await assert.rejects(
      loginSarvam({
        tokenFile: f.path,
        port: 0,
        http: server.http,
        timeoutMs: MOCK_LOGIN_TIMEOUT_MS,
        async onAuthorizationUrl(url) {
          const callback = new URL(url.searchParams.get("redirect_uri")!);
          callback.searchParams.set("state", url.searchParams.get("state")!);
          callback.searchParams.set("code", "fixture-code");
          callback.searchParams.set("iss", "https://example.org");
          assert.equal((await fetch(callback)).status, 400);
        },
      }),
      /issuer/,
    );
    assert.equal(
      server.calls.filter((c) => c.url.endsWith("/token")).length,
      0,
    );
    assert.equal(
      (await new SarvamTokenStore(f.path).status()).authorized,
      false,
    );
  } finally {
    await f.cleanup();
  }
});

test("provider registration errors are redacted instead of echoing credentials", async () => {
  const f = await fixture();
  const server = oauthServer();
  let registrations = 0;
  const http: typeof fetch = async (input, init) => {
    if (String(input).endsWith("/register")) {
      registrations++;
      return json(
        {
          error: "invalid_redirect_uri",
          error_description: "fixture-private-token raw provider details",
        },
        400,
      );
    }
    return server.http(input, init);
  };
  try {
    await assert.rejects(
      loginSarvam({
        tokenFile: f.path,
        port: 0,
        http,
        timeoutMs: MOCK_LOGIN_TIMEOUT_MS,
        onAuthorizationUrl() {
          throw new Error("not reached");
        },
      }),
      (error) => {
        assert.equal(error instanceof ProviderLoginError, true);
        assert.equal(String(error).includes("fixture-private-token"), false);
        return true;
      },
    );
    assert.equal(registrations, 1);
  } finally {
    await f.cleanup();
  }
});
