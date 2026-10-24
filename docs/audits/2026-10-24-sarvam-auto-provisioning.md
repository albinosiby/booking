# Super-admin automatic Sarvam provisioning

The approved change adds a platform-level MCP connection and per-client resumable setup. Super admins configure the workspace credentials once, authorize through Sarvam SSO, select a base voice template, then approve a client's requested services and choose its onboarded number. The API clones a separate agent, installs a private per-client tool key, six booking tools and an on-end call-log tool, writes instructions, reads back the owned configuration, commits a version, deploys and verifies before activating client controls. Activation leaves the client switch off.

## Boundaries

- One private singleton table stores encrypted API/OAuth credentials and a one-use PKCE sign-in state. Existing integration rows store per-client progress and number reservations. The additive migration is prepared; the user must apply it.
- Only super admins and signed admin-panel requests can authorize or advance jobs. Client contracts and tenant-scoped runtime permissions are unchanged.
- Reconnect restores management authorization without recreating agents or disabling existing calls. No refresh-token or permanent-session assumption is made.
- The browser advances bounded steps while open; closing it pauses progress until Resume. No background queue is implied.
- Provider-generated agent IDs are recovered after ambiguous creation by a persisted unique name; committed-version reads and deployment inventory reconcile lost responses. Leases, optimistic versions and uniqueness constraints guard concurrent actions.
- The OAuth return GET is a no-store, same-origin Continue form; completion POST requires the existing strict admin session and a signed API request. Public callback GET access does not authorize mutations.

## Provider contract evidence

The connected Sarvam MCP schemas and public playbooks were read during implementation. They confirm native cloning via clone_from/name/clone_version, prompt text authored only via prompt, onboarded inventory through list_endpoints, separate secret storage, typed webhook tools, committed-version reads, and deployment results returning id. No live agent was created, modified, committed or deployed, and no number was purchased, assigned or called. An automatic approval check refused reading one existing agent's configuration; no such configuration was retrieved. Published schemas/playbooks provided a safe alternative.

## Verification

- Focused automatic provisioning integration tests cover authorization, PKCE/state replay, encrypted credentials, service subset validation, number reservations, missing capabilities, expired/revoked sessions, native clone recovery, committed-version recovery after a lost response, deployment recovery, per-client keys, suspension, tool tampering, and API-key rotation.
- Existing admin, agent-call, Edge, authoring and legacy-setup regression tests passed during implementation.
- Admin production build and API/Edge TypeScript builds were checked. The Edge bundle is generated from source.
- Local browser checks use disposable fixture records only: reconnect return/Continue, number choice, approved service subset, automatic progress to Connected, and narrow-screen overflow.
- Local HTTP checks confirm a cookie-free OAuth GET returns the safe Continue form with no-store/no-referrer while a cookie-free POST redirects to login.

Live OAuth client registration/allow-listing, the selected voice template, provider tool readbacks and phone routing still require a staging acceptance run after deployment. Schema compatibility and local fixtures do not certify live call quality or remote connectivity. Database restoration has not been rehearsed.
