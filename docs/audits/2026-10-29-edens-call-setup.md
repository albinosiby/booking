# Edens call-service setup

Client organization: `Edens` (`76953d3e-f348-4406-838a-f9ea77355c9b`).
Requested and approved services: booking and rescheduling only. English only.
Rescheduling is restricted to the trusted caller's call-created bookings.
Cancellation is disabled and no cancellation tool is attached.

## Provider configuration

- Agent: `Edens BookingOS`, `Edens-Booki-75fc4acc-472b`.
- Inbound deployment: `Edens-Booki-0e6a9dd6-0d8b`.
- Phone: `+918071582699`.
- Sarvam organization: `019f2836-c1ad-7242-874a-39a01f469ac5`.
- Sarvam workspace: `019f2836-c1b1-71b5-9c95-588b6e8d04f5`.
- Telephony connection: `fffde8a2-9a-dd5cd582-d65f` (Sarvam managed Vobiz).
- Schedule: every day, 00:00 to 23:59, Asia/Kolkata.

Configured through the authenticated Sarvam console because the Sarvam MCP was
not available in this session. Six HTTP tools were created: catalog on start,
availability, booking, caller bookings, reschedule, and completion event on end.
Every endpoint uses the existing BookingOS `/voice/v1` API. Caller identity and
interaction IDs use trusted platform context. The completion event uses
`call_duration_seconds` and `interaction_transcript`. The catalog saves its
message into `bookingos_spaces`.

Manually reviewed the booking tool's caller-context fields and numeric
`expected_total` field. Corrected the generated paise description to rupees
(`total_minor / 100`); the provider assistant also corrected the availability
description and made date/time formats explicit. The prompt requires actual
availability/pricing, read-back and explicit confirmation, and successful backend
responses before claiming a booking or change.

Committed version 1 and created the inbound deployment. Version 1's note
explicitly records that private tool authentication was pending. After the
private handoff and tool verification described below, committed version 2 and
updated the same inbound deployment from v1 to v2 using pause/edit/resume. The
console shows Active, Edens BookingOS v2, English, the same number and schedule.
The editor automatically created a successor draft v3; the deployment uses the
committed v2.

## Approved transfer from RK Groups

The user explicitly selected RK Groups' number and then separately approved
deleting its existing inbound deployment, releasing the saved number assignment,
revoking its tool key, and assigning the number to Edens, acknowledging downtime.

RK Groups: `9a80ffc3-f5a9-4298-a7a1-60e3832f194b`.
Removed provider deployment: `R-K-Groups-15e23b67-2fc0`.
Its agent `RK-Groups-B-f5a78251-584d` was preserved.

A guarded transaction disabled RK Groups' integration and voice membership,
cleared only its phone/deployment and tool-key assignment, cleared verification,
and paused its request with a client message. An admin audit record identifies
the user-authorized assisted transfer. Bookings, payments, spaces and call logs
were untouched. Edens' connection was subsequently saved through the signed
admin panel, including the API key entered privately by the user, the new agent
and deployment IDs, selected phone and exactly the two requested services.

The first guarded transaction rolled back because Edens had moved from requested
to in-review. A fresh read verified version 2 in-review with the same requested
services, and the second transaction used those exact preconditions. No schema
changes or migrations were performed.

Recovery snapshot (local, restricted permissions; contains hashes and saved
configuration, not plaintext keys):
`.local/backups/edens-phone-transfer/1793263720460-before.json`.

Restoring RK Groups requires a separately approved reverse number transfer and
recreating its provider deployment, since deletion cannot restore the old
provider ID. Review the snapshot and current versions, restore only the scoped
integration/request/membership fields, and use the newly returned deployment ID.
Do not overwrite current client activity or restore the whole database.

## Private credential handoff and tool verification

BookingOS now shows Replace tool key and enables Verify connection, confirming
that Edens has a generated tool key. After the user reported finishing the
private handoff, a provider metadata read found that the intended secret
`bookingos_edens_76953d3e` was still absent from the correct workspace. All six
tools in draft v2 instead selected `bookingos_rk_9a80ffc3_f5a9`, whose backend
key was revoked during the approved transfer. The draft has not been published
or treated as verified.

The user was asked to create a separate secret named
`bookingos_edens_76953d3e` in that workspace, privately paste the generated Edens
`bkv_…` key, submit Create and confirm its name appears in the list. Do not edit
or overwrite the RK Groups secret. The workspace API key must not be used as
this tool secret. No secret value has been read or placed in chat.

The user then confirmed creation, and the exact separate secret appeared in the
workspace list. Reference ID: `01a186f1-3d32-7ac3-87e3-c8b792fe7d1d`.
Sarvam's chat assistant could read metadata but could not attach credentials to
these external URLs. Used the normal console tool editor to save all six tools
with API Key authentication, header `X-API-Key`, location header and the Edens
secret reference. The four callable response templates were corrected from
`{{response.message}}` to `{{message}}`, matching the integration generator and
the backend's top-level response field. Catalog still saves response field
`message` to `bookingos_spaces`; start/end spoken templates remain blank.

A fresh provider read-back confirmed all six persisted secret references,
existing tool IDs, POST URLs, JSON content type, 12-second timeouts, lifecycle,
numeric/required fields and trusted caller/call mappings. No cancellation tool
was added. A catalog-only console request with the saved reference returned
`FORBIDDEN`, message `The voice agent is turned off.`, request ID
`c8c23e93-8b80-441a-8294-a0ef66a5d810`. This verifies key authentication while
the client's switch remains off. No booking, reschedule, call-event write or
real/playground call was made.

BookingOS verification passed after deployment activation. The admin page
persisted `Active`, `Verified`, and client status `Connected`, including after a
full reload. Approved services remain exactly Booking and Rescheduling. Saved a
client-facing message explaining the number, space selection and enable step,
plus an internal note recording the approved transfer and committed version.
Client booking was left off so the client can choose spaces and explicitly
enable service, then test using a real inbound call. Connection verification
does not itself inspect tool authentication or perform a booking; the separate
catalog check above covers authentication, and a real call remains untested.

Proof screenshot:
`/Users/albinosiby/.codex/visualizations/2026/10/24/01a16cc4-0299-7471-9858-4089ad07ffde/edens-connected-verified.png`.

No application source changes were made for this setup; existing unrelated
workspace edits were preserved.

## Interrupted booking incident and recovery fix

The user reported a confirmed booking followed by the agent saying the slot was
occupied. Read-only checks found booking `BK-85EF267FDE0C`, Full Ground,
29 October 2026 18:00–19:00 Asia/Kolkata, INR 1,500, confirmed and created by the
Edens call membership. No live booking was changed during diagnosis or repair.

Sarvam's interaction trace for `20261029/e6c9ad61-16:15:09-969bdd2c` showed two
booking executions about two seconds apart. The first had no recorded model
response, while the second returned the backend inventory-conflict message.
The caller interrupted the first tool turn. The precise database interleaving
was not available, but a deterministic isolated regression reproduced the same
conflict when both requests passed the initial replay check before one committed.

Approved source fix:

- On an unsuccessful booking, reschedule or cancellation attempt, recheck the
  original actor/organization/call command for a committed result. Recover only
  that exact result after checking current service permission. Missing call IDs,
  another caller and another request do not recover unrelated bookings.
- Preserve the original failure when no committed result exists. Transactions
  still own inventory and command-result atomicity; no new locks or schema are
  needed.
- Replayed results describe the booking's current space and status. Caller
  lookup includes space and activity in both structured and spoken results.
- Prompt and failure replies treat interruptions and missing results as uncertain
  outcomes. Wait for pending writes, reconcile caller bookings where permitted,
  and avoid suggesting another slot before recovering the original outcome.

Validation: the first regression failed with the incident's inventory conflict
before the fix and passed afterwards. All 75 related checkout tests passed.
Independent production-baseline validation passed all 16 Sarvam cases, Edge
typecheck/build, the health assertion, 25 other Edge cases and 24 authoring/setup
cases. A preexisting stale health-test expectation in the baseline was aligned
with the new release revision.

The deployed backend source was backed up via the authenticated code editor.
An isolated git HEAD build matched it byte for byte (SHA256
`c3e05d7ba5e53783b9820eee032db9e89d73d88d3512899fa419ce34308fbd94`). The
release is rebuilt from that exact baseline with only the voice service,
default recovery prompt/failure replies and public health revision changed;
unrelated working-copy feature changes are excluded. No migrations were applied.

Durable release folder:
`.local/releases/2026-10-29-voice-retry-recovery/` contains the API artifact,
exact prior-production rollback artifact, scoped source patch, validation
manifest and reviewed English Edens prompt. API artifact SHA256:
`7f48d6860c87744bf59fedd9f738f9776390764ecb13d2197a05a71c10db0f37`.

**Rollout pending:** Chrome restarted and displayed blank editor pages while
preparing the production editor. The pages briefly recovered, but subsequent
paste/control actions failed again. No Deploy updates action was performed.
A final public `/health` read confirmed the live backend still advertises
`2026-10-29-business-booking-status`, not the recovery release.

Genie reported saving and reading back the Edens v3 draft's approved prompt,
including pending-write and uncertain-result recovery and removal of the old
contradictory rules. Six tools, credentials, language, number and deployment were
reported unchanged. No agent commit or inbound version switch was performed for
this fix. The live agent remains on committed v2 until rollout is completed.

To finish: restore the console pages, verify the API editor contains the exact
isolated release, deploy, and check `/health` returns
`2026-10-29-voice-retry-recovery`. Verify Edens draft recovery instructions and
the two write-tool failure replies, commit it, update existing deployment
`Edens-Booki-0e6a9dd6-0d8b` to the new committed version via pause/edit/resume,
then verify the BookingOS connection. Preserve number, credentials, scopes and
client space controls. Test with an explicitly requested controlled call, not by
replaying a live write from this incident.

Application recovery: redeploy `production-rollback-index.ts` from the release
folder if needed, and point the Edens deployment back to its prior committed v2.
Do not restore the database or alter the confirmed booking to roll back code.

### Subsequent publishing request through MCP

The user explicitly requested updating the two failure replies, committing v3,
and switching/resuming the existing inbound deployment using MCP. A fresh public
health read now confirms the backend recovery release is live:
`2026-10-29-voice-retry-recovery`.

The existing local Sarvam installer authorization is valid. Connected through
the supported MCP SDK using the installer's private credential store; no token
was read into chat or copied from Codex. Narrow MCP reads verified draft v3,
committed v2, English only, the recovery prompt, and six enabled BookingOS tools.
The existing deployment remains active on v2 with its unchanged number and
schedule. Tool IDs in v3 differ from v2; use fresh version-bound metadata.

Sarvam MCP refuses the text-only `configure_app_tool` patch on the credentialed
booking tool because its destination is outside the MCP server's credential URL
allow-list. A read-back confirmed all six tools remained unchanged. No auth
field was removed or changed to bypass that restriction. The console fallback
also timed out. The user was asked to save the same exact uncertainty reply in
the booking and rescheduling tools manually, leaving v3 uncommitted. Once that
is saved, MCP can verify the tool configs, commit v3, then pause/patch/resume the
existing deployment. No commit or deployment mutation has occurred yet.

Current metadata snapshots, excluding credential values, are preserved in
`.local/backups/edens-v3-publish/`. Compare all HTTP tool settings before/after,
allowing only the two requested `on_failure` values to differ, before committing.

### Publishing completed after the user's console changes

The user reported saving both failure replies, committing and deploying v3.
Read-only MCP verification confirmed committed v3 but found the existing
deployment still paused. Pinned reads of immutable v3 confirmed both booking
and rescheduling failure replies exactly match the requested uncertainty text.
All six HTTP tool configurations match the prior v3 snapshots except those two
`on_failure` strings; IDs, enabled state, URLs, authentication references, body
fields, lifecycle and timeout are unchanged. English-only delivery and recovery
prompt SHA `811d279a18fcad9d` are preserved.

Resumed the existing deployment through MCP, then read it back: active,
`Edens-Booki-0e6a9dd6-0d8b`, agent `Edens-Booki-75fc4acc-472b`, committed v3,
number `+918071582699`. The connection, schedule and webhook are unchanged.
Provider update timestamp: `2026-10-29T12:37:56.354694Z`. A fresh public health
check confirms backend revision `2026-10-29-voice-retry-recovery` is live.

Saved committed configuration and final deployment evidence in the existing
`.local/backups/edens-v3-publish/` folder. No new call or booking was created,
and the incident's confirmed booking was not changed. A controlled real inbound
call remains the final user acceptance test.
