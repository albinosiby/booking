# RK Groups call agent setup

Organization: `RK Groups` (`9a80ffc3-f5a9-4298-a7a1-60e3832f194b`).

The user selected `+918071582699` and confirmed that both rescheduling and
cancellation must be limited to bookings originally made by call, belonging to
the caller. The selected number remains bound to the paused `Edens Sports`
deployment (`Edens-Sport-19c31e54-78be`). It has not been released or reassigned.

## Completed in Sarvam

Created the separate agent `RK Groups BookingOS`, ID
`RK-Groups-B-f5a78251-584d`, draft version 1, through the connected Codex MCP.
Verified its inbound greeting and English initial language by reading them back.
The later setup attempt saved the live-catalog variable, seven HTTP tool
definitions, the RK Groups booking prompt including the call-only modification
rule, call goal and voicemail message. The existing silence nudge is present.
Tools are enabled in draft version 1, but authentication is not configured.
There is no committed version or deployment. Do not publish this incomplete
draft as a working booking agent.

Sarvam MCP refuses attaching a workspace secret to this BookingOS backend URL
because the URL is not in its server-managed allow-list. Its supported
alternative is selecting the credential in the console. A staged secret named
`bookingos_rk_9a80ffc3_f5a9` was created, but its generated value was never saved
as a BookingOS tenant tool key and is not attached to any tool. Replace its
value with the actual BookingOS-generated tool key before selecting it; simply
selecting the staged secret would not authenticate to BookingOS.

The console workspace switch was resolved: RK Groups BookingOS is visible in
Thadevoos's Organisation. Before any further setup, the user explicitly chose
to handle everything manually. All external setup work stopped. The number and
old paused deployment remain unchanged; no live database writes, schema
changes, commits, test calls or bookings were performed.

The call-end tool uses the current Sarvam system variables
`call_duration_seconds` and `interaction_transcript`. The corresponding local
provisioning adapter and contract test were corrected. All seven adapter tests,
backend build, Edge type check and Edge bundle passed.

## Backend enforcement prepared

Phone booking lookup now requires `bookings.created_by` to equal the tenant's
restricted voice membership user ID (`sarvam:<organization UUID>`), in addition
to matching the caller phone, organization, permitted spaces, confirmed status
and future date. Staff/app/website bookings are excluded even when the caller
knows the reference and has the same phone number.

Reschedule and cancellation write transactions independently check the creator
after locking the booking. Ordinary staff management remains available. The
shared agent prompt explains this restriction. No database migration is needed.

## Remaining connection work

Validation completed: all 8 Sarvam booking tests and all 45 booking/call-service
regressions passed. Backend TypeScript build, Edge TypeScript check, Edge bundle,
changed-file formatting and `git diff --check` passed. The generated
`supabase/functions/booking-api/index.ts` includes the call-origin checks and is
ready for the user to deploy. The user chose to enter connection details
themselves after browser access became unavailable.

The signed-in deployed admin overview was verified, but browser access became
unavailable before connection setup could proceed. No live database data was
changed during this work. Read-only verification found RK Groups' call request
still requested, its integration disabled, an existing workspace API key, the
old Edens Sports agent ID and no tenant tool key or saved phone/deployment.

1. Deploy the updated `booking-api` generated Edge Function source after the
   validation below passes. Preserve existing secrets and internal auth settings.
2. Open RK Groups' request in the authenticated admin panel and expand manual
   connection setup. Configure the new agent ID and the existing correct Sarvam
   organization/workspace. Use the saved workspace API key without exposing it.
3. Generate RK Groups' tenant tool key through the admin setup. Store it directly
   as a Sarvam workspace secret; do not commit or paste it into documentation.
4. Review the already-created `bookingos_spaces` and six HTTP tools from
   `backend/src/sarvam/sarvam-booking-config.ts`, plus the completion event tool
   from `sarvam-provisioning-remote.ts`. Bind caller phone and interaction ID to
   trusted Sarvam system context. Bind tool authentication to the tenant secret.
5. Review the saved RK Groups prompt, goal, silence nudges and voicemail.
   Read back the prompt and tool definitions, authenticate every HTTP tool with
   the actual tenant tool key, and verify tenant scope before committing.
6. Release the old paused deployment's number only when the new configuration is
   ready, retaining its prior configuration for recovery. Create the RK Groups
   inbound deployment using exactly `+918071582699`; record the returned
   deployment ID in the manual connection form. Release/rebind operations need
   to follow Sarvam's supported lifecycle; do not un-onboard the phone endpoint.
7. Verify the connection, mark the request connected, and let RK Groups select
   spaces and enable call booking. Verify call-created booking changes succeed
   and app/staff bookings are refused. No real booking or call was made here.

Recovery: before number reassignment, the prior paused deployment is unchanged.
Keep the new agent as a draft until backend/tool verification is complete. Roll
back source to the prior revision only while phone booking remains disabled,
because the earlier backend lacks the requested call-origin restriction.
