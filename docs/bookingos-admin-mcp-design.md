# BookingOS admin MCP design for Sarvam setup

Status: approved by the user on 29 October 2026; implementation prepared.
See [installation and operation](bookingos-admin-mcp.md) for the delivered setup,
authentication and live capability prerequisites.

The intended operator experience is: connect BookingOS admin MCP and Sarvam Voice
Agents MCP to Codex, then say “Connect the call-service request for Edens using
this number.” Codex resolves the request, respects its services and language,
configures the provider, saves the connection, verifies it and marks it Connected.
Routine configuration uses tools instead of the browser or admin forms. The
client still chooses spaces and switches call booking on.

Full automation depends on a supported programmatic way to create and attach
Sarvam secrets. A separate MCP connection in Codex does not share its OAuth
credential with BookingOS. Capability and authentication checks therefore come
before allocating provider resources or generating client credentials.

## Product analysis

The current setup crosses two systems and requires manual copying of identifiers
and secrets. This introduces wrong-client credentials, stale deployed versions
and incomplete verification. The primary user is the platform super admin working
in a local Codex chat; clients continue using the existing client controls.

Core scope is request discovery, service and language selection from the saved
request, phone inventory, a setup preview, repeatable provider configuration,
credential installation, committing and deploying the reviewed version, backend
verification, activation, pause and recovery after an interrupted operation.

Optional later scope is remote MCP hosting for other computers, additional
operator accounts, approved number-transfer automation, call-log diagnostics and
explicitly requested test calls. Buying numbers and changing client space choices
are outside the initial connection operation.

The alternatives are the existing manual console workflow, a thin MCP wrapper
around the existing admin APIs, and a provisioning MCP with a trusted credential
bridge. A thin wrapper reduces form entry but leaves the separate backend Sarvam
login and secret-installation problem. The proposed bridge addresses that gap
when the provider exposes the required capability.

## System architecture

Use the current Node.js and TypeScript MCP SDK stack, adding a separate
`bookingos-admin` stdio entry point and tool registry. Preserve `eden-booking`,
which signs in as owner/staff and manages reservations. Admin provisioning should
not become an owner/staff booking tool.

Codex talks to two servers:

- BookingOS admin MCP: request policy, setup plans, approved service configuration,
  scoped backend operations, safe provider references, verification and audit.
- Official Sarvam Voice Agents MCP: supported provider inventory, agent authoring,
  committed versions and deployment operations.

The BookingOS adapter calls narrow authenticated backend endpoints; it has no
direct database access. Existing backend services remain the authority for
permissions, request versions, service approval, number reservation and client
state. The admin panel continues to display the same saved state.

A private credential installer generates the per-client tool key and sends it
directly to the authorized Sarvam secret store. It returns a secret reference and
an operation receipt, never the key value. This installer needs its own supported
provider authentication. It must not extract OAuth tokens from Codex storage or
pretend another MCP connection automatically supplies them.

Start with local stdio for this computer. Local Codex supports stdio and remote
Streamable HTTP, stores MCP configuration in `config.toml`, and reads server-wide
workflow instructions from MCP initialization. The implementation will supply
those instructions so a new chat can discover the process without this history.
[Official MCP setup](https://learn.chatgpt.com/docs/extend/mcp?surface=cli).

## Authentication and provider capability gate

Add a dedicated revocable credential for the admin automation principal, limited
to voice-connection administration. Keep the backend's `ADMIN_SESSION_SECRET`,
database URL and Supabase service-role credentials out of the MCP client.
Authentication should identify the actual automation principal in audit records.

Provision the admin credential privately during installation. Store only its hash
on the backend, with allowed scopes, expiry and revocation. Verify its active
state on every operation. The local server reads its credential from private
configuration, with redacted errors and logs.

Sarvam's official MCP connection is scoped to one workspace. Its documentation
states that its OAuth token lasts 24 hours without a refresh token; sign-in can
therefore require a browser again. This design removes browser work from routine
setup while valid authorization is available; it does not eliminate provider
authentication. [Sarvam MCP](https://docs.sarvam.ai/voice-agents/mcp).

Before any live setup, check the authenticated provider's actual advertised
schemas for agent configuration, tools, secrets, commit, deployment and read-back.
The existing workspace REST key proves deployment and analytics access, not
secret-authoring access. Do not assume it supports secret creation.

Prefer a documented server API for the credential installer if it supports this
workspace. If secret authoring requires a separately authorized MCP client, that
client needs its own supported login and private token store. The previously
rejected BookingOS callback must not silently become a dependency again. A new
loopback or server authorization flow must be validated against provider support.

If no supported secret-creation/attachment path exists, report
`PROVIDER_CAPABILITY_MISSING` before making live setup changes. Do not fall back to
putting credentials in prompts, tool output, URLs or unauthenticated webhooks.
Full unattended setup is an acceptance condition, not a claim made merely because
both servers appear in Codex.

## Data flow and workflow

1. Resolve the organization name to a saved request and stable IDs. Return choices
   for ambiguous names; never guess from a display name.
2. Read requested services, language, current connection and versions. Discover
   current provider capabilities, workspace and available onboarded numbers.
3. Produce a setup plan bound to the request, organization, provider workspace,
   phone, approved services and expected versions. Use an explicit number from the
   prompt or a saved selection; request a choice if there is no unique selection.
4. Reserve the number and begin an idempotent job. Reuse an existing connection or
   recorded checkpoint on retry. Do not duplicate agents after an uncertain reply.
5. Generate and install the client credential privately, then return its provider
   reference to the orchestration workflow.
6. Create or configure the organization's agent. Generate tools and instructions
   from the approved services, preserving trusted caller/call context, numeric
   types, lifecycle hooks and top-level response mapping.
7. Read back the persisted provider configuration. Audit scope, auth reference,
   inputs, prompt, language and failure behavior before committing a version.
8. Commit and configure the number's deployment to use that exact committed
   version. Read back its active status and identity.
9. Save references and perform provider/deployment/analytics verification plus a
   read-only tool authentication check. Mark Connected only when every required
   check passes. Leave client `enabled=false`.
10. Return organization, services, number, agent/version, deployment ID, verification
    result and the client's next step. A real call test is reported separately.

For Edens, the resulting agent contains catalog, availability, booking, caller
bookings, rescheduling and completion logging: six tools, English, no cancellation
tool. Rescheduling remains restricted to the trusted caller's call-created
bookings. Other requests can approve a different subset of the supported services.

## Database design

Reuse `agent_call_requests`, `sarvam_integrations.setup_state`, existing version
columns, `setup_lease`, `sarvam_admin_connection` and `admin_audit_log` for request
state, provider references, encrypted credentials, checkpoints and audit events.
The request is linked to one client organization; setup and integration records
remain organization scoped.

Add a narrowly scoped automation-credential table only for the new transport
authorization: identifier, name, unique token hash, scopes, issuer/operator,
created time, expiry, revocation time and last-used time. Index unique token
lookup and active expiry queries. It must not be exposed to owner/staff Data API
access. Raw tokens are generated once, never stored in this table.

Bind operation receipts and plans to organization, request version and integration
version. Reuse current unique phone and agent constraints, row locks and setup
leases. Validate approved services as a subset of requested services, provider
scope, normalized phone, immutable committed version and exact deployment match.
Persist enough provider references to reconcile partial progress.

Prepare migrations for user application only, with preflight, validation and
recovery instructions. Do not apply them as part of implementation or deployment.

## API and MCP design

Proposed MCP tools:

| Tool | Purpose |
| --- | --- |
| `list_connection_requests` | Find pending requests by organization/status. |
| `get_connection_request` | Read services, language, safe connection metadata and versions. |
| `preflight_connection` | Check authorization, workspace, provider capabilities and number conflicts. |
| `prepare_connection` | Return the exact setup plan and required provider specification. |
| `start_connection` | Reserve and begin the reviewed, version-bound setup operation. |
| `install_tool_credential` | Privately install the key and return only its secret reference. |
| `record_provider_resources` | Save and validate agent/version/deployment references for this job. |
| `get_connection_job` | Read checkpoints, safe failures and the next allowed action. |
| `resume_connection` | Reconcile and continue the same operation. |
| `verify_connection` | Validate actual committed tool configuration and live deployment. |
| `activate_connection` | Mark the verified request Connected; keep client booking off. |
| `pause_connection` | Block this organization's call-service actions. |

Expose an MCP workflow resource and concise server instructions covering the
two-server sequence. Do not expose arbitrary HTTP, SQL, unrestricted admin routes,
secret reads, token export or a raw tool-key rotation result.

Backend routes should live in a narrow namespace such as `/v1/admin-mcp/voice/`,
enforced consistently in Nest and the hosted Edge handler. Reuse existing business
services after authenticating and authorizing the automation actor. Add dedicated
methods where existing operations return plaintext credentials or bypass the
new scope.

Example setup input: organization ID, request ID, approved services
`[booking, rescheduling]`, language `en-IN`, selected phone, expected request and
integration versions, plan ID and idempotency key. Example safe result: job ID,
state `connected`, agent ID, committed version, inbound deployment ID, phone,
verification outcome and `client_enabled=false`. No credential value appears in
the result.

Use explicit typed failures: `UNAUTHENTICATED`, `FORBIDDEN`,
`AMBIGUOUS_ORGANIZATION`, `STALE_PLAN`, `NUMBER_IN_USE`,
`PROVIDER_AUTH_REQUIRED`, `PROVIDER_CAPABILITY_MISSING`, `OUTCOME_UNKNOWN` and
`VERIFICATION_FAILED`. An uncertain remote outcome returns the existing job and
operation IDs and requires reconciliation, not blind re-creation.

## Frontend and operator flow

No new configuration screen is required for initial setup through MCP. The current
admin request, manual connection, verification and audit screens show the same
backend state. Owner/staff booking UI and permissions remain separate.

The operator interaction is prompt, unique request resolution, phone selection if
missing, then status/result. Keep transient state in the MCP client and durable
state/checkpoints on the backend. Required authorization or a destructive number
transfer can still pause the operation; the system must not promise that a single
prompt bypasses host approvals.

A number already assigned to another client must return a conflict. Automatic
transfer is a later explicit operation with source/destination, expected versions,
downtime implications, approval and recovery details. The earlier RK Groups to
Edens transfer does not authorize future transfers.

## Development plan

Implement in this priority order after design approval:

1. Validate the live Sarvam capability/authentication contract and settle the
   private credential installer. This is the go/no-go milestone for full automation.
2. Add dedicated admin MCP authorization and the separately scoped stdio entry
   point. Add request discovery, preflight and preview tools.
3. Add stateful connection operations and resource receipts, reusing existing
   leases/checkpoints. Generate service-specific tools and instructions.
4. Add provider configuration audit, credential check, exact version/deployment
   verification, activation and interruption recovery.
5. Run the targeted tests, prepare user-owned migrations, document deployment and
   install the Codex configuration. Start a new chat for discovery/smoke tests.

Planning estimate: roughly three to five focused engineering days once provider
credential authoring and authentication are confirmed, divided between adapter
and backend work, workflow/recovery, and verification/documentation. Provider
approval or missing capabilities can change that estimate.

## Security

Apply least privilege to the admin MCP principal, verify scope on every operation,
allow only configured BookingOS and Sarvam origins, and preserve organization and
workspace ownership checks. Recheck actual provider inventory before assigning a
number. Do not expose customer records/transcripts merely to configure an agent.

Per-client keys remain isolated, encrypted where recoverable storage is needed,
and hashed for runtime lookup. Logs contain IDs and operation states, not raw
credentials, signed headers or provider response bodies that can echo secrets.
Sarvam tools reference stored secrets rather than embedding values in prompts or
exported definitions. [Sarvam secrets guidance](https://docs.sarvam.ai/voice-agents/settings/secrets).

No automatic real calls, booking writes, purchased numbers, deletion of another
client's deployment, or schema changes during configuration. Service scope is
enforced by backend policy as well as by omitting unapproved action tools.

## Testing

Use the existing in-memory MCP client pattern and backend provider fixtures.
Test schemas and response contracts, scope denial/revocation/expiry, secret
redaction, ambiguous organization names, stale versions and requested-service
restrictions. Verify the six-tool booking/rescheduling case and other service
subsets with their generated prompts.

Integration tests cover occupied phones, workspace mismatch, credential install
failure, expiring provider auth, interrupted/uncertain writes, lease contention,
reconciliation without duplicates, wrong committed versions, incorrect auth
references and activation refusal after failed verification.

An end-to-end acceptance run uses a designated test request and available test
number with both MCPs, no admin/browser configuration, and checks the final saved
state. Authentication and any intentional real call are separate user steps.
Never repurpose the live Edens line as a disposable test resource.

## DevOps

Build and launch the local stdio server with pinned dependencies and an absolute
entry-point path. Add MCP typecheck, protocol integration tests and backend
authorization/workflow tests to existing CI. Deploy the backend changes after the
user applies required migrations, then enable the local MCP principal.

Log request/job/principal IDs, setup transitions, lease expiry, provider latency
and redacted failures. Alert on repeated failures or abandoned reservations.
Use existing database backup/recovery procedures and persist provider checkpoints
before advancing steps. Resume/reconcile partial work; do not automatically delete
unrelated deployments during rollback. Revoke the automation credential to disable
the new transport without affecting client bookings or the ordinary admin panel.

## Documentation and acceptance

Deliver setup instructions, environment/configuration examples without secrets,
credential bootstrap/revocation steps, migration validation/recovery, tool/API
contracts, authentication renewal, run recovery and an operator prompt guide.

The final new-chat prompt can be: “Use BookingOS admin and Sarvam Voice Agents to
connect Edens' pending request with +91 [selected available number], approve only
its requested services, verify the deployment and mark Connected. Leave client
booking off.” If the request/name/number is unique and both authorizations are
valid, no extra configuration form entry is needed.

Completion means both MCPs are discoverable in the new chat, a supported private
credential installer exists, the requested services and language are correct,
the exact committed version is deployed on the selected number, backend state is
verified and Connected, and the client still controls spaces and enablement.

## Implementation references

- `mcp/src/main.ts`, `client.ts`, `tools.ts`: existing stdio transport and booking
  tool patterns; keep their owner/staff scope separate.
- `backend/src/admin/panel-auth.ts`, `admin.guard.ts`, `backend/edge/handler.ts`:
  current admin transport requires the panel HMAC; add dedicated narrow auth.
- `backend/src/admin/admin.service.ts`: request/connection/version/audit logic and
  manual verification; do not expose the raw key returned by rotation.
- `backend/src/admin/admin-sarvam.service.ts`: existing checkpointed provisioning
  and separate backend Sarvam authoring authorization.
- `backend/src/sarvam/sarvam-provisioning-remote.ts`: provider schema discovery,
  secret installation, configuration read-back and deployment verification.
- `backend/src/sarvam/sarvam-booking-config.ts`: existing tool definitions and
  prompt; select tools and prompt references by approved service instead of always
  adding cancellation.
