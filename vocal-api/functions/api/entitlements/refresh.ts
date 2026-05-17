// POST /api/entitlements/refresh
//
// iOS posts a base64 StoreKit receipt; we verify with Apple's
// verifyReceipt endpoint and upsert into `user_entitlements`.
//
// Body: { receipt_data: string }   // base64 StoreKit receipt
// Auth: HARD-REQUIRED bearer JWT. The JWT sub is the user_id we write.
//       (Apple receipts are not bound to our user identity; the binding
//       is "whichever VoCal account presents this receipt owns it".)
//
// Response: { is_pro, product_id?, expires_at? }
//
// Apple endpoints:
//   production:  https://buy.itunes.apple.com/verifyReceipt
//   sandbox:     https://sandbox.itunes.apple.com/verifyReceipt
//
// Apple convention: if production returns status 21007 ("this receipt is
// from the sandbox environment"), retry against sandbox. This lets a
// single endpoint handle both TestFlight and App Store receipts without
// the client telling us which.
//
// Required secret: APPLE_SHARED_SECRET — the "app-specific shared secret"
// from App Store Connect → My Apps → App-Specific Shared Secret. Without
// it, this endpoint returns 503 (Apple's API requires it for
// auto-renewable subscriptions).
//
// Product IDs accepted as VoCal Pro:
//   com.EricSpencer.VoCal.pro.monthly
//   com.EricSpencer.VoCal.pro.yearly
//   com.EricSpencer.VoCal.pro.lifetime
// (Adjust ALLOWED_PRODUCT_IDS below if your bundle layout differs.)
//
// Rate limit: 10/min/identity. Receipt validation hits Apple's servers,
// which are reliable but not free; we don't need a busy iOS client
// hammering this on every cold start.

import type { PagesFunction } from "@cloudflare/workers-types";
import type { Env } from "../../../src/types";
import {
  AuthRequiredError,
  authErrorResponse,
  requireUserId
} from "../../../src/lib/auth";
import { checkRateLimit, rateLimitedResponse } from "../../../src/lib/rateLimit";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization"
};

const APPLE_PROD_URL = "https://buy.itunes.apple.com/verifyReceipt";
const APPLE_SANDBOX_URL = "https://sandbox.itunes.apple.com/verifyReceipt";
// Apple's documented "this receipt is sandbox, retry there" code.
const APPLE_SANDBOX_STATUS = 21007;

// Hard cap on receipt size — real receipts are ~10-50KB; anything > 256KB
// is either an attack or a misuse of this endpoint.
const MAX_RECEIPT_BYTES = 256 * 1024;

// Allow-list of product IDs we accept as Pro. Anything else (consumables,
// future tiers, accidental other-app receipts on the same Apple ID) is
// rejected — never silently grant Pro for an unknown product.
const ALLOWED_PRODUCT_IDS = new Set<string>([
  "com.EricSpencer.VoCal.pro.monthly",
  "com.EricSpencer.VoCal.pro.yearly",
  "com.EricSpencer.VoCal.pro.lifetime"
]);

interface RefreshBody {
  receipt_data?: string;
}

// Subset of Apple's response we care about. Apple's full schema is enormous
// (https://developer.apple.com/documentation/appstorereceipts/responsebody);
// we only consume the fields needed to decide is_pro + expires_at.
interface AppleReceiptResponse {
  status: number;
  environment?: "Production" | "Sandbox";
  receipt?: {
    bundle_id?: string;
    in_app?: AppleIAP[];
  };
  // For auto-renewables Apple returns the latest_receipt_info array at the
  // top level (deduped + sorted, most recent last). Prefer this over
  // receipt.in_app when present.
  latest_receipt_info?: AppleIAP[];
  pending_renewal_info?: Array<{
    product_id?: string;
    expiration_intent?: string;
    auto_renew_status?: string;
  }>;
}

interface AppleIAP {
  product_id?: string;
  // Auto-renewable: expires_date_ms (milliseconds since epoch as STRING).
  expires_date_ms?: string;
  // Non-consumable / lifetime: no expiry; check purchase_date_ms instead.
  purchase_date_ms?: string;
  // Refund / chargeback indicators.
  cancellation_date_ms?: string;
}

export const onRequestOptions: PagesFunction<Env> = async () => {
  return new Response(null, { status: 204, headers: CORS });
};

export const onRequestPost: PagesFunction<Env> = async ({ request, env }) => {
  const bindings = env as unknown as Env & {
    DB?: D1Database;
    JWT_SECRET?: string;
    FOOD_KV?: KVNamespace;
    APPLE_SHARED_SECRET?: string;
  };

  const rl = await checkRateLimit(bindings, request, "entitlements/refresh", 10);
  if (!rl.allowed) return rateLimitedResponse(rl, CORS);

  // Auth: hard-required JWT. We tie the receipt to whichever VoCal user is
  // logged in — there is no other way to know which user_entitlements row
  // to upsert.
  let userId: string;
  try {
    ({ userId } = await requireUserId(bindings, request));
  } catch (err) {
    if (err instanceof AuthRequiredError) return authErrorResponse(err, CORS);
    throw err;
  }

  // Need a DB to upsert into.
  if (!bindings.DB) {
    return json({ error: "Server not configured for entitlements (no DB binding)" }, 503);
  }

  // Need the Apple shared secret to verify the receipt.
  const sharedSecret = bindings.APPLE_SHARED_SECRET;
  if (!sharedSecret || sharedSecret.length < 8) {
    return json({ error: "Server not configured for receipt validation" }, 503);
  }

  const contentLength = Number(request.headers.get("content-length") || "0");
  if (contentLength && contentLength > MAX_RECEIPT_BYTES + 4096) {
    return json({ error: "Receipt too large" }, 413);
  }

  let body: RefreshBody;
  try {
    body = (await request.json()) as RefreshBody;
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  const receiptData = (body.receipt_data || "").trim();
  if (!receiptData) return json({ error: "receipt_data required" }, 400);
  if (receiptData.length > MAX_RECEIPT_BYTES) {
    return json({ error: "Receipt too large" }, 413);
  }
  // Sanity check — Apple receipts are base64.
  if (!/^[A-Za-z0-9+/=\r\n]+$/.test(receiptData)) {
    return json({ error: "receipt_data must be base64" }, 400);
  }

  // --- Verify with Apple ----------------------------------------------------
  // First try production; on 21007 retry against sandbox. Apple recommends
  // this pattern explicitly for builds that may run against TestFlight or
  // store receipts interchangeably.
  let appleRes: AppleReceiptResponse;
  try {
    appleRes = await verifyReceipt(APPLE_PROD_URL, receiptData, sharedSecret);
    if (appleRes.status === APPLE_SANDBOX_STATUS) {
      appleRes = await verifyReceipt(APPLE_SANDBOX_URL, receiptData, sharedSecret);
    }
  } catch (err) {
    console.error("entitlements/refresh: Apple verifyReceipt fetch failed", (err as Error).message);
    return json({ error: "Receipt verification upstream failed" }, 502);
  }

  if (appleRes.status !== 0) {
    // Apple non-zero status = receipt invalid. Documented status codes:
    // https://developer.apple.com/documentation/appstorereceipts/status
    console.warn("entitlements/refresh: Apple rejected receipt", { status: appleRes.status, userId });
    return json({ error: "Invalid receipt", apple_status: appleRes.status }, 400);
  }

  // --- Pick the best active entitlement -------------------------------------
  // Prefer latest_receipt_info (auto-renewables). Fall back to receipt.in_app
  // (non-consumables / lifetime). Within either list pick the entry with the
  // furthest-future expires_date_ms; that's the active subscription period.
  const iaps: AppleIAP[] = [
    ...(appleRes.latest_receipt_info ?? []),
    ...(appleRes.receipt?.in_app ?? [])
  ];

  let activeProductId: string | null = null;
  let activeExpiresAt: number | null = null;
  const now = Date.now();

  for (const iap of iaps) {
    const productId = iap.product_id;
    if (!productId || !ALLOWED_PRODUCT_IDS.has(productId)) continue;
    if (iap.cancellation_date_ms) continue; // refunded/cancelled

    // Lifetime: no expires_date_ms → always active once purchased.
    if (!iap.expires_date_ms) {
      activeProductId = productId;
      activeExpiresAt = null; // null = no expiry
      break; // lifetime wins
    }

    const exp = Number(iap.expires_date_ms);
    if (!isFinite(exp) || exp <= now) continue; // already expired
    if (activeExpiresAt == null || exp > activeExpiresAt) {
      activeProductId = productId;
      activeExpiresAt = exp;
    }
  }

  // --- Upsert into user_entitlements ----------------------------------------
  const isPro = activeProductId != null;
  try {
    await bindings.DB.prepare(
      `INSERT OR IGNORE INTO users (id, display_name, created_at, updated_at)
       VALUES (?1, ?2, ?3, ?3)`
    ).bind(userId, "VoCal User", now).run();

    await bindings.DB.prepare(
      `INSERT INTO user_entitlements (user_id, is_pro, product_id, expires_at, updated_at, source)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6)
       ON CONFLICT(user_id) DO UPDATE SET
         is_pro = excluded.is_pro,
         product_id = excluded.product_id,
         expires_at = excluded.expires_at,
         updated_at = excluded.updated_at,
         source = excluded.source`
    ).bind(
      userId,
      isPro ? 1 : 0,
      activeProductId,
      activeExpiresAt,
      now,
      "apple_receipt"
    ).run();
  } catch (err) {
    console.error("entitlements/refresh: D1 upsert failed", (err as Error).message);
    return json({ error: "Failed to persist entitlement" }, 500);
  }

  return json({
    is_pro: isPro,
    product_id: activeProductId ?? undefined,
    expires_at: activeExpiresAt ?? undefined
  }, 200);
};

async function verifyReceipt(
  url: string,
  receiptData: string,
  sharedSecret: string
): Promise<AppleReceiptResponse> {
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      "receipt-data": receiptData,
      password: sharedSecret,
      // Apple's recommended flag for auto-renewables — returns only the
      // latest in_app entry per product so we don't pay for parsing the
      // whole purchase history.
      "exclude-old-transactions": true
    })
  });
  if (!res.ok) {
    throw new Error(`Apple returned HTTP ${res.status}`);
  }
  return (await res.json()) as AppleReceiptResponse;
}

function json(data: unknown, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...CORS }
  });
}
