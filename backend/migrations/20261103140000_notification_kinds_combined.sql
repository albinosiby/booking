-- 20261102090000 (subscription fees) and 20261103120000 (call wallet alerts) each
-- replaced the outbox CHECKs without the other's kind. Restore one CHECK for all kinds.
ALTER TABLE booking_notification_events
 DROP CONSTRAINT booking_notification_events_kind_check,
 DROP CONSTRAINT notification_event_source_check;
ALTER TABLE booking_notification_events
 ADD CONSTRAINT booking_notification_events_kind_check CHECK(kind IN (
  'created','cancelled','rescheduled','staff_cash_collected','subscription_fee_due','call_wallet_low','call_wallet_empty')),
 ADD CONSTRAINT notification_event_source_check CHECK(
  (kind IN ('created','cancelled','rescheduled') AND history_id IS NOT NULL AND booking_id IS NOT NULL
   AND business_id IS NOT NULL AND resource_id IS NOT NULL AND settlement_id IS NULL AND cash_details IS NULL
   AND admission_id IS NULL AND due_on IS NULL AND fee_details IS NULL AND wallet_details IS NULL)
  OR
  (kind='staff_cash_collected' AND settlement_id IS NOT NULL AND history_id IS NULL AND booking_id IS NULL
   AND business_id IS NULL AND resource_id IS NULL AND cash_details IS NOT NULL AND jsonb_typeof(cash_details)='object'
   AND admission_id IS NULL AND due_on IS NULL AND fee_details IS NULL AND wallet_details IS NULL)
  OR
  (kind='subscription_fee_due' AND admission_id IS NOT NULL AND due_on IS NOT NULL
   AND business_id IS NOT NULL AND resource_id IS NOT NULL AND history_id IS NULL AND booking_id IS NULL
   AND settlement_id IS NULL AND cash_details IS NULL AND wallet_details IS NULL
   AND fee_details IS NOT NULL AND jsonb_typeof(fee_details)='object')
  OR
  (kind IN ('call_wallet_low','call_wallet_empty') AND history_id IS NULL AND booking_id IS NULL AND business_id IS NULL
   AND resource_id IS NULL AND settlement_id IS NULL AND cash_details IS NULL
   AND admission_id IS NULL AND due_on IS NULL AND fee_details IS NULL
   AND wallet_details IS NOT NULL AND jsonb_typeof(wallet_details)='object')
 );
