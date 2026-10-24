# Agent-call admin tile workflow

## Approved scope and implementation

The Agent Calls list now presents each returned organization request as a fully clickable tile instead of an expanded editing form. Tiles show the organization, requester, status, requested/approved services, customer-note preview and request/update timestamps. Selecting a tile opens the existing organization-specific setup route. The setup screen identifies the organization and groups navigation into connection, agent tools, verification and client status. Client messages and private notes remain editable there.

The existing server-only API/authentication and mutation actions are unchanged. Detail identity uses the existing organization endpoint in parallel with the connection request. No provider credentials are added to tiles. There are no embedded mock records or new dependencies in the application. The backend's existing list limit remains in force; the count explicitly describes results shown, not a global total. No schema changes, live data changes or deployments were performed.

## Verification

- `npm run typecheck`: passed.
- `npm run build`: passed, including both dynamic request routes.
- `git diff --check`: passed.
- Read-only local HTTP fixture checks: populated list, active filter, empty rejected filter, invalid-filter fallback, two organization detail pages and signed-out detail redirect passed (seven checks).
- Browser checks against the local production build: tile click opens the matching organization's configuration; all four section links render; client-status anchor navigation works; generation/verification are disabled without credentials and the active option is disabled without verification.
- Responsive browser measurements: three columns at 1280px, two at 1024px, one at 390px, without document-level horizontal overflow. Mobile configuration also fits the viewport.
- Empty status view offers a working return to all requests. The setup loading placeholder was observed. A simulated missing request displays the scoped error view within the admin shell; retry remains recoverable and Back to requests restores the tile list.

All populated browser checks used disposable local fixtures served only over loopback, never production records. Screenshots are local fixture previews, not evidence of production data. No provider API keys, live verification, key regeneration or configuration writes were exercised by these read-only checks. Existing mutation behavior is preserved rather than re-certified here. A separate approved deployment is required to publish the redesign.
