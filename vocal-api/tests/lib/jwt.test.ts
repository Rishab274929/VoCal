import { describe, it, expect } from "vitest";
import { signJWT, verifyJWT } from "../../src/lib/jwt";

const TEST_SECRET = "test-secret-key-for-jwt";

describe("signJWT / verifyJWT", () => {
  it("round-trips claims through sign and verify", async () => {
    const claims = { sub: "user_123", role: "admin" };
    const expiresAt = Date.now() + 60_000; // 1 minute from now

    const token = await signJWT(claims, TEST_SECRET, expiresAt);
    const result = await verifyJWT(token, TEST_SECRET);

    expect(result).not.toBeNull();
    expect(result!.sub).toBe("user_123");
    expect(result!.role).toBe("admin");
    expect(result!.iat).toBeTypeOf("number");
    expect(result!.exp).toBeTypeOf("number");
  });

  it("produces a 3-part base64url token", async () => {
    const token = await signJWT({}, TEST_SECRET, Date.now() + 60_000);
    const parts = token.split(".");

    expect(parts).toHaveLength(3);
    // base64url chars only (no +, /, or =)
    for (const part of parts) {
      expect(part).toMatch(/^[A-Za-z0-9_-]+$/);
    }
  });

  it("returns null when verifying with wrong secret", async () => {
    const token = await signJWT({ sub: "u1" }, TEST_SECRET, Date.now() + 60_000);
    const result = await verifyJWT(token, "wrong-secret");

    expect(result).toBeNull();
  });

  it("returns null for an expired token", async () => {
    const pastExpiry = Date.now() - 10_000; // 10 seconds ago
    const token = await signJWT({ sub: "u1" }, TEST_SECRET, pastExpiry);
    const result = await verifyJWT(token, TEST_SECRET);

    expect(result).toBeNull();
  });

  it("returns null for a malformed token (random string)", async () => {
    const result = await verifyJWT("not-a-jwt-at-all", TEST_SECRET);
    expect(result).toBeNull();
  });

  it("returns null for a token with only 2 parts", async () => {
    const result = await verifyJWT("header.payload", TEST_SECRET);
    expect(result).toBeNull();
  });

  it("returns null for a token with 4 parts", async () => {
    const result = await verifyJWT("a.b.c.d", TEST_SECRET);
    expect(result).toBeNull();
  });

  it("returns null for a tampered payload", async () => {
    const token = await signJWT({ sub: "u1" }, TEST_SECRET, Date.now() + 60_000);
    const parts = token.split(".");

    // Swap the payload with a different base64url-encoded JSON object
    const encoder = new TextEncoder();
    const tampered = JSON.stringify({ sub: "attacker", iat: 0, exp: 9999999999 });
    const rawBytes = encoder.encode(tampered);
    let b64 = btoa(String.fromCharCode(...rawBytes));
    b64 = b64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

    const tamperedToken = `${parts[0]}.${b64}.${parts[2]}`;
    const result = await verifyJWT(tamperedToken, TEST_SECRET);

    expect(result).toBeNull();
  });

  it("succeeds for a token with future expiry", async () => {
    const farFuture = Date.now() + 3_600_000; // 1 hour
    const token = await signJWT({ sub: "u1" }, TEST_SECRET, farFuture);
    const result = await verifyJWT(token, TEST_SECRET);

    expect(result).not.toBeNull();
    expect(result!.sub).toBe("u1");
  });

  it("preserves custom claim fields (sub, provider, anon, email)", async () => {
    const claims = {
      sub: "user_456",
      provider: "google",
      anon: false,
      email: "user@example.com",
      tier: "pro",
    };
    const token = await signJWT(claims, TEST_SECRET, Date.now() + 60_000);
    const result = await verifyJWT(token, TEST_SECRET);

    expect(result).not.toBeNull();
    expect(result!.sub).toBe("user_456");
    expect(result!.provider).toBe("google");
    expect(result!.anon).toBe(false);
    expect(result!.email).toBe("user@example.com");
    expect(result!.tier).toBe("pro");
  });

  it("sets iat to roughly the current time in seconds", async () => {
    const beforeSec = Math.floor(Date.now() / 1000);
    const token = await signJWT({}, TEST_SECRET, Date.now() + 60_000);
    const afterSec = Math.floor(Date.now() / 1000);

    const result = await verifyJWT(token, TEST_SECRET);
    expect(result).not.toBeNull();
    expect(result!.iat).toBeGreaterThanOrEqual(beforeSec);
    expect(result!.iat).toBeLessThanOrEqual(afterSec);
  });

  it("sets exp to expiresAt converted to seconds", async () => {
    const expiresAt = Date.now() + 120_000;
    const expectedExpSec = Math.floor(expiresAt / 1000);

    const token = await signJWT({}, TEST_SECRET, expiresAt);
    const result = await verifyJWT(token, TEST_SECRET);

    expect(result).not.toBeNull();
    expect(result!.exp).toBe(expectedExpSec);
  });

  it("returns null for an empty string token", async () => {
    const result = await verifyJWT("", TEST_SECRET);
    expect(result).toBeNull();
  });

  it("tokens signed with different secrets are not interchangeable", async () => {
    const token1 = await signJWT({ sub: "u1" }, "secret-A", Date.now() + 60_000);
    const token2 = await signJWT({ sub: "u1" }, "secret-B", Date.now() + 60_000);

    expect(await verifyJWT(token1, "secret-B")).toBeNull();
    expect(await verifyJWT(token2, "secret-A")).toBeNull();
    expect(await verifyJWT(token1, "secret-A")).not.toBeNull();
    expect(await verifyJWT(token2, "secret-B")).not.toBeNull();
  });
});
