# Configuration review

Turf, court, pool and hall configuration share reusable review components in the design system. Feature review screens keep their typed models and receive edit callbacks from the parent setup screens; navigation stays in the existing feature Cubits. Repositories, API contracts, database schema and final-save/local-draft behavior are unchanged.

## Screen behavior

Review uses a compact app-bar heading, business name, enabled-space counts and a readiness message derived from existing completeness validation. A clear error explains incomplete setup. Each space has an edit shortcut, opening hours and grouped price rows. Seasonal date ranges remain visible with their applicable weekdays. Preparation/cleanup and secondary product details are expandable. Every expandable section owns its own page-storage bucket so its boolean expansion state cannot collide with the wizard's scroll offset.

New-business final activation remains the primary action. The review's Save changes action is visually secondary until the business is active. Existing validation, busy guards and explicit save commands remain in force. No mutation occurs just from reviewing or using an edit shortcut. Obsolete text claiming bookings are unavailable has been removed.

Pool summaries distinguish per-person admission, group totals and plan prices. Attendance allowance remains separate from expiry; hall hourly rates and session/package totals remain distinct. Full-day operation is labelled Open 24 hours for turf/courts/pools instead of displaying equal midnight endpoints. Hall full-day products retain their actual configured session interval.

## Turf illustrations

`FootballGroundDiagram` and `CricketGroundDiagram` are independent reusable vector components based on the supplied references. Both accept the physical ground's split/single arrangement. Split football shows crosswise half-court markings; split cricket shows the two smaller pitches alongside the main pitch. Single grounds omit these subdivisions. The full football field's ordinary centre line remains a sport marking, not a separate booking space. Drawings are illustrative and are not measured plans or booking controls.

The diagrams appear in the space setup and summary; arrangement and individual pricing offer expandable previews. Only the selected sports are shown in setup. Review shows sports with enabled offerings on that ground. Football and Cricket describe the same ground, and text explains that shared space cannot be double-booked. Cricket linked to Football shows its diagram and a concise shared-pricing note rather than repeating every price.

## Verification

Existing configuration workflows cover activation, direct editing and narrow-screen/large-text layouts. Dedicated review tests cover split/single diagram semantics, 24-hour labels, price units, edit callbacks, unchanged configuration and separate pool attendance/expiry/group details. Optional preview captures use `REVIEW_PREVIEWS=true` and `REVIEW_FONT_DIR` pointing at the Flutter SDK material font directory; output is private under `.local/review-previews`. Normal tests do not require that environment or write previews.

## Pricing expansion regression

The existing turf pricing page also needs distinct PageStorageKeys for its shared-hours and per-offering preparation/cleanup sections. Otherwise an unkeyed ExpansionTile can read the surrounding scroll view's double offset as a bool, producing the red-screen type-cast error. The keys are stable and unique per business/offering. The archived-accounts section now also has a distinct key. A turf widget regression seeds a nonzero stored scroll offset, opens shared hours, switches between two offerings, expands preparation/cleanup and verifies independent state without repository writes.

## Empty configuration lists

The shared empty-state component supports a card-free presentation. Court, pool and hall item lists use it for Nothing added yet: the icon, title and message are horizontally centered across the content width above the Add button, with no background panel. Other empty states retain their existing presentation. This is a layout-only change.

## Pricing follows opening days

Price-rule weekday choices show only the resource's opening days. Weekday/weekend presets select only allowed days, and All open days replaces the unrestricted preset in constrained editors. The reusable weekday picker is shared by court/pool/hall hours editors and turf price rules. Parent opening-hour editors still allow choosing all weekdays.

Immutable configuration methods restrict dependent day lists through existing Cubit edits. Court/pool admission tariffs follow their own resource; turf rules follow effective offering hours within shared hours, with linked Cricket synchronized afterward; hall hourly rules follow hall hours and package prices follow both hall and option hours. Pool group offers and swimming/coaching plans use the intersection of their eligible pools' opening days, matching existing backend validation. Date ranges, time windows, prices, durations, identities and allowances are preserved.

Narrowing opening days removes those days from existing rules. If no days remain, the rule and amount stay in the local draft and the UI asks for an open day or rule removal. Validation blocks incomplete publication. Reopening a day does not silently assign a previously removed price. Restoring older local drafts also restricts their pricing days before editing resumes. These edits keep the existing background local-draft flow; no remote write happens until explicit Save/Activate. Backend validation remains authoritative, and no database or API contract changes are required.

An empty court resource/pricing list displays only the centered empty state and Add court action beneath its normal page heading/navigation. Continue, save, draft-status and reload footer controls appear once a court is present.

## Pricing time ranges follow opening hours

New admission/hourly/turf rules inherit the resource's opening interval, including canonical midnight and explicit full-day mode. A shared constrained range editor replaces independent price-rule time inputs. Its dialog edits both boundaries together, shows opening limits and commits only a valid contained interval. Open 24 hours pricing is available only when the selected opening schedules permit it. Backend validation remains authoritative.

Pool offers and plans are constrained to every eligible pool's hours. Use opening hours chooses their longest shared continuous interval on the selected operating days; disjoint schedules require changing eligibility/opening hours. Ordinary and overnight ranges use the same operating-window containment semantics as existing configuration validation. Date ranges and selected weekdays remain separate and retain their values.

When opening hours change, a rule that previously covered the entire opening interval follows the new interval if the rule itself was not independently edited. Custom bands retain their times and amounts; if they become invalid the editor flags them and offers Use opening hours. Incomplete/out-of-bounds configuration cannot be published. Turf linked Cricket is synchronized after the update. Hall hourly rules and full-opening packages follow hall changes; custom morning/evening sessions retain their explicitly chosen hours. Pool full-opening offers/plans follow changed opening hours or eligible-pool intersections.

No API, database schema or repository contract changes are needed. Feature Cubits orchestrate updates through immutable models; draft persistence and final explicit Save/Activate behavior remain in place. UI midnight remains 24:00 with 00:00 in stored values.
