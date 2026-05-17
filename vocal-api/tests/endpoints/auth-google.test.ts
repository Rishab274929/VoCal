import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { onRequestOptions, onRequestPost } from "../../functions/api/auth/google";
import { verifyJWT } from "../../src/lib/jwt";
import { mockDB, mockStatement, makeRequest } from "../helpers/mocks";

// ---------------------------------------------------------------------------
// Module mocks
// ---------------------------------------------------------------------------
vi.mock("../../src/lib/rateLimit", () => ({
  checkRateLimit: vi.fn(async () => ({
    allowed: true,
    retryAfterSec: 0,
    identifier: "test",
  })),
  rateLimitedResponse: vi.fn(
    () =>
      new Response(JSON.stringify({ error: "rate_limited", retry_after_sec: 30 }), {
        status: 429,
        headers: { "Content-Type": "application/json", "Retry-After": "30" },
      }),
  ),
}));

vi.mock("../../src/lib/identityMerge", () => ({
  mergeAnonymousData: vi.fn(async () => ({ merged: 0, errors: [] })),
}));

// ---------------------------------------------------------------------------
// Fetch mock — intercepts Google tokeninfo (and token exchange) calls
// ---------------------------------------------------------------------------
const originalFetch = globalThis.fetch;

function googleTokenInfo(overrides: Record<string, string> = {}): Record<string, string> {
  return {
    iss: "accounts.google.com",
    sub: "123456789",
    aud: "test-ios-client-id",
    exp: String(Math.floor(Date.now() / 1000) + 3600),
    email: "user@gmail.com",
    email_verified: "true",
    name: "Test User",
    picture: "https://example.com/pic.jpg",
    ...overrides,
  };
}

beforeEach(() => {
  globalThis.fetch = vi.fn(async (url: string | URL | Request) => {
    const urlStr =
      typeof url === "string" ? url : url instanceof URL ? url.toString() : url.url;

    if (urlStr.includes("oauth2.googleapis.com/tokeninfo")) {
      return new Response(JSON.stringify(googleTokenInfo()), { status: 200 });
    }
    // Token exchange endpoint (authorization_code flow)
    if (urlStr.includes("oauth2.googleapis.com/token")) {
      return new Response(
        JSON.stringify({ id_token: "header.eyJub25jZSI6InRlc3QifQ.sig" }),
        { status: 200 },
      );
    }
    return originalFetch(url as any);
  });
});

afterEach(() => {
  globalThis.fetch = originalFetch;
  vi.restoreAllMocks();
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
const JWT_SECRET = "google-auth-test-secret-long";

const baseEnv = () => ({
  JWT_SECRET,
  GOOGLE_CLIENT_ID_IOS: "test-ios-client-id",
  DB: mockDB(),
});

async function callPost(body: unknown, env?: Record<string, unknown>) {
  const request = makeRequest("POST", body);
  return onRequestPost({ request, env: env ?? baseEnv(), params: {} } as any);
}

async function json(r: Response) {
  return r.json() as Promise<Record<string, unknown>>;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
describe("POST /api/auth/google", () => {
  // 1. OPTIONS → 204 with CORS
  describe("onRequestOptions (CORS preflight)", () => {
    it("returns 204 with CORS headers", async () => {
      const res = await onRequestOptions();
      expect(res.status).toBe(204);
      expect(res.headers.get("Access-Control-Allow-Origin")).toBe("*");
      expect(res.headers.get("Access-Control-Allow-Methods")).toContain("POST");
      expect(res.headers.get("Access-Control-Allow-Headers")).toContain("Content-Type");
    });
  });

  // 2. Valid id_token → 200 with user_id, token, expires_at
  it("returns 200 with user_id, token, and ~7-day expires_at for valid id_token", async () => {
    const res = await callPost({ id_token: "valid.google.token" });
    expect(res.status).toBe(200);

    const data = await json(res);
    expect(data.user_id).toBe("google_123456789");
    expect(data.token).toBeTypeOf("string");
    expect((data.token as string).split(".")).toHaveLength(3);

    // expires_at should be ~7 days from now (within 10 seconds tolerance)
    const sevenDaysMs = 7 * 24 * 60 * 60 * 1000;
    const diff = Math.abs((data.expires_at as number) - (Date.now() + sevenDaysMs));
    expect(diff).toBeLessThan(10_000);
  });

  // 3. Returned token is verifiable with correct claims
  it("issues a verifiable JWT with provider:google", async () => {
    const res = await callPost({ id_token: "valid.google.token" });
    const data = await json(res);

    const claims = await verifyJWT(data.token as string, JWT_SECRET);
    expect(claims).not.toBeNull();
    expect(claims!.sub).toBe("google_123456789");
    expect(claims!.provider).toBe("google");
    expect(claims!.email).toBe("user@gmail.com");
    expect(claims!.google_sub).toBe("123456789");
  });

  // 4. Missing id_token AND authorization_code → 400
  it("returns 400 when both id_token and authorization_code are missing", async () => {
    const res = await callPost({});
    expect(res.status).toBe(400);
    const data = await json(res);
    expect(data.error).toContain("authorization_code or id_token required");
  });

  // 5. Invalid JSON body → 400
  it("returns 400 for invalid JSON body", async () => {
    const request = new Request("https://vocal.best/api/auth/google", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: "not-json{{{",
    });
    const res = await onRequestPost({ request, env: baseEnv(), params: {} } as any);
    expect(res.status).toBe(400);
    const data = await json(res);
    expect(data.error).toContain("Invalid JSON");
  });

  // 6. Google rejects id_token → 401
  it("returns 401 when Google tokeninfo rejects the id_token", async () => {
    (globalThis.fetch as ReturnType<typeof vi.fn>).mockImplementation(
      async (url: string | URL | Request) => {
        const urlStr =
          typeof url === "string" ? url : url instanceof URL ? url.toString() : url.url;
        if (urlStr.includes("oauth2.googleapis.com/tokeninfo")) {
          return new Response("invalid_token", { status: 400 });
        }
        return originalFetch(url as any);
      },
    );

    const res = await callPost({ id_token: "bad.token.here" });
    expect(res.status).toBe(401);
    const data = await json(res);
    expect(data.error).toContain("Google rejected");
  });

  // 7. Untrusted issuer → 401
  it("returns 401 for an untrusted issuer", async () => {
    (globalThis.fetch as ReturnType<typeof vi.fn>).mockImplementation(
      async (url: string | URL | Request) => {
        const urlStr =
          typeof url === "string" ? url : url instanceof URL ? url.toString() : url.url;
        if (urlStr.includes("oauth2.googleapis.com/tokeninfo")) {
          return new Response(
            JSON.stringify(googleTokenInfo({ iss: "evil.example.com" })),
            { status: 200 },
          );
        }
        return originalFetch(url as any);
      },
    );

    const res = await callPost({ id_token: "valid.google.token" });
    expect(res.status).toBe(401);
    const data = await json(res);
    expect(data.error).toContain("Untrusted issuer");
  });

  // 8. Expired token → 401
  it("returns 401 for an expired token", async () => {
    (globalThis.fetch as ReturnType<typeof vi.fn>).mockImplementation(
      async (url: string | URL | Request) => {
        const urlStr =
          typeof url === "string" ? url : url instanceof URL ? url.toString() : url.url;
        if (urlStr.includes("oauth2.googleapis.com/tokeninfo")) {
          return new Response(
            JSON.stringify(
              googleTokenInfo({ exp: String(Math.floor(Date.now() / 1000) - 600) }),
            ),
            { status: 200 },
          );
        }
        return originalFetch(url as any);
      },
    );

    const res = await callPost({ id_token: "expired.google.token" });
    expect(res.status).toBe(401);
    const data = await json(res);
    expect(data.error).toContain("expired");
  });

  // 9. Missing sub → 401
  it("returns 401 when sub is missing from tokeninfo", async () => {
    (globalThis.fetch as ReturnType<typeof vi.fn>).mockImplementation(
      async (url: string | URL | Request) => {
        const urlStr =
          typeof url === "string" ? url : url instanceof URL ? url.toString() : url.url;
        if (urlStr.includes("oauth2.googleapis.com/tokeninfo")) {
          const info = googleTokenInfo();
          delete (info as any).sub;
          return new Response(JSON.stringify(info), { status: 200 });
        }
        return originalFetch(url as any);
      },
    );

    const res = await callPost({ id_token: "valid.google.token" });
    expect(res.status).toBe(401);
    const data = await json(res);
    expect(data.error).toContain("missing sub");
  });

  // 10. No GOOGLE_CLIENT_ID_* configured → 503
  it("returns 503 when no GOOGLE_CLIENT_ID_* is configured", async () => {
    const env = {
      JWT_SECRET,
      DB: mockDB(),
      // deliberately no GOOGLE_CLIENT_ID_*
    };
    const res = await callPost({ id_token: "valid.google.token" }, env);
    expect(res.status).toBe(503);
    const data = await json(res);
    expect(data.error).toContain("not configured");
  });

  // 11. Wrong audience → 401
  it("returns 401 when audience does not match any configured client ID", async () => {
    (globalThis.fetch as ReturnType<typeof vi.fn>).mockImplementation(
      async (url: string | URL | Request) => {
        const urlStr =
          typeof url === "string" ? url : url instanceof URL ? url.toString() : url.url;
        if (urlStr.includes("oauth2.googleapis.com/tokeninfo")) {
          return new Response(
            JSON.stringify(googleTokenInfo({ aud: "some-other-app-client-id" })),
            { status: 200 },
          );
        }
        return originalFetch(url as any);
      },
    );

    const res = await callPost({ id_token: "valid.google.token" });
    expect(res.status).toBe(401);
    const data = await json(res);
    expect(data.error).toContain("Untrusted audience");
  });

  // 12. JWT_SECRET missing + DB bound → 503
  it("returns 503 when JWT_SECRET is missing and DB is bound", async () => {
    const env = {
      GOOGLE_CLIENT_ID_IOS: "test-ios-client-id",
      DB: mockDB(),
      // deliberately no JWT_SECRET
    };
    const res = await callPost({ id_token: "valid.google.token" }, env);
    expect(res.status).toBe(503);
    const data = await json(res);
    expect(data.error).toContain("misconfigured");
  });

  // 13. No DB → still issues a token (DB write is non-fatal)
  it("issues a token even when DB is not bound", async () => {
    const env = {
      JWT_SECRET,
      GOOGLE_CLIENT_ID_IOS: "test-ios-client-id",
      // no DB
    };
    const res = await callPost({ id_token: "valid.google.token" }, env);
    expect(res.status).toBe(200);

    const data = await json(res);
    expect(data.user_id).toBe("google_123456789");
    expect(data.token).toBeTypeOf("string");
  });

  // 14. is_new_user true on first sign-in, false on re-sign-in
  it("sets is_new_user to true on first sign-in", async () => {
    // Default mockDB().first() returns null → new user
    const res = await callPost({ id_token: "valid.google.token" });
    expect(res.status).toBe(200);
    const data = await json(res);
    expect(data.is_new_user).toBe(true);
  });

  it("sets is_new_user to false on re-sign-in", async () => {
    // Mock DB.first() to return an existing row
    const existingStmt = mockStatement();
    existingStmt.first.mockResolvedValue({ id: "google_123456789" });

    const db = mockDB();
    // The handler calls prepare() twice: once for SELECT, once for INSERT.
    // First call returns the "existing user" statement.
    let callCount = 0;
    db.prepare.mockImplementation(() => {
      callCount++;
      if (callCount === 1) return existingStmt;
      return mockStatement();
    });

    const env = { JWT_SECRET, GOOGLE_CLIENT_ID_IOS: "test-ios-client-id", DB: db };
    const res = await callPost({ id_token: "valid.google.token" }, env);
    expect(res.status).toBe(200);
    const data = await json(res);
    expect(data.is_new_user).toBe(false);
  });

  // 15. Rate limited → 429
  it("returns 429 when rate limited", async () => {
    const { checkRateLimit } = await import("../../src/lib/rateLimit");
    (checkRateLimit as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      allowed: false,
      retryAfterSec: 30,
      identifier: "test",
    });

    const res = await callPost({ id_token: "valid.google.token" });
    expect(res.status).toBe(429);
  });

  // 16. Email returned in response
  it("includes email, name, and picture in the response", async () => {
    const res = await callPost({ id_token: "valid.google.token" });
    expect(res.status).toBe(200);
    const data = await json(res);
    expect(data.email).toBe("user@gmail.com");
    expect(data.name).toBe("Test User");
    expect(data.picture).toBe("https://example.com/pic.jpg");
  });

  // 17. Unverified email → 401
  it("returns 401 for unverified email (email_verified:'false')", async () => {
    (globalThis.fetch as ReturnType<typeof vi.fn>).mockImplementation(
      async (url: string | URL | Request) => {
        const urlStr =
          typeof url === "string" ? url : url instanceof URL ? url.toString() : url.url;
        if (urlStr.includes("oauth2.googleapis.com/tokeninfo")) {
          return new Response(
            JSON.stringify(googleTokenInfo({ email_verified: "false" })),
            { status: 200 },
          );
        }
        return originalFetch(url as any);
      },
    );

    const res = await callPost({ id_token: "valid.google.token" });
    expect(res.status).toBe(401);
    const data = await json(res);
    expect(data.error).toContain("Email not verified");
  });

  // --- Additional edge cases ---

  it("accepts https://accounts.google.com as issuer", async () => {
    (globalThis.fetch as ReturnType<typeof vi.fn>).mockImplementation(
      async (url: string | URL | Request) => {
        const urlStr =
          typeof url === "string" ? url : url instanceof URL ? url.toString() : url.url;
        if (urlStr.includes("oauth2.googleapis.com/tokeninfo")) {
          return new Response(
            JSON.stringify(
              googleTokenInfo({ iss: "https://accounts.google.com" }),
            ),
            { status: 200 },
          );
        }
        return originalFetch(url as any);
      },
    );

    const res = await callPost({ id_token: "valid.google.token" });
    expect(res.status).toBe(200);
  });

  it("accepts Android client ID as audience", async () => {
    (globalThis.fetch as ReturnType<typeof vi.fn>).mockImplementation(
      async (url: string | URL | Request) => {
        const urlStr =
          typeof url === "string" ? url : url instanceof URL ? url.toString() : url.url;
        if (urlStr.includes("oauth2.googleapis.com/tokeninfo")) {
          return new Response(
            JSON.stringify(googleTokenInfo({ aud: "test-android-client-id" })),
            { status: 200 },
          );
        }
        return originalFetch(url as any);
      },
    );

    const env = {
      ...baseEnv(),
      GOOGLE_CLIENT_ID_ANDROID: "test-android-client-id",
    };
    const res = await callPost({ id_token: "valid.google.token" }, env);
    expect(res.status).toBe(200);
  });

  it("returns 401 for exp=0 (missing/invalid exp)", async () => {
    (globalThis.fetch as ReturnType<typeof vi.fn>).mockImplementation(
      async (url: string | URL | Request) => {
        const urlStr =
          typeof url === "string" ? url : url instanceof URL ? url.toString() : url.url;
        if (urlStr.includes("oauth2.googleapis.com/tokeninfo")) {
          return new Response(
            JSON.stringify(googleTokenInfo({ exp: "0" })),
            { status: 200 },
          );
        }
        return originalFetch(url as any);
      },
    );

    const res = await callPost({ id_token: "valid.google.token" });
    expect(res.status).toBe(401);
  });

  it("uses dev fallback secret when JWT_SECRET is missing and no DB", async () => {
    const env = {
      GOOGLE_CLIENT_ID_IOS: "test-ios-client-id",
      // no JWT_SECRET, no DB
    };
    const res = await callPost({ id_token: "valid.google.token" }, env);
    expect(res.status).toBe(200);

    const data = await json(res);
    // Verify the token was signed with the dev fallback secret
    const claims = await verifyJWT(
      data.token as string,
      "vocal-dev-secret-rotate-in-prod",
    );
    expect(claims).not.toBeNull();
    expect(claims!.sub).toBe("google_123456789");
  });

  it("returns CORS headers on error responses", async () => {
    const res = await callPost({});
    expect(res.status).toBe(400);
    expect(res.headers.get("Access-Control-Allow-Origin")).toBe("*");
  });
});
