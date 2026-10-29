# BookingOS admin MCP setup and operation

The `bookingos-admin` server lets Codex configure a client's saved call-service
request through APIs. It is separate from the owner/staff `eden-booking` server.
The admin server has no reservation-writing tools, and activating a connection
leaves client booking off until the client chooses spaces and enables it.

Codex can keep the official `sarvam-voice-agents` MCP connected for provider
inventory and diagnostics. The private installer inside `bookingos-admin` has its
own Sarvam authorization so it can transfer the generated tool key directly into
the provider secret store without returning the value to Codex.

## Install once on this computer

Use Node.js 24 and the reviewed repository checkout. Build the local server:

```sh
cd "/Users/albinosiby/Tatos Dev/booking/mcp"
npm ci
npm run build
```

The matching backend must be deployed before these tools can manage live
requests. First, the user applies
`supabase/migrations/20261029105442_admin_voice_mcp_credentials.sql` to the correct
BookingOS project. Follow [migration prerequisites, validation and recovery](admin-mcp-migration.md).
No implementation or MCP command applies that migration. Keep
`DATABASE_MIGRATE=false` in production and the existing `BOOKING_SECRETS_KEY`
unchanged. Review the backend changes and follow the current
[Supabase deployment instructions](supabase-only.md).

Create one scoped, expiring local credential with your operator email:

```sh
npm run admin:bootstrap -- --operator-email YOUR_ADMIN_EMAIL
```

This writes two new files with mode 0600 under the gitignored `.local/` directory:

- `.local/admin-mcp.env`: private token and installation configuration.
- `.local/admin-mcp-credential.sql`: registration SQL containing only the token
  hash and scopes, never its value.

The command never overwrites existing files or contacts the live database. Review
and apply the registration SQL yourself after the migration. Never paste the env
file into a chat, issue or commit. Token validity defaults to 90 days; `--days`
accepts 1–365. Optional `--config-file` and `--sql-file` select new output paths.

## Select a reusable template

Use Sarvam's MCP and its current agent-config schema to prepare a dedicated
committed template in the intended workspace. It must have exactly one initial
state, no custom tools and no client credentials. Its voice, native language,
greeting and conversation defaults must already be reviewed. Do not use Edens,
RK Groups or another live client agent as this template.

Fill these nonsensitive manifest values in the private env file:

| Variable | Value |
| --- | --- |
| `BOOKINGOS_SARVAM_TEMPLATE_AGENT_ID` | Dedicated template app ID. |
| `BOOKINGOS_SARVAM_TEMPLATE_VERSION` | Exact committed positive version. |
| `BOOKINGOS_SARVAM_TEMPLATE_LANGUAGE` | Requested locale, for example `en-IN`. |
| `BOOKINGOS_SARVAM_TEMPLATE_LANGUAGE_PATH` | Exact dot path to the native language setting in the current provider config. |
| `BOOKINGOS_SARVAM_TEMPLATE_LANGUAGE_VALUE` | Reviewed string at that path, for example the provider's actual locale/language name. |

The field path must come from the authenticated provider schema and template
read-back; it is not a hardcoded guess about a future Sarvam schema. Preflight
checks the pinned template field. Tool verification checks that same native field
in the actual client draft and committed version. The selected manifest is frozen
into the signed setup plan so local edits cannot change an interrupted job.

If the platform already has a saved workspace API key for the matching provider
organization and workspace, the backend reuses it. Otherwise enter
`BOOKINGOS_SARVAM_WORKSPACE_API_KEY` privately in the local env file. This key is
sent only to the trusted BookingOS backend for deployment and analytics checks;
it is never exposed as a normal tool argument or result. The per-client `bkv_…`
tool credential is generated independently.

## Authorize the private Sarvam installer

```sh
BOOKINGOS_ADMIN_ENV_FILE="/Users/albinosiby/Tatos Dev/booking/.local/admin-mcp.env" node dist/admin-login.js login
```

The explicit command prints an official Sarvam authorization link and waits for a
loopback callback on `127.0.0.1:42827`. Open the link yourself, sign in to the
intended workspace and approve it. PKCE and state bind the callback to this login.
The token is saved atomically in a private file at
`~/.config/bookingos-admin/sarvam-oauth.json`. The normal MCP tools never open a
browser or launch sign-in.

This does not use the rejected
`https://bookingos.online/admin/agent-requests/mcp/callback` path and does not read
Codex's stored OAuth credentials. If Sarvam rejects dynamic registration for this
loopback client, obtain an approved client configuration from Sarvam; set
`SARVAM_OAUTH_CLIENT_ID` and, when required, `SARVAM_OAUTH_CLIENT_SECRET` privately.
Do not bypass registration or promise the login has succeeded until it has.

Optional `BOOKINGOS_SARVAM_TOKEN_FILE`, `BOOKINGOS_SARVAM_CALLBACK_PORT` and
`SARVAM_OAUTH_ISSUER` configure the private store, loopback port and expected issuer.
The same env file is loaded by login and the stdio server. Inspect safe auth status
with `node dist/admin-login.js status`; remove only this integration's token with
`node dist/admin-login.js logout`.

Sarvam currently documents a 24-hour token without a refresh token. Renew the
private installer using the same explicit login command when it expires. Codex's
separate Sarvam MCP can require its own Authenticate action. Routine per-client
configuration uses APIs while authorization is valid.
[Sarvam MCP authentication](https://docs.sarvam.ai/voice-agents/mcp).

## Connect to Codex

The local server uses stdio. Register it once with the absolute built entry point
and only the private file path in Codex configuration:

```sh
codex mcp add bookingos-admin --env 'BOOKINGOS_ADMIN_ENV_FILE=/Users/albinosiby/Tatos Dev/booking/.local/admin-mcp.env' -- node '/Users/albinosiby/Tatos Dev/booking/mcp/dist/admin-main.js'
```

The official Sarvam server URL remains
`https://mcp.sarvam.ai/voice-agents`. Do not overwrite its existing configuration or
copy its token into this integration. Codex stores MCP configuration in
`~/.codex/config.toml`; restart/reload MCP discovery and open a new local chat
after registration. [Official Codex MCP configuration](https://learn.chatgpt.com/docs/extend/mcp?surface=cli).

An unconfigured server can still start and expose `get_setup_status`. It reports
missing installation prerequisites without revealing credentials. No request
connection changes occur until admin authorization and provider preflight pass.

## Use from a new chat

Example prompt:

> Use BookingOS admin MCP and Sarvam Voice Agents MCP to connect the pending
> call-service request for CLIENT NAME. Use PHONE NUMBER. Approve only its requested
> services and requested language. Configure and verify the exact committed version,
> mark Connected, and leave client booking off. Continue the saved job until done.

Codex should resolve the organization first, read the request and any existing
job, then preflight and prepare the plan. If the name matches more than one
organization or a phone is not selected, it needs that choice. An already
connected client should be reported as connected instead of silently replaced.

`start_connection` starts a signed, version-bound plan. `resume_connection` runs
one leased step per call and returns the next checkpoint. Codex continues calling
it through agent, credential, each approved tool, configuration, commit,
deployment, verification and activation until `done=true`.

The MCP initialization instructions and
`bookingos-admin://voice/connection-workflow` resource contain this sequence, so
the new chat does not need the earlier conversation. The existing admin panel
reflects the saved state but is not used for the setup operations.

## Tool and API contract

Tools are `get_setup_status`, `list_connection_requests`,
`get_connection_request`, `preflight_connection`, `prepare_connection`,
`start_connection`, `get_connection_job`, `resume_connection`,
`install_tool_credential`, `verify_connection`, `activate_connection` and
`pause_connection`. The three named step tools only run their matching saved job
step; they cannot skip prerequisites. No tool returns a raw credential.

The backend namespace is `/v1/admin-mcp/voice`. Read scope is `voice:read`; setup
scope is `voice:write`. The internal credential endpoint additionally requires
`voice:credentials:install`, an active job/lease and an idempotent operation ID.
That raw HTTP response is consumed only inside the private installer. It is never
registered as a pass-through MCP tool. Panel HMAC proofs, owner/staff sessions and
MCP credentials are not interchangeable.

Saved plans bind the principal, request/integration versions, requested service
subset, workspace, phone, connection and reviewed template. Job references are
immutable, and reservations have conflict checks. Manual connection save/key
rotation refuses automatically managed jobs to avoid accidental disconnection.

## Verification and recovery

Live capability check on 29 October 2026: the private OAuth login succeeded and
the workspace advertises secret creation, but its API-tool authoring descriptions
explicitly refuse attaching authentication and require selecting the credential
in Sarvam's console. The current live server therefore stops with
`PROVIDER_CREDENTIAL_ATTACHMENT_UNAVAILABLE` before allocating any resources.
Full configuration without the console is blocked until Sarvam provides an
approved programmatic credential-attachment interface. The adapter does not try
undocumented endpoints or encode credentials in headers/URLs to bypass this rule.
Existing clients and deployments were not changed by the capability check.

Preflight validates actual provider capabilities, including private secret
creation/attachment and supported version-bound authoring. It stops before
allocation with `PROVIDER_CAPABILITY_MISSING` if the workspace cannot support
them. Tests against fixtures do not establish that a live workspace has these
capabilities; run the real preflight after sign-in.

The installer sends the generated key directly to Sarvam and receives its secret
reference. A direct catalog-only request to the exact BookingOS API checks that
the backend accepts that key while client booking is off. This is a backend
credential check, not execution of Sarvam's runtime tool. Tool read-back checks
the actual stored reference, inputs, response mapping, service scope and language.
Deployment and analytics verification checks the selected phone and exact active
committed version. A real call is a separate test and is never placed automatically.

On interruption, read the same saved job. A lost creation response is reconciled
by the job's unique name and references. After `OUTCOME_UNKNOWN`, missing read-back
does not trigger a second agent, secret, tool, deployment or commit; wait for
read-back or investigate the original operation. A matching secret name cannot
prove its hidden value. Recovery can rewrite that job-owned secret only when the
provider advertises an explicit supported update operation; otherwise it stops
with `CREDENTIAL_RECOVERY_REQUIRED` before deployment.

Occupied numbers return `NUMBER_IN_USE`. Transferring another client's number
requires a separately reviewed operation; this workflow does not delete or
detach another client's deployment. Final activation keeps `enabled=false`.
The client then selects spaces and turns call booking on.

Revoke the admin principal using the SQL in the bootstrap output or migration
guide. Every backend request checks revocation and expiry. Keep the additive
migration in place when rolling back application code; reconcile any partial
provider job instead of deleting unrelated resources.

## Local verification

```sh
npm run build
npm test
cd ../backend
node --import tsx --test test/admin-mcp-auth.test.ts test/admin-mcp.test.ts test/admin-mcp-edge.test.ts test/admin-sarvam.test.ts test/sarvam-booking-config.test.ts
npm run edge:check
```

Tests use in-memory databases, mocked provider APIs and in-memory MCP clients.
They do not apply a live migration, sign in to Sarvam, place calls or write real
bookings. CI installs both backend and MCP dependencies for the compatibility
tests.
