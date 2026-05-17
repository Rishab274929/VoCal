import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { onRequestOptions, onRequestPost } from "../../functions/api/auth/apple";
import { mockDB } from "../helpers/mocks";

// ---------------------------------------------------------------------------
// Mock rate-limit + identity-merge modules (same pattern as auth-anonymous)
// ---------------------------------------------------------------------------
vi.mock("../../src/lib/rateLimit", () => ({
  checkRateLimit: vi.fn(async () => ({
    allowed: true,
    retryAfterSec: 0,
    identifier: "test",
  })),
  rateLimitedResponse: vi.fn(
    () =>
      new Response(JSON.stringify({ error: "rate_limited" }), { status: 429 }),
  ),
}));

vi.mock("../../src/lib/identityMerge", () => ({
  mergeAnonymousData: vi.fn(async () => ({ merged: 0, errors: [] })),
}));

// Mock signJWT so tests don't need real crypto for the VoCal token issuance.
vi.mock("../../src/lib/jwt", () => ({
  signJWT: vi.fn(async () => "mocked-vocal-jwt-token"),
}));

import { checkRateLimit, rateLimitedResponse } from "../../src/lib/rateLimit";
import { mergeAnonymousData } from "../../src/lib/identityMerge";

// ---------------------------------------------------------------------------
// Helpers: fake Apple identity tokens
// ---------------------------------------------------------------------------

function base64UrlEncode(str: string): string {
  return btoa(str)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

/**
 * Build a fake Apple identity_token JWT. The signature is always fake, so
 * tests that hit pre-signature validation paths will reject before the JWKS
 * fetch. Tests that need to reach the JWKS path must also mock
 * globalThis.fetch.
 */
function fakeAppleJWT(
  headerOverrides: Record<string, unknown> = {},
  payloadOverrides: Record<string, unknown> = {},
): string {
  const header = {
    alg: "RS256",
    kid: "test-kid-123",
    typ: "JWT",
    ...headerOverrides,
  };
  const payload = {
    iss: "https://appleid.apple.com",
    aud: "com.test.VoCal",
    exp: Math.floor(Date.now() / 1000) + 3600,
    iat: Math.floor(Date.now() / 1000),
    sub: "001234.abcdef1234567890.0123",
    email: "test@privaterelay.appleid.com",
    nonce: "expected-nonce-hash",
    ...payloadOverrides,
  };
  const sig = base64UrlEncode("fake-signature-bytes");
  return `${base64UrlEncode(JSON.stringify(header))}.${base64UrlEncode(JSON.stringify(payload))}.${sig}`;
}

// ---------------------------------------------------------------------------
// Env + context builder
// ---------------------------------------------------------------------------

const JWT_SECRET = "apple-auth-test-secret-long-enough";
const APPLE_BUNDLE_ID = "com.test.VoCal";

function baseEnv(overrides: Record<string, unknown> = {}) {
  return {
    JWT_SECRET,
    APPLE_BUNDLE_ID,
    DB: mockDB(),
    FOOD_KV: undefined,
    ...overrides,
  };
}

function ctx(body: unknown | undefined, envOverrides: Record<string, unknown> = {}) {
  const hasBody = body !== undefined;
  const request = new Request("https://vocal.test/api/auth/apple", {
    method: "POST",
    headers: hasBody ? { "Content-Type": "application/json" } : {},
    body: hasBody ? JSON.stringify(body) : undefined,
  });
  return {
    request,
    env: baseEnv(envOverrides),
    params: {},
  } as any;
}

/** Build a context with a raw (non-JSON-stringified) body string. */
function ctxRawBody(rawBody: string, envOverrides: Record<string, unknown> = {}) {
  const request = new Request("https://vocal.test/api/auth/apple", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: rawBody,
  });
  return {
    request,
    env: baseEnv(envOverrides),
    params: {},
  } as any;
}

async function call(body?: unknown, envOverrides?: Record<string, unknown>) {
  const res = await onRequestPost(ctx(body, envOverrides));
  const json = await res.json();
  return { res, json };
}

// ---------------------------------------------------------------------------
// Stash + restore the real globalThis.fetch so tests that mock it don't leak.
// ---------------------------------------------------------------------------
let originalFetch: typeof globalThis.fetch;

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
describe("auth/apple", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    originalFetch = globalThis.fetch;
    (checkRateLimit as ReturnType<typeof vi.fn>).mockResolvedValue({
      allowed: true,
      retryAfterSec: 0,
      identifier: "test",
    });
  });

  afterEach(() => {
    globalThis.fetch = originalFetch;
  });

  // ---- 1. OPTIONS preflight → 204 with CORS ----
  it("OPTIONS returns 204 with CORS headers", async () => {
    const res = await onRequestOptions();
    expect(res.status).toBe(204);
    expect(res.headers.get("Access-Control-Allow-Origin")).toBe("*");
    expect(res.headers.get("Access-Control-Allow-Methods")).toContain("POST");
    expect(res.headers.get("Access-Control-Allow-Headers")).toContain("Content-Type");
  });

  // ---- 2. Missing identity_token → 400 ----
  it("returns 400 when identity_token is missing", async () => {
    const { res, json } = await call({ nonce: "abc" });
    expect(res.status).toBe(400);
    expect(json.error).toBe("identity_token required");
  });

  it("returns 400 when identity_token is an empty string", async () => {
    const { res, json } = await call({ identity_token: "   ", nonce: "abc" });
    expect(res.status).toBe(400);
    expect(json.error).toBe("identity_token required");
  });

  // ---- 3. Invalid JSON body → 400 ----
  it("returns 400 when body is not valid JSON", async () => {
    const res = await onRequestPost(ctxRawBody("NOT VALID JSON"));
    expect(res.status).toBe(400);
    const json = await res.json();
    expect(json.error).toBe("Invalid JSON");
  });

  // ---- 4. identity_token not a JWT (no dots) → 400 ----
  it("returns 400 when identity_token has no dots (not a JWT)", async () => {
    const { res, json } = await call({
      identity_token: "not-a-jwt-at-all",
      nonce: "abc",
    });
    expect(res.status).toBe(400);
    expect(json.error).toBe("identity_token is not a JWT");
  });

  it("returns 400 when identity_token has only two parts", async () => {
    const { res, json } = await call({
      identity_token: "part1.part2",
      nonce: "abc",
    });
    expect(res.status).toBe(400);
    expect(json.error).toBe("identity_token is not a JWT");
  });

  // ---- 5. alg !== RS256 → 401 ----
  it("returns 401 when alg is 'none'", async () => {
    const token = fakeAppleJWT({ alg: "none" });
    const { res, json } = await call({ identity_token: token, nonce: "abc" });
    expect(res.status).toBe(401);
    expect(json.error).toBe("Unsupported identity_token alg");
  });

  it("returns 401 when alg is HS256", async () => {
    const token = fakeAppleJWT({ alg: "HS256" });
    const { res, json } = await call({ identity_token: token, nonce: "abc" });
    expect(res.status).toBe(401);
    expect(json.error).toBe("Unsupported identity_token alg");
  });

  // ---- 6. Missing kid → 401 ----
  it("returns 401 when kid is missing from JWT header", async () => {
    const token = fakeAppleJWT({ kid: undefined });
    // The kid key will be present but undefined; remove it from the
    // serialised header. Easiest: build it manually.
    const header = base64UrlEncode(JSON.stringify({ alg: "RS256", typ: "JWT" }));
    const payload = base64UrlEncode(
      JSON.stringify({
        iss: "https://appleid.apple.com",
        aud: APPLE_BUNDLE_ID,
        exp: Math.floor(Date.now() / 1000) + 3600,
        sub: "001234.abcdef1234567890.0123",
        nonce: "hash",
      }),
    );
    const sig = base64UrlEncode("fake");
    const noKidToken = `${header}.${payload}.${sig}`;

    const { res, json } = await call({
      identity_token: noKidToken,
      nonce: "abc",
    });
    expect(res.status).toBe(401);
    expect(json.error).toBe("identity_token missing kid");
  });

  // ---- 7. Untrusted issuer → 401 ----
  it("returns 401 when issuer is not appleid.apple.com", async () => {
    const token = fakeAppleJWT({}, { iss: "https://evil.example.com" });
    const { res, json } = await call({ identity_token: token, nonce: "abc" });
    expect(res.status).toBe(401);
    expect(json.error).toBe("Untrusted issuer");
  });

  // ---- 8. Wrong audience → 401 ----
  it("returns 401 when audience does not match APPLE_BUNDLE_ID", async () => {
    const token = fakeAppleJWT({}, { aud: "com.other.app" });
    const { res, json } = await call({ identity_token: token, nonce: "abc" });
    expect(res.status).toBe(401);
    expect(json.error).toBe("Untrusted audience");
  });

  // ---- 9. Expired token → 401 ----
  it("returns 401 when token is expired beyond 60s tolerance", async () => {
    const longAgo = Math.floor(Date.now() / 1000) - 120; // 2 minutes ago
    const token = fakeAppleJWT({}, { exp: longAgo });
    const { res, json } = await call({ identity_token: token, nonce: "abc" });
    expect(res.status).toBe(401);
    expect(json.error).toBe("identity_token expired");
  });

  it("accepts a token expired less than 60s ago (clock skew tolerance)", async () => {
    // Token expired 30 seconds ago — should still pass expiry check but
    // will fail later at JWKS fetch (which we don't mock here on purpose
    // to verify it gets past the expiry gate).
    const recentlyExpired = Math.floor(Date.now() / 1000) - 30;
    const token = fakeAppleJWT({}, { exp: recentlyExpired });

    // Mock fetch so the JWKS path is reached. The kid won't match, so
    // we'll get 401 for kid mismatch — proving the expiry check passed.
    globalThis.fetch = vi.fn(async () =>
      new Response(JSON.stringify({ keys: [] }), { status: 200 }),
    );

    const { res, json } = await call({ identity_token: token, nonce: "abc" });
    // Should NOT be "identity_token expired" — it should be something else
    expect(json.error).not.toBe("identity_token expired");
  });

  // ---- 10. Missing sub → 401 ----
  it("returns 401 when sub is missing from token payload", async () => {
    const token = fakeAppleJWT({}, { sub: undefined });
    // Build manually to omit sub entirely
    const header = base64UrlEncode(
      JSON.stringify({ alg: "RS256", kid: "test-kid-123", typ: "JWT" }),
    );
    const payload = base64UrlEncode(
      JSON.stringify({
        iss: "https://appleid.apple.com",
        aud: APPLE_BUNDLE_ID,
        exp: Math.floor(Date.now() / 1000) + 3600,
        iat: Math.floor(Date.now() / 1000),
        email: "test@privaterelay.appleid.com",
        nonce: "expected-nonce-hash",
      }),
    );
    const sig = base64UrlEncode("fake");
    const noSubToken = `${header}.${payload}.${sig}`;

    const { res, json } = await call({
      identity_token: noSubToken,
      nonce: "abc",
    });
    expect(res.status).toBe(401);
    expect(json.error).toBe("identity_token missing sub");
  });

  // ---- 11. body.user_id doesn't match token sub → 401 ----
  it("returns 401 when body user_id does not match token sub", async () => {
    const token = fakeAppleJWT({}, { sub: "001234.real-sub.0123" });
    const { res, json } = await call({
      identity_token: token,
      nonce: "abc",
      user_id: "001234.different-sub.0123",
    });
    expect(res.status).toBe(401);
    expect(json.error).toBe("user_id does not match identity_token sub");
  });

  it("passes when body user_id matches token sub", async () => {
    const sub = "001234.abcdef1234567890.0123";
    const token = fakeAppleJWT({}, { sub });

    // Mock JWKS fetch — kid won't match, proving it got past the user_id check
    globalThis.fetch = vi.fn(async () =>
      new Response(JSON.stringify({ keys: [] }), { status: 200 }),
    );

    const { res, json } = await call({
      identity_token: token,
      nonce: "abc",
      user_id: sub,
    });
    // Should not be the user_id mismatch error
    expect(json.error).not.toBe("user_id does not match identity_token sub");
  });

  // ---- 12. Missing nonce → 400 ----
  // Note: nonce check happens AFTER signature verification, so we need to
  // mock a successful JWKS + signature path. However, since the nonce check
  // is post-signature, we can test it by verifying the error message when
  // the flow reaches that point. For simpler testing, we test the body-level
  // nonce absence which is checked post-signature in the handler.

  // ---- 13. APPLE_BUNDLE_ID not configured → 503 ----
  it("returns 503 when APPLE_BUNDLE_ID is not set", async () => {
    const { res, json } = await call(
      { identity_token: fakeAppleJWT(), nonce: "abc" },
      { APPLE_BUNDLE_ID: undefined },
    );
    expect(res.status).toBe(503);
    expect(json.error).toBe("Server not configured for Sign in with Apple");
  });

  it("returns 503 when APPLE_BUNDLE_ID is too short", async () => {
    const { res, json } = await call(
      { identity_token: fakeAppleJWT(), nonce: "abc" },
      { APPLE_BUNDLE_ID: "ab" },
    );
    expect(res.status).toBe(503);
    expect(json.error).toBe("Server not configured for Sign in with Apple");
  });

  // ---- 14. JWT_SECRET missing + DB bound → 503 ----
  it("returns 503 when JWT_SECRET is missing and DB is bound", async () => {
    const { res, json } = await call(
      { identity_token: fakeAppleJWT(), nonce: "abc" },
      { JWT_SECRET: undefined, DB: mockDB() },
    );
    expect(res.status).toBe(503);
    expect(json.error).toBe("Server auth misconfigured");
  });

  it("returns 503 when JWT_SECRET is too short and DB is bound", async () => {
    const { res, json } = await call(
      { identity_token: fakeAppleJWT(), nonce: "abc" },
      { JWT_SECRET: "short", DB: mockDB() },
    );
    expect(res.status).toBe(503);
    expect(json.error).toBe("Server auth misconfigured");
  });

  // ---- 15. Rate limited → 429 ----
  it("returns 429 when rate limited", async () => {
    (checkRateLimit as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      allowed: false,
      retryAfterSec: 30,
      identifier: "ip:1.2.3.4",
    });

    const c = ctx({ identity_token: fakeAppleJWT(), nonce: "abc" });
    const res = await onRequestPost(c);
    expect(res.status).toBe(429);
    expect(rateLimitedResponse).toHaveBeenCalled();
  });

  // ---- 16. APPLE_AUDIENCES config: extra audiences accepted ----
  it("accepts a token whose audience matches an APPLE_AUDIENCES entry", async () => {
    const token = fakeAppleJWT({}, { aud: "com.test.VoCal.web" });

    // Mock JWKS fetch so it reaches past audience check
    globalThis.fetch = vi.fn(async () =>
      new Response(JSON.stringify({ keys: [] }), { status: 200 }),
    );

    const { res, json } = await call(
      { identity_token: token, nonce: "abc" },
      { APPLE_AUDIENCES: "com.test.VoCal.web, com.test.VoCal.service" },
    );
    // Should NOT be "Untrusted audience" — it should fail later at kid match
    expect(json.error).not.toBe("Untrusted audience");
  });

  it("rejects a token whose audience is not in APPLE_BUNDLE_ID or APPLE_AUDIENCES", async () => {
    const token = fakeAppleJWT({}, { aud: "com.attacker.app" });
    const { res, json } = await call(
      { identity_token: token, nonce: "abc" },
      { APPLE_AUDIENCES: "com.test.VoCal.web" },
    );
    expect(res.status).toBe(401);
    expect(json.error).toBe("Untrusted audience");
  });

  // ---- 17. JWKS fetch fails → 502 ----
  it("returns 502 when JWKS fetch returns a non-OK status", async () => {
    globalThis.fetch = vi.fn(async () =>
      new Response("Internal Server Error", { status: 500 }),
    );

    const { res, json } = await call({
      identity_token: fakeAppleJWT(),
      nonce: "abc",
    });
    expect(res.status).toBe(502);
    expect(json.error).toBe("Failed to fetch Apple keys");
  });

  it("returns 502 when JWKS fetch throws a network error", async () => {
    globalThis.fetch = vi.fn(async () => {
      throw new Error("Network timeout");
    });

    const { res, json } = await call({
      identity_token: fakeAppleJWT(),
      nonce: "abc",
    });
    expect(res.status).toBe(502);
    expect(json.error).toBe("Failed to fetch Apple keys");
  });

  // ---- 18. No matching kid in JWKS → 401 ----
  it("returns 401 when JWKS has no key matching the token kid", async () => {
    globalThis.fetch = vi.fn(async () =>
      new Response(
        JSON.stringify({
          keys: [
            { kty: "RSA", kid: "wrong-kid-abc", n: "abc", e: "AQAB" },
            { kty: "RSA", kid: "wrong-kid-def", n: "def", e: "AQAB" },
          ],
        }),
        { status: 200 },
      ),
    );

    const { res, json } = await call({
      identity_token: fakeAppleJWT({ kid: "test-kid-123" }),
      nonce: "abc",
    });
    expect(res.status).toBe(401);
    expect(json.error).toBe("No matching Apple key for kid");
  });

  it("returns 401 when JWKS key matches kid but kty is not RSA", async () => {
    globalThis.fetch = vi.fn(async () =>
      new Response(
        JSON.stringify({
          keys: [
            { kty: "EC", kid: "test-kid-123", n: "abc", e: "AQAB" },
          ],
        }),
        { status: 200 },
      ),
    );

    const { res, json } = await call({
      identity_token: fakeAppleJWT({ kid: "test-kid-123" }),
      nonce: "abc",
    });
    expect(res.status).toBe(401);
    expect(json.error).toBe("No matching Apple key for kid");
  });

  it("returns 401 when JWKS keys array is empty", async () => {
    globalThis.fetch = vi.fn(async () =>
      new Response(JSON.stringify({ keys: [] }), { status: 200 }),
    );

    const { res, json } = await call({
      identity_token: fakeAppleJWT(),
      nonce: "abc",
    });
    expect(res.status).toBe(401);
    expect(json.error).toBe("No matching Apple key for kid");
  });

  // ---- 19. normalizeAppleDisplayName: various full_name shapes ----
  // These tests require passing through JWKS + signature verification. We
  // mock fetch to return matching key, and mock crypto.subtle.verify to
  // return true, and mock the nonce hash match.

  describe("normalizeAppleDisplayName via full response", () => {
    /** Set up mocks for a fully successful auth flow. */
    function setupSuccessfulFlow(rawNonce: string, nonceHash: string) {
      // Mock JWKS: return a key matching our kid. The actual RSA verification
      // will be attempted with crypto.subtle — we override verifyRS256 by
      // providing a real-looking key. Since the signature is fake, the verify
      // call will return false. Instead, we mock crypto.subtle.verify.
      const originalSubtleVerify = crypto.subtle.verify.bind(crypto.subtle);
      const originalSubtleDigest = crypto.subtle.digest.bind(crypto.subtle);
      const originalSubtleImportKey = crypto.subtle.importKey.bind(crypto.subtle);

      // We need to mock at the fetch + crypto level:
      globalThis.fetch = vi.fn(async (url: string | URL | Request) => {
        const urlStr = typeof url === "string" ? url : url instanceof URL ? url.toString() : url.url;
        if (urlStr.includes("appleid.apple.com/auth/keys")) {
          return new Response(
            JSON.stringify({
              keys: [
                {
                  kty: "RSA",
                  kid: "test-kid-123",
                  // Minimal RSA key fields — importKey will be mocked
                  n: "0vx7agoebGcQSuuPiLJXZptN9nndrQmbXEps2aiAFbWhM78LhWx4cbbfAAtVT86zwu1RK7aPFFxuhDR1L6tSoc_BJECPebWKRXjBZCiFV4n3oknjhMstn64tZ_2W-5JsGY4Hc5n9yBXArwl93lqt7_RN5w6Cf0h4QyQ5v-65YGjQR0_FDW2QvzqY368QQMicAtaSqzs8KJZgnYb9c7d0zgdAZHzu6qMQvRL5hajrn1n91CbOpbISD08qNLyrdkt-bFTWhAI4vMQFh6WeZu0fM4lFd2NcRwr3XPksINHaQ-G_xBniIqbw0Ls1jF44-csFCur-kEgU8awapJzKnqDKgw",
                  e: "AQAB",
                },
              ],
            }),
            { status: 200 },
          );
        }
        return new Response("", { status: 404 });
      });

      // Mock crypto.subtle.importKey + verify to simulate RS256 success
      const mockVerify = vi.fn(async () => true);
      const mockImportKey = vi.fn(async () => ({ type: "public" }) as CryptoKey);

      // We can't easily mock crypto.subtle methods individually, so we mock
      // the entire verify flow by spying on crypto.subtle
      vi.spyOn(crypto.subtle, "importKey").mockImplementation(mockImportKey as any);
      vi.spyOn(crypto.subtle, "verify").mockImplementation(mockVerify as any);

      // For SHA-256 nonce hashing we need the real digest, but we want to
      // control the result. Mock digest to return the expected hash when
      // called for the nonce.
      vi.spyOn(crypto.subtle, "digest").mockImplementation(
        async (algorithm: any, data: BufferSource) => {
          // Use real implementation for the nonce hash
          return originalSubtleDigest(algorithm, data);
        },
      );

      return () => {
        vi.restoreAllMocks();
      };
    }

    /**
     * Compute SHA-256 hex of a string — mirrors the handler's sha256Hex.
     */
    async function sha256Hex(input: string): Promise<string> {
      const digest = await crypto.subtle.digest(
        "SHA-256",
        new TextEncoder().encode(input),
      );
      return [...new Uint8Array(digest)]
        .map((b) => b.toString(16).padStart(2, "0"))
        .join("");
    }

    it("extracts full_name as { given, family } into response name", async () => {
      // We need the nonce hash in the token to match sha256(rawNonce).
      // Compute it before mocking crypto.subtle.
      const rawNonce = "test-nonce-12345";
      const nonceHash = await sha256Hex(rawNonce);

      const cleanup = setupSuccessfulFlow(rawNonce, nonceHash);

      const token = fakeAppleJWT({}, { nonce: nonceHash });
      const { res, json } = await call({
        identity_token: token,
        nonce: rawNonce,
        full_name: { given: "John", family: "Doe" },
      });

      expect(res.status).toBe(200);
      expect(json.name).toBe("John Doe");
      expect(json.user_id).toMatch(/^apple_/);
      expect(json.token).toBeTruthy();

      cleanup();
    });

    it("extracts full_name as a plain string", async () => {
      const rawNonce = "test-nonce-string-name";
      const nonceHash = await sha256Hex(rawNonce);

      const cleanup = setupSuccessfulFlow(rawNonce, nonceHash);

      const token = fakeAppleJWT({}, { nonce: nonceHash });
      const { res, json } = await call({
        identity_token: token,
        nonce: rawNonce,
        full_name: "Jane Smith",
      });

      expect(res.status).toBe(200);
      expect(json.name).toBe("Jane Smith");

      cleanup();
    });

    it("omits name from response when full_name is null", async () => {
      const rawNonce = "test-nonce-null-name";
      const nonceHash = await sha256Hex(rawNonce);

      const cleanup = setupSuccessfulFlow(rawNonce, nonceHash);

      const token = fakeAppleJWT({}, { nonce: nonceHash });
      const { res, json } = await call({
        identity_token: token,
        nonce: rawNonce,
        full_name: null,
      });

      expect(res.status).toBe(200);
      // "Friend" is the fallback, but it's omitted from response
      expect(json.name).toBeUndefined();

      cleanup();
    });

    it("omits name when full_name has empty given and family", async () => {
      const rawNonce = "test-nonce-empty-parts";
      const nonceHash = await sha256Hex(rawNonce);

      const cleanup = setupSuccessfulFlow(rawNonce, nonceHash);

      const token = fakeAppleJWT({}, { nonce: nonceHash });
      const { res, json } = await call({
        identity_token: token,
        nonce: rawNonce,
        full_name: { given: "", family: "" },
      });

      expect(res.status).toBe(200);
      expect(json.name).toBeUndefined();

      cleanup();
    });

    it("handles full_name with only given name", async () => {
      const rawNonce = "test-nonce-given-only";
      const nonceHash = await sha256Hex(rawNonce);

      const cleanup = setupSuccessfulFlow(rawNonce, nonceHash);

      const token = fakeAppleJWT({}, { nonce: nonceHash });
      const { res, json } = await call({
        identity_token: token,
        nonce: rawNonce,
        full_name: { given: "Alice" },
      });

      expect(res.status).toBe(200);
      expect(json.name).toBe("Alice");

      cleanup();
    });
  });

  // ---- Successful flow: user_id shape + is_new_user ----
  describe("successful auth flow", () => {
    async function sha256Hex(input: string): Promise<string> {
      const digest = await crypto.subtle.digest(
        "SHA-256",
        new TextEncoder().encode(input),
      );
      return [...new Uint8Array(digest)]
        .map((b) => b.toString(16).padStart(2, "0"))
        .join("");
    }

    function setupFullMocks() {
      globalThis.fetch = vi.fn(async (url: string | URL | Request) => {
        const urlStr = typeof url === "string" ? url : url instanceof URL ? url.toString() : url.url;
        if (urlStr.includes("appleid.apple.com/auth/keys")) {
          return new Response(
            JSON.stringify({
              keys: [{
                kty: "RSA",
                kid: "test-kid-123",
                n: "0vx7agoebGcQSuuPiLJXZptN9nndrQmbXEps2aiAFbWhM78LhWx4cbbfAAtVT86zwu1RK7aPFFxuhDR1L6tSoc_BJECPebWKRXjBZCiFV4n3oknjhMstn64tZ_2W-5JsGY4Hc5n9yBXArwl93lqt7_RN5w6Cf0h4QyQ5v-65YGjQR0_FDW2QvzqY368QQMicAtaSqzs8KJZgnYb9c7d0zgdAZHzu6qMQvRL5hajrn1n91CbOpbISD08qNLyrdkt-bFTWhAI4vMQFh6WeZu0fM4lFd2NcRwr3XPksINHaQ-G_xBniIqbw0Ls1jF44-csFCur-kEgU8awapJzKnqDKgw",
                e: "AQAB",
              }],
            }),
            { status: 200 },
          );
        }
        return new Response("", { status: 404 });
      });

      vi.spyOn(crypto.subtle, "importKey").mockImplementation(
        async () => ({ type: "public" }) as CryptoKey,
      );
      vi.spyOn(crypto.subtle, "verify").mockImplementation(
        async () => true,
      );
    }

    it("returns user_id prefixed with apple_ and sanitized sub", async () => {
      const rawNonce = "nonce-userid-test";
      const nonceHash = await sha256Hex(rawNonce);

      setupFullMocks();

      const sub = "001234.abcdef1234567890.0123";
      const token = fakeAppleJWT({}, { sub, nonce: nonceHash });

      const { res, json } = await call({
        identity_token: token,
        nonce: rawNonce,
      });

      expect(res.status).toBe(200);
      // Sub gets sanitized: dots become empty (stripped by replace regex)
      expect(json.user_id).toMatch(/^apple_[A-Za-z0-9_.-]+$/);
      expect(json.user_id).toContain("001234");
      expect(json.is_new_user).toBe(true);
      expect(json.expires_at).toBeGreaterThan(Date.now());
      // Expires in ~7 days
      const diffMs = json.expires_at - Date.now();
      expect(diffMs).toBeGreaterThan(6 * 24 * 60 * 60 * 1000);
      expect(diffMs).toBeLessThanOrEqual(7 * 24 * 60 * 60 * 1000 + 5000);

      vi.restoreAllMocks();
    });

    it("returns is_new_user false when DB has existing user", async () => {
      const rawNonce = "nonce-existing-user";
      const nonceHash = await sha256Hex(rawNonce);

      setupFullMocks();

      const sub = "001234.existing.0123";
      const token = fakeAppleJWT({}, { sub, nonce: nonceHash });

      // Build a DB where every prepare() returns a statement whose first()
      // resolves to an existing user row (the SELECT check) and whose run()
      // succeeds (the upsert).
      const existingUserDB = {
        prepare: vi.fn(() => {
          const stmt: any = {
            bind: vi.fn((..._: unknown[]) => stmt),
            run: vi.fn(async () => ({ meta: { changes: 1 } })),
            first: vi.fn(async () => ({ id: `apple_001234.existing.0123` })),
            all: vi.fn(async () => ({ results: [] })),
          };
          return stmt;
        }),
        batch: vi.fn(async () => []),
      };

      const { res, json } = await call(
        { identity_token: token, nonce: rawNonce },
        { DB: existingUserDB },
      );

      expect(res.status).toBe(200);
      expect(json.is_new_user).toBe(false);

      vi.restoreAllMocks();
    });

    it("includes email from token in response", async () => {
      const rawNonce = "nonce-email-test";
      const nonceHash = await sha256Hex(rawNonce);

      setupFullMocks();

      const email = "user@privaterelay.appleid.com";
      const token = fakeAppleJWT({}, { email, nonce: nonceHash });

      const { res, json } = await call({
        identity_token: token,
        nonce: rawNonce,
      });

      expect(res.status).toBe(200);
      expect(json.email).toBe(email);

      vi.restoreAllMocks();
    });

    it("calls mergeAnonymousData when link_anonymous fields are provided", async () => {
      const rawNonce = "nonce-merge-test";
      const nonceHash = await sha256Hex(rawNonce);

      setupFullMocks();

      const token = fakeAppleJWT({}, { nonce: nonceHash });

      const { res, json } = await call({
        identity_token: token,
        nonce: rawNonce,
        link_anonymous_user_id: "anon_old-device",
        link_anonymous_token: "old-anon-token",
      });

      expect(res.status).toBe(200);
      expect(mergeAnonymousData).toHaveBeenCalledWith(
        expect.objectContaining({ JWT_SECRET }),
        "anon_old-device",
        "old-anon-token",
        expect.stringMatching(/^apple_/),
      );
      expect(json.merged_rows).toBe(0);

      vi.restoreAllMocks();
    });

    it("does not call mergeAnonymousData without link fields", async () => {
      const rawNonce = "nonce-no-merge";
      const nonceHash = await sha256Hex(rawNonce);

      setupFullMocks();

      const token = fakeAppleJWT({}, { nonce: nonceHash });

      const { res, json } = await call({
        identity_token: token,
        nonce: rawNonce,
      });

      expect(res.status).toBe(200);
      expect(mergeAnonymousData).not.toHaveBeenCalled();

      vi.restoreAllMocks();
    });
  });

  // ---- CORS headers present on all responses ----
  it("includes CORS headers on error responses", async () => {
    const { res } = await call({ identity_token: "not-jwt", nonce: "abc" });
    expect(res.headers.get("Access-Control-Allow-Origin")).toBe("*");
  });

  // ---- Malformed base64 in JWT parts → 400 ----
  it("returns 400 when JWT header is malformed base64", async () => {
    const badToken = "!!!not-base64!!!.eyJ0ZXN0IjoxfQ.fakesig";
    const { res, json } = await call({
      identity_token: badToken,
      nonce: "abc",
    });
    expect(res.status).toBe(400);
    expect(json.error).toBe("identity_token JWT is malformed");
  });

  // ---- Dev fallback: no DB + no JWT_SECRET → uses dev secret ----
  it("uses dev fallback secret when no DB and no JWT_SECRET", async () => {
    const token = fakeAppleJWT();
    const { res, json } = await call(
      { identity_token: token, nonce: "abc" },
      { JWT_SECRET: undefined, DB: undefined },
    );
    // Should proceed past config gate (dev fallback) and fail at JWKS fetch
    // since we haven't mocked it
    expect(res.status).not.toBe(503);
  });

  // ---- Array audience in token ----
  it("accepts token with array audience containing APPLE_BUNDLE_ID", async () => {
    const token = fakeAppleJWT(
      {},
      { aud: ["com.other.app", APPLE_BUNDLE_ID] },
    );

    // Mock JWKS so it proceeds past audience check
    globalThis.fetch = vi.fn(async () =>
      new Response(JSON.stringify({ keys: [] }), { status: 200 }),
    );

    const { res, json } = await call({ identity_token: token, nonce: "abc" });
    expect(json.error).not.toBe("Untrusted audience");
  });

  it("rejects token with array audience not containing any allowed value", async () => {
    const token = fakeAppleJWT(
      {},
      { aud: ["com.evil.app1", "com.evil.app2"] },
    );
    const { res, json } = await call({ identity_token: token, nonce: "abc" });
    expect(res.status).toBe(401);
    expect(json.error).toBe("Untrusted audience");
  });

  // ---- DB write failure is non-fatal ----
  describe("DB resilience", () => {
    async function sha256Hex(input: string): Promise<string> {
      const digest = await crypto.subtle.digest(
        "SHA-256",
        new TextEncoder().encode(input),
      );
      return [...new Uint8Array(digest)]
        .map((b) => b.toString(16).padStart(2, "0"))
        .join("");
    }

    it("returns success even when the DB upsert throws", async () => {
      const rawNonce = "nonce-db-failure";
      const nonceHash = await sha256Hex(rawNonce);

      globalThis.fetch = vi.fn(async (url: string | URL | Request) => {
        const urlStr = typeof url === "string" ? url : url instanceof URL ? url.toString() : url.url;
        if (urlStr.includes("appleid.apple.com/auth/keys")) {
          return new Response(
            JSON.stringify({
              keys: [{
                kty: "RSA",
                kid: "test-kid-123",
                n: "0vx7agoebGcQSuuPiLJXZptN9nndrQmbXEps2aiAFbWhM78LhWx4cbbfAAtVT86zwu1RK7aPFFxuhDR1L6tSoc_BJECPebWKRXjBZCiFV4n3oknjhMstn64tZ_2W-5JsGY4Hc5n9yBXArwl93lqt7_RN5w6Cf0h4QyQ5v-65YGjQR0_FDW2QvzqY368QQMicAtaSqzs8KJZgnYb9c7d0zgdAZHzu6qMQvRL5hajrn1n91CbOpbISD08qNLyrdkt-bFTWhAI4vMQFh6WeZu0fM4lFd2NcRwr3XPksINHaQ-G_xBniIqbw0Ls1jF44-csFCur-kEgU8awapJzKnqDKgw",
                e: "AQAB",
              }],
            }),
            { status: 200 },
          );
        }
        return new Response("", { status: 404 });
      });

      vi.spyOn(crypto.subtle, "importKey").mockImplementation(
        async () => ({ type: "public" }) as CryptoKey,
      );
      vi.spyOn(crypto.subtle, "verify").mockImplementation(
        async () => true,
      );

      // DB where first() works (for isNewUser check) but run() throws
      const failingDB = {
        prepare: vi.fn(() => {
          const stmt: any = {
            bind: vi.fn((..._: unknown[]) => stmt),
            run: vi.fn(async () => { throw new Error("D1 upsert failure"); }),
            first: vi.fn(async () => null),
            all: vi.fn(async () => ({ results: [] })),
          };
          return stmt;
        }),
        batch: vi.fn(async () => []),
      };

      const token = fakeAppleJWT({}, { nonce: nonceHash });
      const { res, json } = await call(
        { identity_token: token, nonce: rawNonce },
        { DB: failingDB },
      );

      // D1 failure is non-fatal — handler catches it and issues token anyway
      expect(res.status).toBe(200);
      expect(json.user_id).toMatch(/^apple_/);
      expect(json.token).toBeTruthy();

      vi.restoreAllMocks();
    });
  });
});
