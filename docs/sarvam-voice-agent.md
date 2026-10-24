# Managed call service

Clients request a call service and choose Booking, Rescheduling, Enquiries and/or Cancellation. Only a platform super admin configures Sarvam, assigns the number and verifies the connection. Clients see provider-neutral status, the number, activated services, space switches and call history.

## Ownership and state

- Organization owners request the service and manage space access/the service switch. Existing staff permissions do not grant these controls.
- Super admins approve a subset of the requested services, store provider credentials, assign the phone number, rotate the tool key, verify and activate the connection. Support-role admins cannot perform these operations.
- Requests progress through `requested`, `in_review`, `setting_up`, `active`, `paused` or `rejected`. The client renders `active` as connected. Rejected requests can be submitted again.
- `active` is separate from `enabled`. Activation never enables client actions automatically. A verified connection, an active request, approved services and at least one ready selected space are required to enable.
- Moving out of `active` immediately disables the integration and voice membership. Changing connection details or rotating the tool key also disables access and clears verification. A provider identity change revokes the previous tool key.
- Off blocks call-service actions. It does not pause telephony or disconnect the number. The UI explains this. Stop inbound answering in Sarvam when that is required: [deployment pause/resume](https://docs.sarvam.ai/voice-agents/api/deployments/update-status).
- Existing bookings are preserved. Rescheduling/cancellation through phone is restricted to the caller's bookings in selected spaces. Caller identity still relies on trusted provider caller context; this change does not add OTP verification.

## Architecture

Flutter Screen → Cubit → repository → `/v1/agent-calls` → organization-scoped backend. Next.js server actions → signed admin API → super-admin authorization → encrypted provider configuration. Voice HTTP tools authenticate through a unique hashed key scoped to one organization.

Services are checked in the voice service and again inside the booking transaction. The transaction takes shared locks on connection/request state before the membership lock. Admin/client control writes lock the connection first, so a completed revocation blocks later booking writes. Space permissions use explicit resource IDs in the existing voice membership's staff assignments. No selection removes an assignment: an empty array has legacy all-space semantics and must never be used by the managed workflow.

One provider agent and one phone number can be assigned to only one organization. This keeps provider analytics, tools and numbers isolated. New resources do not inherit voice access.

## Automatic setup through MCP

Open **Call service requests → Connect or reconnect Sarvam**. This connection belongs to the platform, not to a client.

1. After applying the new migration below, deploy the API and admin panel. Set the API secret `SARVAM_ADMIN_REDIRECT_URI` to your exact admin web URL ending `/admin/agent-requests/mcp/callback`. Keep the existing `BOOKING_SECRETS_KEY`. The API public HTTPS URL must point to the API, including `/functions/v1/booking-api` when hosted on Supabase. The Edge entry sets that URL automatically.
2. Enter your Sarvam organization/workspace IDs and workspace API key once, then save. Click **Connect Sarvam**, sign in to the matching workspace, approve access and click **Continue to admin panel** on return. Custom OAuth callbacks may need Sarvam allow-list approval. If Sarvam provides a registered client, set `SARVAM_OAUTH_CLIENT_ID` on the API. The panel displays the exact callback URL.
3. Select a single-state Sarvam template agent with your desired voice/language/model settings and **no tools**. Create this basic template in Sarvam once if necessary. Save it on the connection page. Client agent IDs are generated automatically.
4. Open a client request, review the service checkboxes, choose a free number from the authenticated workspace inventory and click **Approve and create agent**. Existing manually configured clients continue using their connection. Automatic approval is for requests without an assigned agent.
5. Keep the page open while setup runs. It reserves the number, clones a separate agent with a unique saved name and records its generated ID, installs a tenant-specific secret plus six booking tools and the on-end logging tool, writes the managed instructions, reads the configuration back, commits it, creates the inbound deployment, verifies its number/agent and analytics credentials, and changes the client status to Connected. The client switch remains off; the client selects spaces and enables it.
6. If setup stops, return to the request and click **Resume setup**. Progress, unique agent name, generated agent identity and number reservation are durable. A lost create/deployment response is recovered by reading provider state before writing again. The browser advances one bounded API step at a time; there is no background queue continuing after the page closes.

**Reconnecting:** Sarvam currently documents a 24-hour OAuth lifetime with no refresh token. The panel displays expiration and a Reconnect button. Click **Reconnect Sarvam**, sign in, click **Continue to admin panel**, then reopen the client request and **Resume setup**. Reauthorization preserves deployed agents, tool keys, numbers and space controls. Existing calls use their configured tool key; analytics uses the workspace API key, so normal calls do not depend on the MCP sign-in remaining valid. A provider 401 also marks the connection as needing reconnect.

Only numbers already onboarded in Sarvam can be selected. This flow does not purchase numbers, perform KYC or place test calls. Numbers used by any existing deployment (including paused deployments) or reserved by another BookingOS client are unavailable. A single MCP connection manages one workspace. Switching workspace IDs is blocked after managed agents exist. Updating the workspace API key updates automatic clients in that same workspace without rotating their booking tool keys.

Capabilities are discovered from authenticated MCP `tools/list`; unsupported operations, required fields, absent native-clone/secret/HTTP-tool/deployment capabilities or incomplete inventories stop setup with an admin-visible error. Both `create_http_tool` and the legacy `configure_app_tool` are supported when their schemas match the implemented connector contract. Enterprise code-tool-only workspaces are not silently treated as HTTP-tool workspaces. Remote agent/tool readbacks and deployment verification must pass before activation. The authenticated workspace’s real schemas, voice settings and number routing still require a controlled staging acceptance run; fixture tests cannot certify them.

References: [Sarvam MCP](https://docs.sarvam.ai/voice-agents/mcp), [API tool lifecycle and trusted context](https://docs.sarvam.ai/voice-agents/build/tools/https-tool), [inbound deployment creation](https://docs.sarvam.ai/voice-agents/api/deployments/create). Deployment creation can begin answering calls immediately; approval explicitly authorizes assigning the selected number. Booking writes remain disabled until the client turns them on.

### Architecture and security

Signed Next.js server actions → super-admin-only `/v1/admin/sarvam` → encrypted singleton `booking_app.sarvam_admin_connection` → Sarvam OAuth/MCP. Existing per-organization integration rows store the reserved phone, generated agent ID, encrypted tenant tool key, and resumable job state. A database lease prevents concurrent step execution. Optimistic versions protect approval/settings, unique phone/agent/deployment indexes prevent cross-client assignments, and a final request-state check prevents paused/rejected jobs becoming Connected. Operational logs and audit records exclude OAuth codes, access tokens, API keys and transcript bodies.

OAuth uses PKCE S256, a random hashed one-use state with ten-minute expiry, fixed server-configured callback URI and authenticated signed completion. The existing admin session stays SameSite=Strict. The callback displays a same-origin Continue POST so returning from Sarvam can restore that session without relaxing its cookie policy. Callback responses disable caching, referrers, external assets and embedding. Browser/server actions receive only safe status, inventory and progress; authorization and workspace API secrets stay encrypted on the API.

| Method | Admin API path | Purpose |
|---|---|---|
| GET / PUT | `/v1/admin/sarvam` | Read safe status / save workspace settings with version |
| POST | `/v1/admin/sarvam/connect` | Start or restart browser authorization |
| POST | `/v1/admin/sarvam/callback` | Signed, one-time OAuth completion |
| GET | `/v1/admin/sarvam/inventory` | Safe agent/template and phone inventory |
| GET | `/v1/admin/sarvam/jobs/:organizationId` | Safe progress |
| POST | `/v1/admin/sarvam/jobs/:organizationId/approve` | `{version,approved_services,connection_id,phone_number}` |
| POST | `/v1/admin/sarvam/jobs/:organizationId/resume` | Advance one durable setup step |

### Additional migration — applied by the owner

The earlier managed-call-service migration you already applied is retained. Automatic provisioning requires **one additional migration**: `supabase/migrations/20261024101355_admin_sarvam_provisioning.sql`. Do not reapply the earlier migration. The backend copy is for disposable tests only. This new migration creates a private singleton credentials table and a unique deployment-assignment index; it does not alter existing client enablement or credentials.

Before applying, back up the database and verify the prior managed migration exists and no duplicate nonempty deployment assignments are present:

```sql
SELECT name FROM booking_app.schema_migrations
WHERE name IN ('20261024075411_managed_call_service.sql','20261024101355_admin_sarvam_provisioning.sql');
SELECT sarvam_org_id,workspace_id,deployment_id,count(*)
FROM booking_app.sarvam_integrations WHERE deployment_id<>''
GROUP BY sarvam_org_id,workspace_id,deployment_id HAVING count(*)>1;
```

Resolve duplicate assignments before applying. Run the entire new Supabase SQL file once in SQL Editor; it includes BEGIN/COMMIT and schema-migration registration. Validate:

```sql
SELECT id,version,api_key_ciphertext IS NULL AS no_api_key,authoring_ciphertext IS NULL AS no_oauth
FROM booking_app.sarvam_admin_connection;
SELECT grantee,privilege_type FROM information_schema.role_table_grants
WHERE table_schema='booking_app' AND table_name='sarvam_admin_connection';
SELECT indexname FROM pg_indexes WHERE schemaname='booking_app'
AND indexname='call_service_deployment_unique';
```

Expect one row, both credentials initially absent, no public/anon/authenticated grants, booking_api SELECT/INSERT/UPDATE, and the deployment index. If SQL fails, ROLLBACK and fix prerequisites before retrying the full file. For an application rollback leave the additive table/index in place, stop provisioning, and restore the earlier API/admin binaries. Do not remove client agents or numbers automatically: they may already be deployed. Before resuming a failed job after a provider timeout, use Resume so it reconciles the existing agent/deployment. Manual key rotation and manual connection replacement are blocked for automatic clients. Full backup restoration has not been rehearsed by code tests.

The connected Sarvam MCP contract was inspected read-only during implementation. It creates agents by omitting `agent_id` and passing `clone_from`, `clone_version` and a unique `name`, writes prompt text only through the `prompt` parameter, lists onboarded numbers through `telephony.list_endpoints`, and returns deployment IDs under `id`. The backend follows these contracts and recovers a lost clone response by its saved name. No existing agent configuration was inspected or mutated during that check.

## Manual super-admin setup

1. Open **Call service requests**, review the requested services and update progress/client-visible messages.
2. Open **Manage connection**. Enter the Sarvam workspace API key, provider organization ID, workspace ID, agent App ID, inbound deployment ID, and the phone number in E.164 form (`+` and country code). Select the requested services to approve and save.
3. Generate a tool key. Copy the one-time value into a Sarvam secret. Never paste credentials in prompts. Existing selections are retained when configuration changes, but the service becomes disabled until it is verified again.
4. Configure the HTTP tools below in Sarvam. Use the backend's HTTPS tool base URL shown in the admin panel. Every request uses `X-API-Key` from that secret and `Content-Type: application/json`. Publish/review the intended agent version in Sarvam and connect it to the number. Saving a number in BookingOS does not provision or route a number.
5. Use the provided managed conversation instructions. The catalog's message starts with available services; the agent must offer only those services. The backend enforces them independently. Clarify dates, repeat details and price, obtain explicit caller confirmation, and announce success only after `ok:true` with a booking result. Venue policies must come from approved knowledge; refer unknown questions to venue staff.
6. Check **I configured and reviewed...**, then **Verify connection**. The backend checks analytics credentials and reads the deployment to verify its agent ID, deployment ID, inbound direction, active status and phone-number association. It does not place a test call, inspect every remote tool definition, or create a booking. The checkbox records the admin's tool/configuration review. [Sarvam deployment read API](https://docs.sarvam.ai/voice-agents/api/deployments/get).
7. Set the request to **Connected**. The client selects spaces and enables the service. Perform an authorized test call using a controlled slot before advertising the number. Test each approved service and at least one forbidden action.

Manual setup remains available for existing configured agents and deployments. It does not require MCP authorization. Clients have no provider connection/configuration endpoint. The earlier owner-based automatic authoring code remains internal for compatibility; platform provisioning uses the separate admin OAuth connection described above.

### Voice tools

All endpoints are POST under `/voice/v1`; business refusals return `{ok:false,message}`. Authentication failures use HTTP 401/403. The agent must not interpret HTTP 200 alone as successful booking.

| Tool | Path | Permission |
|---|---|---|
| `bookingos_list_spaces` | `/catalog` | Any approved service; returns permitted services and selected spaces |
| `bookingos_check_availability` | `/availability` | Booking, rescheduling or enquiry |
| `bookingos_book_slot` | `/bookings` | Booking |
| `bookingos_my_bookings` | `/my-bookings` | Rescheduling or cancellation |
| `bookingos_reschedule_booking` | `/reschedule` | Rescheduling |
| `bookingos_cancel_booking` | `/cancel` | Cancellation |
| `bookingos_call_completed` | `/call-events` | Authenticated call completion, including when actions are off |

Run catalog at call start and store its `message` as `bookingos_spaces`. Other action tools run during conversation and return their `message`. The admin panel includes their fields and conversation instructions. Map `caller_phone` and `interaction_id` to Sarvam's trusted User Identifier and Interaction ID variables; do not let the LLM supply caller identity. Keep the same interaction ID on retries. The booking service retains its existing duplicate-request and inventory protections.

Configure `bookingos_call_completed` as an **on_end HTTP API tool**, using the same secret. Map:

| JSON field | Source |
|---|---|
| `interaction_id` | Interaction ID |
| `caller_phone` | User Identifier |
| `duration_seconds` | Call Length |
| `transcript` | Call Transcript, supplied as text |
| `summary` (optional) | Captured call summary |
| `caller_name` (optional) | Captured caller name |
| `disposition` (optional) | Captured outcome |

This is our authenticated on-end tool contract, not Sarvam's differently shaped deployment-webhook payload. [Sarvam HTTP tool lifecycle and context](https://docs.sarvam.ai/voice-agents/build/tools/https-tool). Use a bounded timeout and provider delivery retries where available. Repeated completion events update the same record. Call start time is estimated from event receipt minus duration until analytics supplies the precise timestamp.

## Client API

All routes require the authenticated organization owner. Credentials/provider identifiers/internal notes never appear in client responses.

| Method | Path | Contract |
|---|---|---|
| GET | `/v1/agent-calls` | Status, client message, requested/approved services, phone number, settings version, ready/enabled flags, spaces, call-log availability |
| POST | `/v1/agent-calls/request` | `{note?,services:["booking","enquiry"]}`; at least one distinct known service |
| PUT | `/v1/agent-calls/spaces` | `{version,resource_ids:[...]}`; only ready spaces from the owner's organization |
| PUT | `/v1/agent-calls/enabled` | `{version,enabled}`; stale enable is rejected, stale disable remains safe |
| GET | `/v1/agent-calls/calls` | `start`, `end` ISO timestamps (maximum 31 days), `offset`; returns items, total, next_offset and warning |
| GET | `/v1/agent-calls/transcript` | `interaction_id` from this organization's call history |
| GET | `/v1/agent-calls/recording` | Same ownership check; authenticated audio proxy |

Admin request updates require the request version. Connection updates and verification require the connection version. Stale writes return 409; ownership failures return 403; invalid selections return 400. No space is selected by default for a new connection. Deselecting the last space turns the service off.

## Call history and privacy

The authenticated on-end tool stores call metadata and a transcript in private `booking_app.agent_call_logs`. Reads also cache analytics pages. The primary key deduplicates events by organization and interaction ID; a history index supports tenant/date pagination. Provider-scope metadata prevents archived calls being fetched through a replacement provider connection.

Switching off or admin suspension does not remove history. If analytics is unavailable, the API serves saved records with an explicit warning that recent calls may be missing. When analytics returns no calls but completion events are saved, those saved calls are shown while analytics catches up. Saved transcripts remain available on provider failure; recordings are fetched from the provider and can become unavailable. Transcript details must first belong to a known call in the tenant's history. Client lists support load-more pagination.

The application does not claim all remote calls have been backfilled: configure the completion tool before launch, and browse historical analytics ranges as needed. Saved data is retained until a platform retention process removes it; agree an appropriate retention period with the organization before production use. Never log tool keys, API keys, transcript bodies or caller numbers in operational logs.

## Migration — applied by the owner

File: `supabase/migrations/20261024075411_managed_call_service.sql`.
The same-named backend migration is used only by the disposable local/test database. Do not run both files against production.

This migration **turns existing voice integrations off** and moves active requests to setting_up, because old connections have no verified assigned number/services. It preserves credentials, bookings and resource selections, freezing previous business-wide assignments to today's explicit spaces. Plan a maintenance window and reverify/re-enable existing connections after deployment.

Prerequisites: the booking schema, original Sarvam voice/automatic setup migrations, admin-panel migration, and the repository's earlier migrations (through `20261024050810_permanent_team_deletion.sql`). Keep `BOOKING_SECRETS_KEY` available and backed up; it is the existing server-only base64 32-byte encryption key. Back up the database before applying.

Run these read-only checks in the intended project first:

```sql
SELECT name FROM booking_app.schema_migrations
WHERE name IN ('20261022100000_sarvam_voice_agent.sql',
 '20261022110000_sarvam_automatic_setup.sql','20261023100000_admin_panel.sql',
 '20261024050810_permanent_team_deletion.sql','20261024075411_managed_call_service.sql')
ORDER BY name;
SELECT sarvam_org_id,workspace_id,app_id,count(*)
FROM booking_app.sarvam_integrations WHERE app_id<>''
GROUP BY sarvam_org_id,workspace_id,app_id HAVING count(*)>1;
SELECT organization_id,status FROM booking_app.agent_call_requests ORDER BY created_at;
SELECT grantee,privilege_type FROM information_schema.role_table_grants
WHERE table_schema='booking_app' AND table_name IN ('sarvam_integrations','staff_assignments');
```

The new migration must not already be recorded. Duplicate provider agent assignments must be resolved before applying; the new unique index intentionally rejects them. `booking_api` needs its existing integration/assignment privileges. Confirm no live authoring job is running.

Run the entire Supabase migration file once in SQL Editor. It includes BEGIN/COMMIT, private-schema permissions and application migration registration. Do not run a bulk `db push` that also applies unrelated pending files.

Validate:

```sql
SELECT column_name,data_type FROM information_schema.columns
WHERE table_schema='booking_app' AND table_name IN ('agent_call_requests','sarvam_integrations')
AND column_name IN ('requested_services','approved_services','phone_number','deployment_id','verified_at','verified_by','version')
ORDER BY table_name,column_name;
SELECT count(*) AS enabled_connections FROM booking_app.sarvam_integrations WHERE enabled;
SELECT count(*) AS unsafe_assignments FROM booking_app.staff_assignments a
JOIN booking_app.sarvam_integrations s ON s.membership_id=a.membership_id
WHERE jsonb_array_length(a.resource_ids)=0;
SELECT indexname,indexdef FROM pg_indexes WHERE schemaname='booking_app'
AND tablename IN ('sarvam_integrations','agent_call_logs');
SELECT grantee,privilege_type FROM information_schema.role_table_grants
WHERE table_schema='booking_app' AND table_name='agent_call_logs';
SELECT name FROM booking_app.schema_migrations WHERE name='20261024075411_managed_call_service.sql';
```

Immediately after migration expect zero enabled connections, zero unsafe assignments, both uniqueness indexes and the call-history index, one migration record, and only `booking_api` SELECT/INSERT/UPDATE access on the new table (plus database-owner privileges).

If migration execution fails, `ROLLBACK;` the failed transaction, correct prerequisites and retry the whole file. Do not manually register an incomplete migration. For application rollback, leave the additive schema in place and disable integrations before reverting binaries. Dropping columns/tables loses settings, verification and saved call history. Restoring the database backup is the full schema recovery path and should be rehearsed separately; it has not been performed by these code tests.

## Deployment and verification

After migration validation, deploy the backend first, then the admin panel and Flutter clients through the existing deployment process. This change does not deploy anything, publish an agent, place calls or install an APK. Old clients must update: request and settings mutations now require services/versions.

Checks from the repository:

```bash
# Run in backend/
node --import tsx --test --test-concurrency=2 test/*.test.ts
# Focused automatic setup checks:
node --import tsx --test test/admin-sarvam.test.ts test/sarvam-authoring.test.ts test/edge.test.ts
npm run build
npm run edge:check
npm run edge:build
# Run in admin-panel/
npm run typecheck
npm run build
# Run at repository root
flutter analyze
flutter test test/agent_calls_test.dart
```

Acceptance: owner requests selected services; support staff cannot configure; super admin saves number/services; wrong deployment or number fails verification; unverified activation fails; client copies the number and selects spaces; enquiries-only cannot book; unselected/new spaces remain inaccessible; booking retries do not duplicate; suspension and the client switch block actions; completion/history remain accessible while paused; foreign call IDs are refused; saved history remains visible on provider failure. Review mobile and desktop layouts with enlarged text.

Monitor backend errors, verification failures, rejected tool operations, completion delivery failures, missing history and provider latency. Admin/control actions are audited without secrets. Use the existing database backup strategy for settings and saved history. Maintain separate provider availability alerts; a successful one-time verification does not guarantee the provider stays online.
