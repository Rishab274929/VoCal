-- 0003: per-user Pro entitlement table.
--
-- Source of truth for paywalled endpoints. The iOS app's local StoreKit
-- cache is advisory only and can be tampered; the server now refuses
-- expensive operations unless this table says is_pro = 1 (and the row
-- hasn't expired).
--
-- Population paths:
--   - /api/entitlements/refresh — iOS posts a StoreKit receipt; we verify
--     with Apple and upsert here.
--   - Manual SQL (`wrangler d1 execute ... --command "INSERT INTO ..."`)
--     for early testers / comp accounts. Set source='manual'.
--   - Future: App Store Server Notifications V2 webhook.
--
-- expires_at is unix ms. NULL means "no expiry" (lifetime / manual grant).
-- A row with is_pro = 0 means "we know about this user and they are NOT
-- Pro" — useful for cache invalidation when a subscription lapses.

CREATE TABLE IF NOT EXISTS user_entitlements (
  user_id     TEXT PRIMARY KEY,
  is_pro      INTEGER NOT NULL DEFAULT 0,
  product_id  TEXT,            -- e.g. com.EricSpencer.VoCal.pro.monthly
  expires_at  INTEGER,         -- unix ms; nullable for lifetime/none
  updated_at  INTEGER NOT NULL,
  source      TEXT             -- 'apple_receipt' | 'webhook' | 'manual'
);

CREATE INDEX IF NOT EXISTS idx_user_entitlements_updated
  ON user_entitlements(updated_at);
