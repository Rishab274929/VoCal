import { describe, it, expect } from "vitest";
import { signJWT } from "../../src/lib/jwt";
import {
  authIdentity,
  resolveUserId,
  requireUserId,
  AuthRequiredError,
  authErrorResponse,
  EntitlementRequiredError,
  proRequiredResponse,
  mintedSessionHeaders,
  type AuthIdentity as AuthIdentityType,
  type MintedSession,
} from "../../src/lib/auth";

const TEST_SECRET = "test-secret-that-is-long-enough";

function makeReq(token?: string): Request {
  const headers: Record<string, string> = {};
  if (token) headers["Authorization"] = `Bearer ${token}`;
  return new Request("https://test.com", { headers });
}

function makeEnv(secret: string = TEST_SECRET) {
  return { JWT_SECRET: secret };
}

async function mintToken(
  claims: Record<string, unknown>,
  secret: string = TEST_SECRET
): Promise<string> {
  return signJWT(claims, secret, Date.now() + 60_000);
}

// ---------------------------------------------------------------------------
// authIdentity
// ---------------------------------------------------------------------------

describe("authIdentity", () => {
  it("returns null identity when no Authorization header is present", async () => {
    const result = await authIdentity(makeReq(), makeEnv());
    expect(result.userId).toBeNull();
    expect(result.provider).toBeNull();
    expect(result.claims).toBeNull();
  });

  it("returns null identity for malformed header (no Bearer prefix)", async () => {
    const req = new Request("https://test.com", {
      headers: { Authorization: "Token abc123" },
    });
    const result = await authIdentity(req, makeEnv());
    expect(result.userId).toBeNull();
    expect(result.provider).toBeNull();
    expect(result.claims).toBeNull();
  });

  it("returns null identity when JWT_SECRET is missing", async () => {
    const token = await mintToken({ sub: "user_1" });
    const result = await authIdentity(makeReq(token), { JWT_SECRET: undefined });
    expect(result.userId).toBeNull();
  });

  it("returns null identity when JWT_SECRET is too short (<16 chars)", async () => {
    const token = await mintToken({ sub: "user_1" });
    const result = await authIdentity(makeReq(token), makeEnv("short"));
    expect(result.userId).toBeNull();
    expect(result.provider).toBeNull();
  });

  it("returns correct userId and claims for a valid token", async () => {
    const token = await mintToken({ sub: "user_42" });
    const result = await authIdentity(makeReq(token), makeEnv());
    expect(result.userId).toBe("user_42");
    expect(result.claims).not.toBeNull();
    expect(result.claims!.sub).toBe("user_42");
  });

  it("detects google provider", async () => {
    const token = await mintToken({ sub: "g_user", provider: "google" });
    const result = await authIdentity(makeReq(token), makeEnv());
    expect(result.provider).toBe("google");
    expect(result.userId).toBe("g_user");
  });

  it("detects apple provider", async () => {
    const token = await mintToken({ sub: "a_user", provider: "apple" });
    const result = await authIdentity(makeReq(token), makeEnv());
    expect(result.provider).toBe("apple");
    expect(result.userId).toBe("a_user");
  });

  it("detects anonymous provider via anon claim", async () => {
    const token = await mintToken({ sub: "anon_xyz", anon: true });
    const result = await authIdentity(makeReq(token), makeEnv());
    expect(result.provider).toBe("anonymous");
    expect(result.userId).toBe("anon_xyz");
  });

  it("returns null provider when no provider or anon claim is set", async () => {
    const token = await mintToken({ sub: "plain_user" });
    const result = await authIdentity(makeReq(token), makeEnv());
    expect(result.provider).toBeNull();
    expect(result.userId).toBe("plain_user");
  });

  it("returns null identity when token is signed with wrong secret", async () => {
    const token = await signJWT({ sub: "u1" }, "wrong-secret-abcdefgh", Date.now() + 60_000);
    const result = await authIdentity(makeReq(token), makeEnv());
    expect(result.userId).toBeNull();
    expect(result.claims).toBeNull();
  });

  it("returns null identity for an expired token", async () => {
    const token = await signJWT({ sub: "u1" }, TEST_SECRET, Date.now() - 10_000);
    const result = await authIdentity(makeReq(token), makeEnv());
    expect(result.userId).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// resolveUserId
// ---------------------------------------------------------------------------

describe("resolveUserId", () => {
  it("prefers JWT identity over body userId", () => {
    const identity: AuthIdentityType = {
      userId: "jwt_user",
      provider: "google",
      claims: { sub: "jwt_user" },
    };
    const result = resolveUserId(identity, "body_user");
    expect(result.userId).toBe("jwt_user");
    expect(result.source).toBe("jwt");
  });

  it("falls back to body userId when JWT identity is null", () => {
    const identity: AuthIdentityType = {
      userId: null,
      provider: null,
      claims: null,
    };
    const result = resolveUserId(identity, "body_user");
    expect(result.userId).toBe("body_user");
    expect(result.source).toBe("body");
    expect(result.mismatch).toBe(false);
  });

  it("falls back to 'demo-user' when neither JWT nor body is present", () => {
    const identity: AuthIdentityType = {
      userId: null,
      provider: null,
      claims: null,
    };
    const result = resolveUserId(identity, null);
    expect(result.userId).toBe("demo-user");
    expect(result.source).toBe("default");
    expect(result.mismatch).toBe(false);
  });

  it("falls back to 'demo-user' for empty/whitespace body", () => {
    const identity: AuthIdentityType = {
      userId: null,
      provider: null,
      claims: null,
    };
    const result = resolveUserId(identity, "   ");
    expect(result.userId).toBe("demo-user");
    expect(result.source).toBe("default");
  });

  it("sets mismatch = true when JWT and body disagree", () => {
    const identity: AuthIdentityType = {
      userId: "jwt_user",
      provider: "anonymous",
      claims: { sub: "jwt_user" },
    };
    const result = resolveUserId(identity, "different_body_user");
    expect(result.mismatch).toBe(true);
    expect(result.userId).toBe("jwt_user");
    expect(result.source).toBe("jwt");
  });

  it("sets mismatch = false when JWT and body agree", () => {
    const identity: AuthIdentityType = {
      userId: "same_user",
      provider: "google",
      claims: { sub: "same_user" },
    };
    const result = resolveUserId(identity, "same_user");
    expect(result.mismatch).toBe(false);
  });

  it("sets mismatch = false when body is null/undefined", () => {
    const identity: AuthIdentityType = {
      userId: "jwt_user",
      provider: "google",
      claims: { sub: "jwt_user" },
    };
    expect(resolveUserId(identity, null).mismatch).toBe(false);
    expect(resolveUserId(identity, undefined).mismatch).toBe(false);
  });

  it("sanitizes special characters from userId", () => {
    const identity: AuthIdentityType = {
      userId: "user<script>alert(1)</script>",
      provider: null,
      claims: { sub: "user<script>alert(1)</script>" },
    };
    const result = resolveUserId(identity, null);
    expect(result.userId).not.toContain("<");
    expect(result.userId).not.toContain(">");
    expect(result.userId).not.toContain("(");
    expect(result.userId).toBe("userscriptalert1script");
  });

  it("sanitizes body userId too", () => {
    const identity: AuthIdentityType = {
      userId: null,
      provider: null,
      claims: null,
    };
    const result = resolveUserId(identity, "bad/user@name!");
    expect(result.userId).toBe("badusername");
    expect(result.source).toBe("body");
  });

  it("preserves allowed special chars (_.:-)", () => {
    const identity: AuthIdentityType = {
      userId: "user_name.test:id-123",
      provider: null,
      claims: { sub: "user_name.test:id-123" },
    };
    const result = resolveUserId(identity, null);
    expect(result.userId).toBe("user_name.test:id-123");
  });

  it("truncates userId to 96 characters", () => {
    const longId = "a".repeat(200);
    const identity: AuthIdentityType = {
      userId: longId,
      provider: null,
      claims: { sub: longId },
    };
    const result = resolveUserId(identity, null);
    expect(result.userId).toHaveLength(96);
  });
});

// ---------------------------------------------------------------------------
// requireUserId
// ---------------------------------------------------------------------------

describe("requireUserId", () => {
  it('throws AuthRequiredError with reason "missing" when no header', async () => {
    await expect(requireUserId(makeEnv(), makeReq())).rejects.toThrow(
      AuthRequiredError
    );
    try {
      await requireUserId(makeEnv(), makeReq());
    } catch (err) {
      expect(err).toBeInstanceOf(AuthRequiredError);
      expect((err as AuthRequiredError).reason).toBe("missing");
    }
  });

  it('throws AuthRequiredError with reason "missing" for non-Bearer header', async () => {
    const req = new Request("https://test.com", {
      headers: { Authorization: "Basic abc123" },
    });
    try {
      await requireUserId(makeEnv(), req);
    } catch (err) {
      expect(err).toBeInstanceOf(AuthRequiredError);
      expect((err as AuthRequiredError).reason).toBe("missing");
    }
  });

  it('throws AuthRequiredError with reason "invalid" when token fails verification', async () => {
    const token = await signJWT({ sub: "u1" }, "wrong-secret-abcdefgh", Date.now() + 60_000);
    try {
      await requireUserId(makeEnv(), makeReq(token));
    } catch (err) {
      expect(err).toBeInstanceOf(AuthRequiredError);
      expect((err as AuthRequiredError).reason).toBe("invalid");
    }
  });

  it("returns userId and identity when token is valid", async () => {
    const token = await mintToken({ sub: "valid_user", provider: "google" });
    const result = await requireUserId(makeEnv(), makeReq(token));
    expect(result.userId).toBe("valid_user");
    expect(result.identity.userId).toBe("valid_user");
    expect(result.identity.provider).toBe("google");
  });

  it("sanitizes the returned userId", async () => {
    const token = await mintToken({ sub: "user/with@bad#chars" });
    const result = await requireUserId(makeEnv(), makeReq(token));
    expect(result.userId).toBe("userwithbadchars");
  });
});

// ---------------------------------------------------------------------------
// AuthRequiredError
// ---------------------------------------------------------------------------

describe("AuthRequiredError", () => {
  it('has the correct message for "missing"', () => {
    const err = new AuthRequiredError("missing");
    expect(err.message).toBe("missing bearer token");
    expect(err.reason).toBe("missing");
    expect(err).toBeInstanceOf(Error);
  });

  it('has the correct message for "invalid"', () => {
    const err = new AuthRequiredError("invalid");
    expect(err.message).toBe("invalid bearer token");
    expect(err.reason).toBe("invalid");
  });
});

// ---------------------------------------------------------------------------
// authErrorResponse
// ---------------------------------------------------------------------------

describe("authErrorResponse", () => {
  it("returns a 401 response with auth_required code for missing reason", async () => {
    const err = new AuthRequiredError("missing");
    const res = authErrorResponse(err);
    expect(res.status).toBe(401);
    const body = await res.json() as { error: string; detail: string };
    expect(body.error).toBe("auth_required");
    expect(body.detail).toBe("missing bearer token");
  });

  it("returns a 401 response with auth_invalid code for invalid reason", async () => {
    const err = new AuthRequiredError("invalid");
    const res = authErrorResponse(err);
    expect(res.status).toBe(401);
    const body = await res.json() as { error: string; detail: string };
    expect(body.error).toBe("auth_invalid");
  });

  it("includes Content-Type and WWW-Authenticate headers", () => {
    const res = authErrorResponse(new AuthRequiredError("missing"));
    expect(res.headers.get("Content-Type")).toBe("application/json");
    expect(res.headers.get("WWW-Authenticate")).toBe('Bearer realm="vocal-api"');
  });

  it("merges in CORS headers when provided", () => {
    const cors = {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST",
    };
    const res = authErrorResponse(new AuthRequiredError("missing"), cors);
    expect(res.headers.get("Access-Control-Allow-Origin")).toBe("*");
    expect(res.headers.get("Access-Control-Allow-Methods")).toBe("GET, POST");
    expect(res.headers.get("Content-Type")).toBe("application/json");
  });
});

// ---------------------------------------------------------------------------
// EntitlementRequiredError
// ---------------------------------------------------------------------------

describe("EntitlementRequiredError", () => {
  it('has correct message for "no_row"', () => {
    const err = new EntitlementRequiredError("no_row");
    expect(err.reason).toBe("no_row");
    expect(err.message).toBe("no entitlement on file");
    expect(err).toBeInstanceOf(Error);
  });

  it('has correct message for "expired"', () => {
    const err = new EntitlementRequiredError("expired");
    expect(err.reason).toBe("expired");
    expect(err.message).toBe("entitlement expired");
  });

  it('has correct message for "not_pro"', () => {
    const err = new EntitlementRequiredError("not_pro");
    expect(err.reason).toBe("not_pro");
    expect(err.message).toBe("no active Pro entitlement");
  });
});

// ---------------------------------------------------------------------------
// proRequiredResponse
// ---------------------------------------------------------------------------

describe("proRequiredResponse", () => {
  it("returns a 402 response with pro_required error and reason", async () => {
    const err = new EntitlementRequiredError("expired");
    const res = proRequiredResponse(err);
    expect(res.status).toBe(402);
    const body = await res.json() as { error: string; detail: string; reason: string };
    expect(body.error).toBe("pro_required");
    expect(body.reason).toBe("expired");
    expect(body.detail).toBe("entitlement expired");
  });

  it("includes Content-Type header", () => {
    const res = proRequiredResponse(new EntitlementRequiredError("no_row"));
    expect(res.headers.get("Content-Type")).toBe("application/json");
  });

  it("merges CORS headers when provided", () => {
    const cors = { "Access-Control-Allow-Origin": "https://app.vocal.dev" };
    const res = proRequiredResponse(new EntitlementRequiredError("not_pro"), cors);
    expect(res.headers.get("Access-Control-Allow-Origin")).toBe("https://app.vocal.dev");
  });
});

// ---------------------------------------------------------------------------
// mintedSessionHeaders
// ---------------------------------------------------------------------------

describe("mintedSessionHeaders", () => {
  it("returns all three X-Vocal-Anon-* headers", () => {
    const minted: MintedSession = {
      userId: "anon_abc123",
      token: "jwt.token.here",
      expiresAt: 1700000000000,
    };
    const headers = mintedSessionHeaders(minted);
    expect(headers["X-Vocal-Anon-User-Id"]).toBe("anon_abc123");
    expect(headers["X-Vocal-Anon-Token"]).toBe("jwt.token.here");
    expect(headers["X-Vocal-Anon-Expires-At"]).toBe("1700000000000");
  });

  it("converts expiresAt to a string", () => {
    const minted: MintedSession = {
      userId: "u",
      token: "t",
      expiresAt: 42,
    };
    const headers = mintedSessionHeaders(minted);
    expect(typeof headers["X-Vocal-Anon-Expires-At"]).toBe("string");
    expect(headers["X-Vocal-Anon-Expires-At"]).toBe("42");
  });
});
