import { describe, it, expect, vi } from "vitest";
import { checkRateLimit, rateLimitedResponse } from "../../src/lib/rateLimit";

// --- helpers ---

function makeReq(ip?: string): Request {
  const headers: Record<string, string> = {};
  if (ip) headers["CF-Connecting-IP"] = ip;
  return new Request("https://test.com", { headers });
}

const mockKV = (store: Record<string, string> = {}) => ({
  get: vi.fn(async (key: string) => store[key] ?? null),
  put: vi.fn(async (key: string, value: string) => {
    store[key] = value;
  }),
});

// --- checkRateLimit ---

describe("checkRateLimit", () => {
  // ---- 1. No FOOD_KV bound → fail open ----
  it("allows requests when FOOD_KV is not bound", async () => {
    const result = await checkRateLimit({}, makeReq("1.2.3.4"), "test", 5);

    expect(result.allowed).toBe(true);
    expect(result.retryAfterSec).toBe(0);
    expect(result.identifier).toBe("no-kv");
  });

  // ---- 2. Under limit → allowed ----
  it("allows a request under the limit", async () => {
    const kv = mockKV();
    const result = await checkRateLimit(
      { FOOD_KV: kv as any },
      makeReq("10.0.0.1"),
      "photo/parse",
      10,
    );

    expect(result.allowed).toBe(true);
    expect(result.retryAfterSec).toBe(0);
    // identifier should include the IP
    expect(result.identifier).toContain("10.0.0.1");
    // should have written the incremented count
    expect(kv.put).toHaveBeenCalledOnce();
  });

  it("allows requests that are still below the limit", async () => {
    // Pre-seed 4 requests; limit is 5 → one more is fine
    const store: Record<string, string> = {};
    const kv = mockKV(store);

    // First 4 requests
    for (let i = 0; i < 4; i++) {
      await checkRateLimit(
        { FOOD_KV: kv as any },
        makeReq("10.0.0.2"),
        "meals",
        5,
      );
    }

    // 5th request should still be allowed (count was 4, limit is 5)
    const result = await checkRateLimit(
      { FOOD_KV: kv as any },
      makeReq("10.0.0.2"),
      "meals",
      5,
    );
    expect(result.allowed).toBe(true);
  });

  // ---- 3. At/over limit → blocked ----
  it("blocks when at the limit", async () => {
    // Pre-populate KV so that the count equals the limit
    const kv = mockKV();
    kv.get.mockResolvedValue("5");

    const result = await checkRateLimit(
      { FOOD_KV: kv as any },
      makeReq("10.0.0.3"),
      "photo/parse",
      5,
    );

    expect(result.allowed).toBe(false);
    expect(result.retryAfterSec).toBeGreaterThan(0);
    expect(result.retryAfterSec).toBeLessThanOrEqual(60);
  });

  it("blocks when over the limit", async () => {
    const kv = mockKV();
    kv.get.mockResolvedValue("100");

    const result = await checkRateLimit(
      { FOOD_KV: kv as any },
      makeReq("10.0.0.4"),
      "coach",
      10,
    );

    expect(result.allowed).toBe(false);
    expect(result.retryAfterSec).toBeGreaterThan(0);
  });

  // ---- 4. KV read error → fail open ----
  it("fails open on KV get error", async () => {
    const kv = mockKV();
    kv.get.mockRejectedValueOnce(new Error("KV unavailable"));

    const result = await checkRateLimit(
      { FOOD_KV: kv as any },
      makeReq("10.0.0.5"),
      "photo/parse",
      5,
    );

    expect(result.allowed).toBe(true);
    expect(result.retryAfterSec).toBe(0);
  });

  // ---- 5. KV write error → still allowed ----
  it("allows request even when KV put fails", async () => {
    const kv = mockKV();
    kv.put.mockRejectedValueOnce(new Error("KV write failed"));
    // Suppress the console.warn from the implementation
    vi.spyOn(console, "warn").mockImplementation(() => {});

    const result = await checkRateLimit(
      { FOOD_KV: kv as any },
      makeReq("10.0.0.6"),
      "photo/parse",
      10,
    );

    expect(result.allowed).toBe(true);
    expect(result.retryAfterSec).toBe(0);
  });

  // ---- additional coverage ----
  it("uses 'unknown' when no IP header is present", async () => {
    const kv = mockKV();
    const result = await checkRateLimit(
      { FOOD_KV: kv as any },
      makeReq(), // no IP
      "test",
      10,
    );

    expect(result.allowed).toBe(true);
    expect(result.identifier).toContain("unknown");
  });
});

// --- rateLimitedResponse ---

describe("rateLimitedResponse", () => {
  it("returns a 429 Response", () => {
    const result = { allowed: false, retryAfterSec: 30, identifier: "ip:1.2.3.4" };
    const resp = rateLimitedResponse(result);

    expect(resp.status).toBe(429);
  });

  it("sets Retry-After header", () => {
    const result = { allowed: false, retryAfterSec: 42, identifier: "ip:1.2.3.4" };
    const resp = rateLimitedResponse(result);

    expect(resp.headers.get("Retry-After")).toBe("42");
  });

  it("returns JSON body with error and retry_after_sec", async () => {
    const result = { allowed: false, retryAfterSec: 15, identifier: "u:user_1" };
    const resp = rateLimitedResponse(result);
    const body = await resp.json() as Record<string, unknown>;

    expect(body.error).toBe("rate_limited");
    expect(body.retry_after_sec).toBe(15);
  });

  it("sets Content-Type to application/json", () => {
    const result = { allowed: false, retryAfterSec: 10, identifier: "ip:x" };
    const resp = rateLimitedResponse(result);

    expect(resp.headers.get("Content-Type")).toBe("application/json");
  });

  it("merges custom CORS headers", () => {
    const result = { allowed: false, retryAfterSec: 5, identifier: "ip:x" };
    const cors = {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST",
    };
    const resp = rateLimitedResponse(result, cors);

    expect(resp.headers.get("Access-Control-Allow-Origin")).toBe("*");
    expect(resp.headers.get("Access-Control-Allow-Methods")).toBe("GET, POST");
    // original headers preserved
    expect(resp.headers.get("Retry-After")).toBe("5");
    expect(resp.headers.get("Content-Type")).toBe("application/json");
  });
});
