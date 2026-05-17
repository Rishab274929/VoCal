import { describe, it, expect, vi } from "vitest";
import { mergeAnonymousData } from "../../src/lib/identityMerge";
import { signJWT } from "../../src/lib/jwt";

const SECRET = "merge-test-secret-long-enough";

/** Sign a valid anonymous token for the given user id. */
async function anonToken(userId: string, overrides?: Record<string, unknown>) {
  return signJWT(
    { sub: userId, anon: true, ...overrides },
    SECRET,
    Date.now() + 60_000,
  );
}

function mockDB(): any {
  return {
    prepare: vi.fn(() => ({
      bind: vi.fn().mockReturnThis(),
      run: vi.fn(async () => ({ meta: { changes: 3 } })),
    })),
    batch: vi.fn(async () => [
      { meta: { changes: 2 } },
      { meta: { changes: 1 } },
      { meta: { changes: 0 } },
      { meta: { changes: 0 } },
      { meta: { changes: 0 } },
      { meta: { changes: 1 } },
    ]),
  };
}

describe("mergeAnonymousData", () => {
  // ---- 1. JWT_SECRET unconfigured ----
  it("returns error when JWT_SECRET is missing", async () => {
    const result = await mergeAnonymousData(
      { JWT_SECRET: undefined },
      "anon_abc",
      "tok",
      "user_1",
    );
    expect(result).toEqual({ merged: 0, errors: ["jwt secret unconfigured"] });
  });

  it("returns error when JWT_SECRET is too short", async () => {
    const result = await mergeAnonymousData(
      { JWT_SECRET: "short" },
      "anon_abc",
      "tok",
      "user_1",
    );
    expect(result).toEqual({ merged: 0, errors: ["jwt secret unconfigured"] });
  });

  // ---- 2. Missing arguments ----
  it("returns error when anonUserId is empty", async () => {
    const result = await mergeAnonymousData(
      { JWT_SECRET: SECRET },
      "",
      "tok",
      "user_1",
    );
    expect(result).toEqual({ merged: 0, errors: ["missing arguments"] });
  });

  it("returns error when anonToken is empty", async () => {
    const result = await mergeAnonymousData(
      { JWT_SECRET: SECRET },
      "anon_abc",
      "",
      "user_1",
    );
    expect(result).toEqual({ merged: 0, errors: ["missing arguments"] });
  });

  it("returns error when newUserId is empty", async () => {
    const result = await mergeAnonymousData(
      { JWT_SECRET: SECRET },
      "anon_abc",
      "tok",
      "",
    );
    expect(result).toEqual({ merged: 0, errors: ["missing arguments"] });
  });

  // ---- 3. Same identity (no-op) ----
  it("returns no-op when anonUserId equals newUserId", async () => {
    const result = await mergeAnonymousData(
      { JWT_SECRET: SECRET },
      "anon_abc",
      "tok",
      "anon_abc",
    );
    expect(result).toEqual({ merged: 0, errors: [] });
  });

  // ---- 4. Invalid / expired token ----
  it("rejects an invalid token (wrong secret)", async () => {
    const token = await signJWT(
      { sub: "anon_abc", anon: true },
      "different-secret-entirely!!",
      Date.now() + 60_000,
    );
    const result = await mergeAnonymousData(
      { JWT_SECRET: SECRET },
      "anon_abc",
      token,
      "user_1",
    );
    expect(result).toEqual({ merged: 0, errors: ["invalid anon token"] });
  });

  it("rejects an expired token", async () => {
    const token = await signJWT(
      { sub: "anon_abc", anon: true },
      SECRET,
      Date.now() - 10_000,
    );
    const result = await mergeAnonymousData(
      { JWT_SECRET: SECRET },
      "anon_abc",
      token,
      "user_1",
    );
    expect(result).toEqual({ merged: 0, errors: ["invalid anon token"] });
  });

  // ---- 5. Token sub mismatch ----
  it("rejects when token sub does not match anonUserId", async () => {
    const token = await anonToken("anon_other");
    const result = await mergeAnonymousData(
      { JWT_SECRET: SECRET },
      "anon_abc",
      token,
      "user_1",
    );
    expect(result).toEqual({ merged: 0, errors: ["invalid anon token"] });
  });

  // ---- 6. Token missing anon:true ----
  it("rejects a token without anon:true", async () => {
    const token = await signJWT(
      { sub: "anon_abc", provider: "google" },
      SECRET,
      Date.now() + 60_000,
    );
    const result = await mergeAnonymousData(
      { JWT_SECRET: SECRET },
      "anon_abc",
      token,
      "user_1",
    );
    expect(result).toEqual({ merged: 0, errors: ["token is not anonymous"] });
  });

  // ---- 7. anonUserId without anon_ prefix ----
  it("rejects anonUserId that does not start with anon_", async () => {
    const token = await anonToken("google_abc");
    const result = await mergeAnonymousData(
      { JWT_SECRET: SECRET, DB: mockDB() },
      "google_abc",
      token,
      "user_1",
    );
    expect(result).toEqual({
      merged: 0,
      errors: ["anonUserId does not match anon_* convention"],
    });
  });

  // ---- 8. No DB bound ----
  it("returns silent no-op when DB is not bound", async () => {
    const token = await anonToken("anon_abc");
    const result = await mergeAnonymousData(
      { JWT_SECRET: SECRET },
      "anon_abc",
      token,
      "user_1",
    );
    expect(result).toEqual({ merged: 0, errors: [] });
  });

  // ---- 9. Successful merge with mocked DB ----
  it("performs a successful merge and sums batch changes", async () => {
    const db = mockDB();
    const token = await anonToken("anon_device123");
    const result = await mergeAnonymousData(
      { JWT_SECRET: SECRET, DB: db },
      "anon_device123",
      token,
      "google_realuser",
    );

    // batch returns [2,1,0,0,0,1] — sum of first 5 (all except last) = 3
    expect(result.merged).toBe(3);
    expect(result.errors).toEqual([]);
    expect(db.batch).toHaveBeenCalledOnce();
  });

  it("calls prepare for each SQL statement", async () => {
    const db = mockDB();
    const token = await anonToken("anon_dev");
    await mergeAnonymousData(
      { JWT_SECRET: SECRET, DB: db },
      "anon_dev",
      token,
      "apple_user",
    );

    // 6 statements: 3 UPDATEs + 1 DELETE entitlements + 1 UPDATE entitlements + 1 DELETE users
    expect(db.prepare).toHaveBeenCalledTimes(6);
  });

  it("falls back to meals-only merge on batch error", async () => {
    const db = mockDB();
    db.batch.mockRejectedValueOnce(new Error("table body_metrics not found"));
    const token = await anonToken("anon_fallback");
    const result = await mergeAnonymousData(
      { JWT_SECRET: SECRET, DB: db },
      "anon_fallback",
      token,
      "google_new",
    );

    // Fallback prepare().bind().run() returns { meta: { changes: 3 } }
    expect(result.merged).toBe(3);
    expect(result.errors.length).toBeGreaterThanOrEqual(1);
    expect(result.errors[0]).toContain("batch failed");
  });
});
