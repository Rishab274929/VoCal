import { describe, it, expect, vi, beforeEach } from "vitest";
import { onRequestOptions, onRequestPost } from "../../functions/api/auth/anonymous";
import { verifyJWT } from "../../src/lib/jwt";

// ---------------------------------------------------------------------------
// Mock the rate-limit module so tests control whether requests are allowed.
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

// Re-import so we can manipulate the mock per-test.
import { checkRateLimit, rateLimitedResponse } from "../../src/lib/rateLimit";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
const JWT_SECRET = "test-secret-for-anon-auth-tests"; // >= 16 chars

function mockDB() {
  return {
    prepare: vi.fn(() => ({
      bind: vi.fn().mockReturnThis(),
      run: vi.fn(async () => ({ meta: { changes: 0 } })),
      first: vi.fn(async () => null),
      all: vi.fn(async () => ({ results: [] })),
    })),
    batch: vi.fn(async () => []),
  };
}

/** Build a minimal PagesFunction context matching what the handler expects. */
function ctx(
  body: unknown | undefined,
  envOverrides: Record<string, unknown> = {},
) {
  const hasBody = body !== undefined;
  const request = new Request("https://vocal.test/api/auth/anonymous", {
    method: "POST",
    headers: hasBody ? { "content-type": "application/json" } : {},
    body: hasBody ? JSON.stringify(body) : undefined,
  });
  return {
    request,
    env: { JWT_SECRET, DB: mockDB(), FOOD_KV: undefined, ...envOverrides },
    params: {},
  } as any;
}

/** Shorthand: call the handler and parse the JSON response. */
async function call(
  body?: unknown,
  envOverrides?: Record<string, unknown>,
) {
  const res = await onRequestPost(ctx(body, envOverrides));
  const json = await res.json();
  return { res, json };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
describe("auth/anonymous", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    // Reset the rate-limit mock to "allow" by default.
    (checkRateLimit as ReturnType<typeof vi.fn>).mockResolvedValue({
      allowed: true,
      retryAfterSec: 0,
      identifier: "test",
    });
  });

  // ---- 1. OPTIONS / CORS preflight ----
  it("OPTIONS returns 204 with CORS headers", async () => {
    const res = await onRequestOptions();
    expect(res.status).toBe(204);
    expect(res.headers.get("access-control-allow-origin")).toBe("*");
    expect(res.headers.get("access-control-allow-methods")).toContain("POST");
    expect(res.headers.get("access-control-allow-headers")).toContain(
      "content-type",
    );
  });

  // ---- 2. POST with device_id ----
  it("POST with device_id returns matching user_id, token, and expires_at", async () => {
    const { json } = await call({ device_id: "my-device-123" });

    expect(json.user_id).toBe("anon_my-device-123");
    expect(json.token).toEqual(expect.any(String));
    // expires_at should be ~1 hour from now (within a generous window).
    const diffMs = json.expires_at - Date.now();
    expect(diffMs).toBeGreaterThan(59 * 60 * 1000 - 5000);
    expect(diffMs).toBeLessThanOrEqual(60 * 60 * 1000 + 1000);
  });

  // ---- 3. POST with empty body → random UUID-based user_id ----
  it("POST with empty body generates a random UUID-based anon user_id", async () => {
    const { json } = await call(undefined);

    expect(json.user_id).toMatch(/^anon_[a-f0-9-]+$/);
    expect(json.token).toEqual(expect.any(String));
    expect(json.expires_at).toEqual(expect.any(Number));
  });

  // ---- 4. POST with invalid JSON → falls back gracefully ----
  it("POST with invalid JSON body still succeeds", async () => {
    const request = new Request("https://vocal.test/api/auth/anonymous", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: "NOT VALID JSON",
    });
    const res = await onRequestPost({
      request,
      env: { JWT_SECRET, DB: mockDB(), FOOD_KV: undefined },
      params: {},
    } as any);

    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.user_id).toMatch(/^anon_/);
    expect(json.token).toBeTruthy();
  });

  // ---- 5. Token is verifiable with verifyJWT ----
  it("returned token is verifiable with verifyJWT using the same secret", async () => {
    const { json } = await call({ device_id: "verify-me" });
    const claims = await verifyJWT(json.token, JWT_SECRET);

    expect(claims).not.toBeNull();
    expect(claims!.sub).toBe(json.user_id);
  });

  // ---- 6. Token claims have sub === user_id and anon === true ----
  it("token claims contain sub === user_id and anon === true", async () => {
    const { json } = await call({ device_id: "claim-check" });
    const claims = await verifyJWT(json.token, JWT_SECRET);

    expect(claims).not.toBeNull();
    expect(claims!.sub).toBe("anon_claim-check");
    expect(claims!.anon).toBe(true);
  });

  // ---- 7. Device ID sanitisation ----
  it("strips special characters and truncates device_id to 32 chars", async () => {
    const dirtyId = "a!b@c#d$e%f^g&h*i(j)k+l=m/n?o.p";
    const { json } = await call({ device_id: dirtyId });

    // Only alphanumeric, underscore, and hyphen survive.
    expect(json.user_id).toMatch(/^anon_[A-Za-z0-9_-]+$/);
    // The part after "anon_" must be <= 32 chars.
    const suffix = json.user_id.slice("anon_".length);
    expect(suffix.length).toBeLessThanOrEqual(32);
  });

  it("truncates a very long device_id to 32 characters", async () => {
    const longId = "a".repeat(100);
    const { json } = await call({ device_id: longId });
    const suffix = json.user_id.slice("anon_".length);
    expect(suffix.length).toBe(32);
  });

  // ---- 8. DB bound + no JWT_SECRET → 503 ----
  it("returns 503 when DB is bound but JWT_SECRET is missing", async () => {
    const { res, json } = await call(
      { device_id: "sec-test" },
      { JWT_SECRET: undefined, DB: mockDB() },
    );

    expect(res.status).toBe(503);
    expect(json.error).toBe("Server auth misconfigured");
  });

  // ---- 9. DB bound + weak JWT_SECRET → 503 ----
  it("returns 503 when DB is bound but JWT_SECRET is too short", async () => {
    const { res, json } = await call(
      { device_id: "sec-test" },
      { JWT_SECRET: "short", DB: mockDB() },
    );

    expect(res.status).toBe(503);
    expect(json.error).toBe("Server auth misconfigured");
  });

  // ---- 10. No DB + no JWT_SECRET → dev fallback succeeds ----
  it("succeeds with dev fallback secret when DB is not bound", async () => {
    const { res, json } = await call(
      { device_id: "dev-mode" },
      { JWT_SECRET: undefined, DB: undefined },
    );

    expect(res.status).toBe(200);
    expect(json.user_id).toBe("anon_dev-mode");
    expect(json.token).toBeTruthy();

    // The fallback secret is hard-coded in the handler.
    const claims = await verifyJWT(
      json.token,
      "vocal-dev-secret-rotate-in-prod",
    );
    expect(claims).not.toBeNull();
    expect(claims!.sub).toBe("anon_dev-mode");
  });

  // ---- 11. DB write failure → still returns successfully ----
  it("returns successfully even when the DB write throws", async () => {
    const failingDB = {
      prepare: vi.fn(() => ({
        bind: vi.fn().mockReturnThis(),
        run: vi.fn(async () => {
          throw new Error("D1 write failure");
        }),
      })),
    };

    const { res, json } = await call(
      { device_id: "db-fail" },
      { DB: failingDB },
    );

    expect(res.status).toBe(200);
    expect(json.user_id).toBe("anon_db-fail");
    expect(json.token).toBeTruthy();
  });

  // ---- 12. Rate limited → 429 ----
  it("returns 429 when rate limited", async () => {
    (checkRateLimit as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      allowed: false,
      retryAfterSec: 42,
      identifier: "ip:1.2.3.4",
    });

    const c = ctx({ device_id: "flood" });
    const res = await onRequestPost(c);

    expect(res.status).toBe(429);
    expect(rateLimitedResponse).toHaveBeenCalled();
  });
});
