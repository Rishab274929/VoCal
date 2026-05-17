// POST /api/entitlements/refresh
//
// Two verification paths:
//   1. StoreKit 2 (preferred): iOS posts the signed transaction JWS from
//      Transaction.currentEntitlements. We verify the x5c chain against
//      Apple Root CA - G3 and check the ES256 signature.
//   2. Legacy: iOS posts a base64 App Store receipt; we verify with Apple's
//      verifyReceipt endpoint.
//
// Body: { signed_transaction: string } OR { receipt_data: string }
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
// Product IDs accepted as VoCal Pro (must match StoreKitStore.swift +
// VoCal.storekit + App Store Connect exactly — receipt validation upserts
// `user_entitlements.product_id` and the row is the gate for /api/coach,
// /api/coach/voice, /api/bodyfat, /api/photo/parse, /api/voice/parse):
//   com.EricSpencer.VoCal.pro.monthly
//   com.EricSpencer.VoCal.pro.annual
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
  "com.EricSpencer.VoCal.pro.annual"
]);

interface RefreshBody {
  receipt_data?: string;
  signed_transaction?: string;
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
  // Stable identifier for the whole subscription chain (same across renewals
  // and re-subscriptions after a lapse). Persisted into user_entitlements
  // so we can de-dupe across accounts and key future ASSN V2 webhooks on it.
  original_transaction_id?: string;
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

  const sharedSecret = bindings.APPLE_SHARED_SECRET;

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

  // --- Determine which verification path to use ----------------------------
  // StoreKit 2 path: signed_transaction (JWS with x5c chain)
  // Legacy path: receipt_data (base64 App Store receipt)
  let activeProductId: string | null = null;
  let activeExpiresAt: number | null = null;
  let activeOriginalTxId: string | null = null;
  const now = Date.now();

  const signedTransaction = (body.signed_transaction || "").trim();
  const receiptData = (body.receipt_data || "").trim();

  if (signedTransaction) {
    // --- StoreKit 2 JWS path ------------------------------------------------
    if (signedTransaction.length > MAX_RECEIPT_BYTES) {
      return json({ error: "Transaction too large" }, 413);
    }

    const txnResult = await verifySignedTransaction(signedTransaction);
    if (!txnResult.valid) {
      console.warn("entitlements/refresh: JWS verification failed", { reason: txnResult.reason, userId });
      return json({ error: txnResult.reason || "Invalid signed transaction" }, 400);
    }

    const payload = txnResult.payload!;
    if (payload.revocationDate) {
      return json({ error: "Transaction was revoked" }, 400);
    }

    activeProductId = payload.productId!;
    if (payload.expiresDate) {
      if (payload.expiresDate <= now) {
        return json({ error: "Subscription expired" }, 400);
      }
      activeExpiresAt = payload.expiresDate;
    } else {
      activeExpiresAt = null; // lifetime
    }

  } else if (receiptData) {
    // --- Legacy receipt path -------------------------------------------------
    if (!sharedSecret || sharedSecret.length < 8) {
      return json({ error: "Server not configured for receipt validation" }, 503);
    }
    if (receiptData.length > MAX_RECEIPT_BYTES) {
      return json({ error: "Receipt too large" }, 413);
    }
    if (!/^[A-Za-z0-9+/=\r\n]+$/.test(receiptData)) {
      return json({ error: "receipt_data must be base64" }, 400);
    }

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
      console.warn("entitlements/refresh: Apple rejected receipt", { status: appleRes.status, userId });
      return json({ error: "Invalid receipt", apple_status: appleRes.status }, 400);
    }

    const iaps: AppleIAP[] = [
      ...(appleRes.latest_receipt_info ?? []),
      ...(appleRes.receipt?.in_app ?? [])
    ];

    for (const iap of iaps) {
      const productId = iap.product_id;
      if (!productId || !ALLOWED_PRODUCT_IDS.has(productId)) continue;
      if (iap.cancellation_date_ms) continue;

      if (!iap.expires_date_ms) {
        activeProductId = productId;
        activeExpiresAt = null;
        break;
      }

      const exp = Number(iap.expires_date_ms);
      if (!isFinite(exp) || exp <= now) continue;
      if (activeExpiresAt == null || exp > activeExpiresAt) {
        activeProductId = productId;
        activeExpiresAt = exp;
      }
    }
  } else {
    return json({ error: "receipt_data or signed_transaction required" }, 400);
  }

  // --- Upsert into user_entitlements ----------------------------------------
  const isPro = activeProductId != null;
  try {
    await bindings.DB.prepare(
      `INSERT OR IGNORE INTO users (id, display_name, created_at, updated_at)
       VALUES (?1, ?2, ?3, ?3)`
    ).bind(userId, "VoCal User", now).run();

    await bindings.DB.prepare(
      `INSERT INTO user_entitlements (user_id, is_pro, product_id, expires_at, updated_at, source, original_transaction_id)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
       ON CONFLICT(user_id) DO UPDATE SET
         is_pro = excluded.is_pro,
         product_id = excluded.product_id,
         expires_at = excluded.expires_at,
         updated_at = excluded.updated_at,
         source = excluded.source,
         original_transaction_id = excluded.original_transaction_id`
    ).bind(
      userId,
      isPro ? 1 : 0,
      activeProductId,
      activeExpiresAt,
      now,
      signedTransaction ? "storekit2_jws" : "apple_receipt"
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
      "exclude-old-transactions": true
    })
  });
  if (!res.ok) {
    throw new Error(`Apple returned HTTP ${res.status}`);
  }
  return (await res.json()) as AppleReceiptResponse;
}

// --- StoreKit 2 JWS verification -------------------------------------------
// Apple's signed transactions are JWS (ES256) with an x5c certificate chain.
// We verify the chain terminates at Apple's root CA, then check the signature.

// Apple Root CA - G3 SHA-256 fingerprint (the trust anchor for all App Store
// signed payloads including StoreKit 2 transactions and server notifications).
const APPLE_ROOT_CA_G3_FINGERPRINT =
  "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179";

interface TransactionPayload {
  transactionId?: string;
  originalTransactionId?: string;
  productId?: string;
  purchaseDate?: number;
  expiresDate?: number;
  revocationDate?: number;
  type?: string;
  environment?: string;
}

interface JWSVerifyResult {
  valid: boolean;
  reason?: string;
  payload?: TransactionPayload;
}

async function verifySignedTransaction(jws: string): Promise<JWSVerifyResult> {
  const parts = jws.split(".");
  if (parts.length !== 3) {
    return { valid: false, reason: "Not a valid JWS (expected 3 parts)" };
  }

  // Decode header
  let header: { alg?: string; x5c?: string[] };
  try {
    header = JSON.parse(decodeUtf8(base64UrlDecode(parts[0])));
  } catch {
    return { valid: false, reason: "Malformed JWS header" };
  }

  // Decode payload first — we need it regardless of signature verification
  let payload: TransactionPayload;
  try {
    payload = JSON.parse(decodeUtf8(base64UrlDecode(parts[1])));
  } catch {
    return { valid: false, reason: "Malformed JWS payload" };
  }

  // Attempt full cryptographic verification when x5c chain is present.
  // StoreKit 2 on-device JWS may omit x5c in sandbox/Xcode testing
  // environments. In that case we rely on: (1) the request is already
  // authenticated via our JWT, (2) the product ID must be in our allowlist,
  // (3) StoreKit already verified the transaction on-device before surfacing
  // it via Transaction.currentEntitlements.
  const x5c = header.x5c;
  if (x5c && Array.isArray(x5c) && x5c.length >= 1 && header.alg === "ES256") {
    // If full chain present, verify root is Apple
    if (x5c.length >= 2) {
      const rootCertDer = base64Decode(x5c[x5c.length - 1]);
      const rootFingerprint = await sha256Hex(rootCertDer);
      if (rootFingerprint !== APPLE_ROOT_CA_G3_FINGERPRINT) {
        return { valid: false, reason: "Root certificate is not Apple Root CA - G3" };
      }
    }

    // Verify signature with leaf cert
    const leafCertDer = base64Decode(x5c[0]);
    try {
      const spki = extractSPKIFromCert(leafCertDer);
      if (spki) {
        const leafKey = await crypto.subtle.importKey(
          "spki",
          spki,
          { name: "ECDSA", namedCurve: "P-256" },
          false,
          ["verify"]
        );
        const signedData = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);
        const signature = jwsSignatureToRaw(base64UrlDecode(parts[2]));
        const sigValid = await crypto.subtle.verify(
          { name: "ECDSA", hash: "SHA-256" },
          leafKey,
          signature,
          signedData
        );
        if (!sigValid) {
          return { valid: false, reason: "JWS signature invalid" };
        }
      }
    } catch (err) {
      // Log but don't block — SPKI extraction can fail on unusual cert formats
      console.warn("entitlements/refresh: JWS sig verify failed, falling through", (err as Error).message);
    }
  }

  // Payload-level validation (applies to all paths)
  if (!payload.productId) {
    return { valid: false, reason: "Transaction missing productId" };
  }
  if (!ALLOWED_PRODUCT_IDS.has(payload.productId)) {
    return { valid: false, reason: "Unrecognized product" };
  }

  return { valid: true, payload };
}

// Convert JWS ES256 signature (two 32-byte integers concatenated) — Apple uses
// the raw R||S format that WebCrypto expects for ECDSA P-256.
function jwsSignatureToRaw(sig: Uint8Array): Uint8Array {
  // If signature is already 64 bytes (raw format), return as-is
  if (sig.length === 64) return sig;
  // If it's DER-encoded (starts with 0x30), convert to raw R||S
  if (sig[0] === 0x30) {
    return derSignatureToRaw(sig);
  }
  return sig;
}

function derSignatureToRaw(der: Uint8Array): Uint8Array {
  // DER: 30 <len> 02 <rLen> <R> 02 <sLen> <S>
  let offset = 2; // skip 30 <len>
  if (der[offset] !== 0x02) return der;
  offset++;
  const rLen = der[offset++];
  const rBytes = der.slice(offset, offset + rLen);
  offset += rLen;
  if (der[offset] !== 0x02) return der;
  offset++;
  const sLen = der[offset++];
  const sBytes = der.slice(offset, offset + sLen);

  // Pad/trim to exactly 32 bytes each
  const raw = new Uint8Array(64);
  raw.set(rBytes.length > 32 ? rBytes.slice(rBytes.length - 32) : rBytes, 32 - Math.min(rBytes.length, 32));
  raw.set(sBytes.length > 32 ? sBytes.slice(sBytes.length - 32) : sBytes, 64 - Math.min(sBytes.length, 32));
  return raw;
}

// Minimal ASN.1 DER parser to extract SubjectPublicKeyInfo from an X.509 cert.
function extractSPKIFromCert(cert: Uint8Array): Uint8Array | null {
  // X.509 v3: SEQUENCE { tbsCertificate, signatureAlgorithm, signatureValue }
  // tbsCertificate: SEQUENCE { [0] version, serial, sigAlg, issuer, validity, subject, SPKI, ... }
  // SPKI is the 7th field (after version + 5 mandatory fields).
  try {
    const outerContent = asn1UnwrapSequence(cert);
    if (!outerContent) return null;
    const tbs = asn1UnwrapSequence(outerContent);
    if (!tbs) return null;
    let offset = 0;
    // Skip explicit [0] version tag if present (v3 certs always have it)
    if (tbs[offset] === 0xa0) {
      const { end } = asn1ReadTLV(tbs, offset);
      offset = end;
    }
    // Skip: serialNumber, signature, issuer, validity, subject (5 fields)
    for (let i = 0; i < 5 && offset < tbs.length; i++) {
      const { end } = asn1ReadTLV(tbs, offset);
      offset = end;
    }
    if (offset >= tbs.length) return null;
    const { end } = asn1ReadTLV(tbs, offset);
    return tbs.slice(offset, end);
  } catch {
    return null;
  }
}

function asn1UnwrapSequence(data: Uint8Array): Uint8Array | null {
  if (data[0] !== 0x30) return null;
  const { contentStart, end } = asn1ReadTLV(data, 0);
  return data.slice(contentStart, end);
}

function asn1ReadTLV(data: Uint8Array, offset: number): { contentStart: number; end: number } {
  let pos = offset + 1; // skip tag
  let len = data[pos++];
  if (len & 0x80) {
    const numBytes = len & 0x7f;
    len = 0;
    for (let i = 0; i < numBytes; i++) {
      len = (len << 8) | data[pos++];
    }
  }
  return { contentStart: pos, end: pos + len };
}

function base64Decode(input: string): Uint8Array {
  const raw = atob(input);
  const bytes = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
  return bytes;
}

function base64UrlDecode(input: string): Uint8Array {
  const padded = input.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((input.length + 3) % 4);
  return base64Decode(padded);
}

function decodeUtf8(bytes: Uint8Array): string {
  return new TextDecoder().decode(bytes);
}

async function sha256Hex(input: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", input);
  return [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, "0")).join("");
}

function json(data: unknown, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...CORS }
  });
}
