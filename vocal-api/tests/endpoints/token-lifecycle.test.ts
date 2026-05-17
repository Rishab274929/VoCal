import { describe, it, expect, vi } from "vitest";
import { signJWT, verifyJWT } from "../../src/lib/jwt";
import {
  authIdentity,
  resolveUserId,
  requireUserId,
  requireUserIdOrMint,
  AuthRequiredError,
  requirePro,
  EntitlementRequiredError,
  mintedSessionHeaders,
} from "../../src/lib/auth";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const SECRET = "token-lifecycle-test-secret-32c";

function makeReq(token?: string): Request {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (token) headers["Authorization"] = `Bearer ${token}`;
  return new Request("https://vocal.best/api/test", { method: "POST", headers });
}

function makeEnv(secret: string = SECRET) {
  return { JWT_SECRET: secret };
}

async function mintAnon(userId: string, ttlMs = 60_000): Promise<string> {
  return signJWT({ sub: userId, anon: true }, SECRET, Date.now() + ttlMs);
}

async function mintGoogle(sub: string, ttlMs = 60_000): Promise<string> {
  return signJWT({ sub, provider: "google" }, SECRET, Date.now() + ttlMs);
}

async function mintApple(sub: string, ttlMs = 60_000): Promise<string> {
  return signJWT({ sub, provider: "apple" }, SECRET, Date.now() + ttlMs);
}

function mockDBWithEntitlement(
  row: { is_pro: number; expires_at: number | null; product_id: string | null } | null
) {
  const stmt: any = {
    bind: vi.fn().mockReturnThis(),
    run: vi.fn(async () => ({ meta: { changes: 0 } })),
    first: vi.fn(async () => row),
    all: vi.fn(async () => ({ results: row ? [row] : [] })),
  };
  return {
    prepare: vi.fn(() => stmt),
    batch: vi.fn(async () => []),
  };
}

// ===========================================================================
// Anonymous token lifecycle
// ===========================================================================

describe("Anonymous token lifecycle", () => {
  it("1. minted anonymous token is recognized with provider 'anonymous' and correct userId", async () => {
    const token = await mintAnon("anon_user_001");
    const identity = await authIdentity(makeReq(token), makeEnv());

    expect(identity.userId).toBe("anon_user_001");
    expect(identity.provider).toBe("anonymous");
    expect(identity.claims).not.toBeNull();
    expect(identity.claims!.anon).toBe(true);
  });

  it("2. minted anonymous token is accepted by requireUserId and returns userId", async () => {
    const token = await mintAnon("anon_user_002");
    const { userId, identity } = await requireUserId(makeEnv(), makeReq(token));

    expect(userId).toBe("anon_user_002");
    expect(identity.provider).toBe("anonymous");
  });

  it("3. expired anonymous token → authIdentity returns null identity", async () => {
    const token = await signJWT({ sub: "anon_expired", anon: true }, SECRET, Date.now() - 10_000);
    const identity = await authIdentity(makeReq(token), makeEnv());

    expect(identity.userId).toBeNull();
    expect(identity.provider).toBeNull();
    expect(identity.claims).toBeNull();
  });

  it("4. expired anonymous token → requireUserId throws AuthRequiredError('invalid')", async () => {
    const token = await signJWT({ sub: "anon_expired", anon: true }, SECRET, Date.now() - 10_000);

    try {
      await requireUserId(makeEnv(), makeReq(token));
      expect.unreachable("should have thrown");
    } catch (err) {
      expect(err).toBeInstanceOf(AuthRequiredError);
      expect((err as AuthRequiredError).reason).toBe("invalid");
    }
  });
});

// ===========================================================================
// Google token lifecycle
// ===========================================================================

describe("Google token lifecycle", () => {
  it("5. Google-provider token is recognized with provider 'google'", async () => {
    const token = await mintGoogle("google_123");
    const identity = await authIdentity(makeReq(token), makeEnv());

    expect(identity.userId).toBe("google_123");
    expect(identity.provider).toBe("google");
    expect(identity.claims!.provider).toBe("google");
  });

  it("6. Google token → requireUserId returns 'google_123'", async () => {
    const token = await mintGoogle("google_123");
    const { userId } = await requireUserId(makeEnv(), makeReq(token));

    expect(userId).toBe("google_123");
  });
});

// ===========================================================================
// Apple token lifecycle
// ===========================================================================

describe("Apple token lifecycle", () => {
  it("7. Apple-provider token is recognized with provider 'apple'", async () => {
    const token = await mintApple("apple_abc");
    const identity = await authIdentity(makeReq(token), makeEnv());

    expect(identity.userId).toBe("apple_abc");
    expect(identity.provider).toBe("apple");
    expect(identity.claims!.provider).toBe("apple");
  });
});

// ===========================================================================
// resolveUserId integration
// ===========================================================================

describe("resolveUserId integration", () => {
  it("8. valid JWT identity + matching body userId → source 'jwt', mismatch false", async () => {
    const token = await mintAnon("anon_resolve");
    const identity = await authIdentity(makeReq(token), makeEnv());
    const result = resolveUserId(identity, "anon_resolve");

    expect(result.source).toBe("jwt");
    expect(result.mismatch).toBe(false);
    expect(result.userId).toBe("anon_resolve");
  });

  it("9. valid JWT identity + different body userId → source 'jwt', mismatch true", async () => {
    const token = await mintAnon("anon_resolve");
    const identity = await authIdentity(makeReq(token), makeEnv());
    const result = resolveUserId(identity, "someone_else");

    expect(result.source).toBe("jwt");
    expect(result.mismatch).toBe(true);
    expect(result.userId).toBe("anon_resolve");
  });

  it("10. no JWT (null identity) + body userId → source 'body'", async () => {
    const identity = await authIdentity(makeReq(), makeEnv());
    const result = resolveUserId(identity, "body_user_id");

    expect(result.source).toBe("body");
    expect(result.userId).toBe("body_user_id");
    expect(result.mismatch).toBe(false);
  });

  it("11. no JWT + no body → source 'default', userId 'demo-user'", async () => {
    const identity = await authIdentity(makeReq(), makeEnv());
    const result = resolveUserId(identity, null);

    expect(result.source).toBe("default");
    expect(result.userId).toBe("demo-user");
    expect(result.mismatch).toBe(false);
  });
});

// ===========================================================================
// requireUserIdOrMint
// ===========================================================================

describe("requireUserIdOrMint", () => {
  it("12. request WITH valid Bearer → returns JWT userId, no mintedSession", async () => {
    const token = await mintAnon("anon_existing");
    const result = await requireUserIdOrMint(makeEnv(), makeReq(token));

    expect(result.userId).toBe("anon_existing");
    expect(result.identity.provider).toBe("anonymous");
    expect(result.mintedSession).toBeUndefined();
  });

  it("13. request WITH invalid Bearer → throws AuthRequiredError('invalid')", async () => {
    const token = await signJWT({ sub: "u" }, "wrong-secret-long-enough", Date.now() + 60_000);

    try {
      await requireUserIdOrMint(makeEnv(), makeReq(token));
      expect.unreachable("should have thrown");
    } catch (err) {
      expect(err).toBeInstanceOf(AuthRequiredError);
      expect((err as AuthRequiredError).reason).toBe("invalid");
    }
  });

  it("14. request WITHOUT any Bearer + no DB → mints a new session", async () => {
    const result = await requireUserIdOrMint(makeEnv(), makeReq());

    expect(result.mintedSession).toBeDefined();
    expect(result.mintedSession!.token).toBeTypeOf("string");
    expect(result.mintedSession!.token.split(".")).toHaveLength(3);
    expect(result.userId).toMatch(/^anon_/);
    expect(result.mintedSession!.userId).toBe(result.userId);
    expect(result.identity.provider).toBe("anonymous");
  });

  it("15. the mintedSession token is itself valid via verifyJWT", async () => {
    const result = await requireUserIdOrMint(makeEnv(), makeReq());

    expect(result.mintedSession).toBeDefined();
    const claims = await verifyJWT(result.mintedSession!.token, SECRET);
    expect(claims).not.toBeNull();
    expect(claims!.sub).toBe(result.userId);
    expect(claims!.anon).toBe(true);
  });
});

// ===========================================================================
// requirePro
// ===========================================================================

describe("requirePro", () => {
  it("16. valid JWT but no DB → throws EntitlementRequiredError('no_row')", async () => {
    const token = await mintAnon("anon_pro_test");

    try {
      await requirePro({ JWT_SECRET: SECRET }, makeReq(token));
      expect.unreachable("should have thrown");
    } catch (err) {
      expect(err).toBeInstanceOf(EntitlementRequiredError);
      expect((err as EntitlementRequiredError).reason).toBe("no_row");
    }
  });

  it("17. valid JWT + DB has is_pro=1 row → succeeds with entitlement", async () => {
    const token = await mintGoogle("google_pro");
    const db = mockDBWithEntitlement({
      is_pro: 1,
      expires_at: Date.now() + 86_400_000,
      product_id: "com.vocal.pro.yearly",
    });

    const result = await requirePro(
      { JWT_SECRET: SECRET, DB: db as any },
      makeReq(token)
    );

    expect(result.userId).toBe("google_pro");
    expect(result.entitlement.isPro).toBe(true);
    expect(result.entitlement.productId).toBe("com.vocal.pro.yearly");
    expect(result.entitlement.expiresAt).toBeTypeOf("number");
  });

  it("18. valid JWT + DB has is_pro=0 → throws EntitlementRequiredError('not_pro')", async () => {
    const token = await mintGoogle("google_free");
    const db = mockDBWithEntitlement({
      is_pro: 0,
      expires_at: null,
      product_id: null,
    });

    try {
      await requirePro({ JWT_SECRET: SECRET, DB: db as any }, makeReq(token));
      expect.unreachable("should have thrown");
    } catch (err) {
      expect(err).toBeInstanceOf(EntitlementRequiredError);
      expect((err as EntitlementRequiredError).reason).toBe("not_pro");
    }
  });

  it("19. valid JWT + DB has expired row → throws EntitlementRequiredError('expired')", async () => {
    const token = await mintGoogle("google_lapsed");
    const db = mockDBWithEntitlement({
      is_pro: 1,
      expires_at: Date.now() - 86_400_000, // expired yesterday
      product_id: "com.vocal.pro.monthly",
    });

    try {
      await requirePro({ JWT_SECRET: SECRET, DB: db as any }, makeReq(token));
      expect.unreachable("should have thrown");
    } catch (err) {
      expect(err).toBeInstanceOf(EntitlementRequiredError);
      expect((err as EntitlementRequiredError).reason).toBe("expired");
    }
  });

  it("20. valid JWT + DB has no row → throws EntitlementRequiredError('no_row')", async () => {
    const token = await mintGoogle("google_norow");
    const db = mockDBWithEntitlement(null);

    try {
      await requirePro({ JWT_SECRET: SECRET, DB: db as any }, makeReq(token));
      expect.unreachable("should have thrown");
    } catch (err) {
      expect(err).toBeInstanceOf(EntitlementRequiredError);
      expect((err as EntitlementRequiredError).reason).toBe("no_row");
    }
  });
});

// ===========================================================================
// mintedSessionHeaders
// ===========================================================================

describe("mintedSessionHeaders", () => {
  it("21. returns correct X-Vocal-Anon-User-Id, X-Vocal-Anon-Token, X-Vocal-Anon-Expires-At", async () => {
    const result = await requireUserIdOrMint(makeEnv(), makeReq());
    const minted = result.mintedSession!;
    const headers = mintedSessionHeaders(minted);

    expect(headers["X-Vocal-Anon-User-Id"]).toBe(minted.userId);
    expect(headers["X-Vocal-Anon-Token"]).toBe(minted.token);
    expect(headers["X-Vocal-Anon-Expires-At"]).toBe(String(minted.expiresAt));

    // Verify the token in the header is actually valid
    const claims = await verifyJWT(headers["X-Vocal-Anon-Token"], SECRET);
    expect(claims).not.toBeNull();
    expect(claims!.sub).toBe(minted.userId);
  });
});

// ===========================================================================
// Cross-provider token isolation
// ===========================================================================

describe("Cross-provider token isolation", () => {
  it("22. Google-provider token does NOT have anon claim", async () => {
    const token = await mintGoogle("google_isolation");
    const identity = await authIdentity(makeReq(token), makeEnv());

    expect(identity.provider).toBe("google");
    expect(identity.claims!.anon).toBeUndefined();
    expect(identity.claims!.provider).toBe("google");
  });

  it("23. anonymous token has anon:true in claims", async () => {
    const token = await mintAnon("anon_isolation");
    const identity = await authIdentity(makeReq(token), makeEnv());

    expect(identity.provider).toBe("anonymous");
    expect(identity.claims!.anon).toBe(true);
    // Anonymous tokens should NOT have a provider claim
    expect(identity.claims!.provider).toBeUndefined();
  });
});
