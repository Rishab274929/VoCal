// Minimal HS256 JWT — no dependencies, Workers-compatible.

function base64UrlEncode(input: ArrayBuffer | Uint8Array): string {
  const bytes = input instanceof Uint8Array ? input : new Uint8Array(input);
  let str = "";
  for (let i = 0; i < bytes.length; i++) str += String.fromCharCode(bytes[i]);
  return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64UrlDecode(input: string): Uint8Array {
  const padded = input.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((input.length + 3) % 4);
  const raw = atob(padded);
  const bytes = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
  return bytes;
}

async function hmacSha256(key: string, data: string): Promise<ArrayBuffer> {
  const enc = new TextEncoder();
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    enc.encode(key),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
  return crypto.subtle.sign("HMAC", cryptoKey, enc.encode(data));
}

export async function signJWT(
  claims: Record<string, unknown>,
  secret: string,
  expiresAt: number,
): Promise<string> {
  const header = { alg: "HS256", typ: "JWT" };
  const payload = { ...claims, iat: Math.floor(Date.now() / 1000), exp: Math.floor(expiresAt / 1000) };

  const enc = new TextEncoder();
  const headerB64 = base64UrlEncode(enc.encode(JSON.stringify(header)));
  const payloadB64 = base64UrlEncode(enc.encode(JSON.stringify(payload)));
  const signingInput = `${headerB64}.${payloadB64}`;
  const sig = await hmacSha256(secret, signingInput);
  const sigB64 = base64UrlEncode(sig);
  return `${signingInput}.${sigB64}`;
}

export async function verifyJWT(
  token: string,
  secret: string,
): Promise<Record<string, unknown> | null> {
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  const [headerB64, payloadB64, sigB64] = parts;
  const signingInput = `${headerB64}.${payloadB64}`;
  const expectedSig = await hmacSha256(secret, signingInput);
  const expectedSigB64 = base64UrlEncode(expectedSig);
  if (expectedSigB64 !== sigB64) return null;

  try {
    const payloadBytes = base64UrlDecode(payloadB64);
    const payloadStr = new TextDecoder().decode(payloadBytes);
    const payload = JSON.parse(payloadStr) as Record<string, unknown>;
    const exp = payload.exp as number | undefined;
    if (exp && exp * 1000 < Date.now()) return null;
    return payload;
  } catch {
    return null;
  }
}
