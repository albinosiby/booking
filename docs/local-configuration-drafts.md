# Local configuration drafts

Turf, court, pool and hall setup use feature models/repositories/Cubits with a shared local draft coordinator. Continue and resource completion do not call the API. Each edit schedules a coalesced local write after 300 ms; Continue requests an immediate background checkpoint. Draft writes never set the cloud-saving flag or block editing/navigation.

## Persistence and recovery

`ConfigurationDraft` stores a format version, original business version, complete configuration and navigation position. `ConfigurationDraftRepository` owns persistence. Its production implementation uses OS secure storage and scopes each key to the backend/project, organization, membership and business. Other accounts cannot restore a draft through the UI. Signing out does not publish or discard the original owner's local work.

Local serialization preserves unfinished numeric text, empty values, names and prices. The `_local` form fields exist only in local JSON. Ordinary `toJson()` continues producing the existing API representation; cloud validation and contracts are unchanged.

Writes are serialized, debounced and guarded against stale completion. Leaving a screen flushes pending local work. App pause requests a flush. Recovery disables editing briefly while the stored draft is read; a storage read failure can be retried without overwriting that draft. Local write failures retain the in-memory form and display a retry action. As with any autosave, a forced process kill before an outstanding local write completes can lose the last unsaved input; the UI only says saved after storage confirms the write.

## Final commands

Only explicit Save changes / Activate commands call the remote repositories. The Cubit checkpoints locally before sending. A successful final command clears the local draft. A failed/uncertain command keeps the draft and existing response-loss recovery checks. Controls are disabled only for final cloud saving, existing workspace refreshes and initial local recovery—not background autosaving.

A restored draft based on a different business version remains available locally, but publishing is blocked. Reload saved settings (with the existing discard confirmation) explicitly replaces the local draft with cloud state. Backend version/tenant/booking guards remain authoritative for concurrent changes after the editor opened.

Court/pool guided actions now read Continue and Continue & add another. They validate the selected resource and retain all resources locally. Direct court/pool/hall section editors use Continue to return to their list; their overview/review Save changes and Activate actions publish the accumulated configuration. Turf retains its direct editing Save changes action and wizard Activate action.

Active court/pool/hall settings already remain active when valid changes are saved. Turf now follows the same rule: incomplete active edits are rejected transactionally. The frontend avoids an extra Activate request when the saved server snapshot is already ready. New-business activation still saves configuration and invokes the existing activation endpoint; both requests happen only after the final Activate command.

## Verification

Tests cover immediate Continue with storage deliberately blocked, no cloud calls during resource completion, exact incomplete form recovery across all four types, membership isolation, old-version conflict protection, storage retry and final save cleanup/failure. Existing narrow-screen/large-text UI tests cover final-save-only setup and direct editing. The backend turf test verifies active-state preservation and rollback on incomplete active edits.

No Supabase schema migration is required. Local drafts are never inserted into the cloud database automatically. The API remains hosted on the development Mac until separately deployed.

## Duration controls

Turf, court, pool and hall hourly pricing expose allowed-duration chips without a separate default-duration dropdown. Existing saved defaults remain compatible; Cubits retain an allowed internal default and select a remaining duration if it is removed. API and database contracts are unchanged.

See [configuration review](configuration-review.md) for the summary design and sport-specific diagrams.
