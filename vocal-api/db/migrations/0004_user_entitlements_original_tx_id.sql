-- 0004: store Apple's original_transaction_id on user_entitlements.
--
-- Apple guarantees that within a subscription "chain" (purchases, renewals,
-- and re-subscriptions after a lapse) the original_transaction_id stays the
-- same for the lifetime of that subscription. It uniquely identifies the
-- purchase across:
--   - Auto-renewals (each renewal has its own transaction_id but the same
--     original_transaction_id).
--   - Sandbox vs production.
--   - Future App Store Server Notifications V2 webhooks (which key
--     subscription events on original_transaction_id, not user_id).
--
-- Why we want it:
--   - Idempotency: a duplicate receipt sync becomes recognizable.
--   - Multi-account-on-same-AppleID detection: if two VoCal accounts present
--     receipts with the same original_transaction_id we can flag/de-dupe.
--   - ASSN V2 readiness: webhook payloads include original_transaction_id;
--     a column to index on means O(1) lookup instead of scanning by user_id.
--
-- We deliberately do NOT make this UNIQUE — two VoCal accounts presenting
-- the same Apple receipt is a real (though rare) scenario, and we'd rather
-- detect it explicitly than have one insert silently fail with a constraint
-- violation. An index is enough for lookup speed.

ALTER TABLE user_entitlements
  ADD COLUMN original_transaction_id TEXT;

CREATE INDEX IF NOT EXISTS idx_user_entitlements_original_tx_id
  ON user_entitlements(original_transaction_id);
