# BookingOS admin MCP implementation and live capability check

The user approved the design in `docs/bookingos-admin-mcp-design.md` on
29 October 2026. A separate local stdio server named `bookingos-admin` is built
and registered globally in Codex alongside the existing `sarvam-voice-agents`
Streamable HTTP connection. Codex configuration stores only the built executable
and private configuration file path, not the admin token.

The server exposes twelve tools for safe installation status, request discovery,
preflight, signed plans, job start/resume, private credential installation,
verification, activation and pause. A workflow resource and initialization
instructions make the sequence discoverable to a new chat. Normal owner/staff
booking tools retain their separate server and permissions.

Backend changes add scoped, expiring, revocable hashed credentials, separate
Nest/Edge authentication, signed version-bound plans, frozen service/template
requirements, immutable resource references, per-step leases, checkpoints,
uncertain-outcome reconciliation and actual committed version checks. Client
activation keeps booking off. Existing automatic setup now generates only the
approved service tools and matching prompt references. A booking/rescheduling
request uses six tools and omits cancellation.

Migration `20261029105442_admin_voice_mcp_credentials.sql` was prepared in both
migration directories. The user reported applying it. The assistant did not
apply any live migration. A private bootstrap created the local credential and
hash-only registration SQL at `.local/admin-mcp-credential.sql`; that registration
SQL has not been applied by the assistant. The automation principal is labelled
Codex voice setup using an internal service identity, not a newly created mailbox.

The user completed the private Sarvam OAuth sign-in. The explicit CLI successfully
registered its loopback callback and saved its own authorization in a private
token store; it did not copy Codex's token or depend on the rejected BookingOS
admin callback. Safe status showed authorization valid until 30 October 2026,
11:18 UTC (16:48 Asia/Kolkata). Normal setup tools never start sign-in.

Live MCP metadata exposed `configure_secret`, but the descriptions of
`configure_app_tool`, `create_api_tool` and `configure_secret` explicitly prohibit
attaching authentication to tools through that MCP. They require a user to select
the credential in Sarvam's console. This is a material provider capability limit,
not evidence that a fully automatic connection has succeeded. The new preflight
returns `PROVIDER_CREDENTIAL_ATTACHMENT_UNAVAILABLE` before any allocation when
this restriction is advertised. No workaround using raw headers, credentials in
URLs, undocumented APIs or extracted browser tokens was attempted. Further
adapter compatibility must be validated against an approved provider interface
before claiming full unattended setup.

The live check read only MCP schemas and Edens v2's native language metadata.
It did not change Edens, RK Groups, agents, secrets, deployments, phone numbers,
bookings or call logs. The verified English native field in that configuration
was `language_config.initial_language_name`, value `English`.

The live BookingOS admin-MCP route returned HTTP 404 after migration application,
so the matching backend is not deployed yet. The connected Supabase account does
not list the live project `scwwkaywewecspsrskft`. No deployment was made to a
different project. The generated Edge bundle contains the current workspace's
other pending changes as well; review those before publishing a whole bundle.

Validation includes in-memory backend and MCP tests, mocked OAuth/provider tests,
compiled stdio tool discovery, backend/Edge typechecks, formatting and a generated
Edge build with no embedded secrets. These tests do not prove a live provider
supports authenticated tool authoring. Installation and operation instructions are
in `docs/bookingos-admin-mcp.md`; migration/revocation/recovery steps are in
`docs/admin-mcp-migration.md`.

Final focused results: 61 MCP tests and 75 backend tests passed. The mock OAuth
callback deadline was raised to ten seconds after an intermittent failure under
concurrent database-test load; state, PKCE, issuer and credential-redaction
assertions were retained. A subsequent complete MCP run passed. The final guard
was also checked against the captured authenticated provider schemas and refused
credential attachment without making any provider mutation. A later fresh
schema request encountered a network error and was not treated as successful
end-to-end verification.
