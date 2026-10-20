# Minimum pool group offers

Group size rules support `exact`, `up_to`, and `at_least`. An `at_least` offer with 15 people appears as **15+ people**. It accepts 15 or more swimmers at the configured total package price, subject to the pool's capacity, remaining capacity, applicable hours and duration. It does not charge the package price per person. Existing exact and maximum offers retain their meaning.

Configuration validates the threshold against each eligible pool's capacity. Booking selection starts at the minimum for an at-least offer; staff can increase it. The Cubit checks the selected offer's group bounds before requesting a quote. The server independently checks bounds and capacity; booking transactions retain the shared overlapping-capacity checks.

No database migration is required: the offer rule is stored in the existing JSON configuration. Existing offers are not rewritten.

## Activate the backend change

The generated deployment source is `supabase/functions/booking-api/index.ts`. The live function must be updated before saving new at-least offers from the updated app.

1. In the existing **booking** Supabase project (`scwwkaywewecspsrskft`), open **Edge Functions → booking-api → Code**.
2. Replace the function source with the generated `index.ts` and select **Deploy updates**.
3. Preserve the existing function settings, secrets and custom Supabase Auth verification (`verify_jwt=false`). No SQL is needed.
4. With a pool capacity of at least 20, configure a 15+ offer. Verify 14 is rejected, 15 and 16 receive the same package price, and a count exceeding remaining capacity is rejected. Use nonfinancial quote checks where possible.

Backend tests cover exact/up-to behavior, minimum boundaries, invalid counts, pool capacity and shared booking capacity. Flutter tests cover configuration round trips, labels, minimum capacity validation, booking bounds and existing pool/booking workflows.

An older backend rejects the new mode; deploy the updated backend before using it. Older installed clients do not fully understand minimum offers, so update clients before staff use newly configured minimum offers. Rolling back to code without at-least support requires first changing those offers to a supported mode with the owner’s review.
