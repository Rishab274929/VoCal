// Anonymous → authed data merge.
//
// When a user signs up with Google or Apple after using the app
// anonymously, we want their previously-logged meals + body metrics
// to follow them to the new identity. This is the "save my data when
// I sign up" guarantee.
//
// Safety posture:
//   - Verify the anon token via the auth helper. Without that an attacker
//     could pass an arbitrary anonUserId and steal another user's rows.
//   - Only delete the anon user row if `provider = anonymous` and the row
//     actually belongs to that id — never touch a previously-linked
//     account.
//   - Best-effort: errors here don't fail the parent auth call. The user
//     still gets a valid session; data merge can be retried.
//
// Caveats: D1 doesn't expose `provider` on the users table (the schema
// uses `apple_sub` to identify Apple accounts; google users have an id
// like `google_<sub>`; anonymous users have `anon_<deviceId>`). We rely
// on the id prefix to distinguish anonymous rows, since that's what the
// existing /api/auth/anonymous endpoint actually writes.

import { verifyJWT } from "./jwt";

export interface MergeResult {
  merged: number;
  errors: string[];
}

interface MergeEnv {
  DB?: D1Database;
  JWT_SECRET?: string;
}

/**
 * Move all data owned by `anonUserId` to `newUserId`, then delete the
 * anon user row. Returns the total row count moved (across all tables).
 *
 * - On invalid token: returns `{ merged: 0, errors: ["invalid anon token"] }`.
 *   Do NOT throw — the caller's auth flow continues regardless.
 * - On DB errors: returns the partial count + an `errors[]` array. The
 *   parent should log this; the merge can be re-attempted next sign-in.
 */
export async function mergeAnonymousData(
  env: MergeEnv,
  anonUserId: string,
  anonToken: string,
  newUserId: string
): Promise<MergeResult> {
  // --- 1. Verify the anonymous token belongs to anonUserId ---
  // Without this, an attacker could merge ANY user's rows into their own
  // new account by guessing or scraping anon ids.
  if (!env.JWT_SECRET || env.JWT_SECRET.length < 16) {
    // No secret means we can't verify the anon token. Refuse to merge
    // rather than trusting the client's claim.
    return { merged: 0, errors: ["jwt secret unconfigured"] };
  }
  if (!anonUserId || !anonToken || !newUserId) {
    return { merged: 0, errors: ["missing arguments"] };
  }
  if (anonUserId === newUserId) {
    // No-op merge — already the same identity. Avoid trampling a row onto
    // itself (would set updated_at unnecessarily).
    return { merged: 0, errors: [] };
  }

  const claims = await verifyJWT(anonToken, env.JWT_SECRET);
  if (!claims || claims.sub !== anonUserId) {
    return { merged: 0, errors: ["invalid anon token"] };
  }
  // Belt and suspenders: must actually claim to be an anonymous session.
  if (claims.anon !== true) {
    return { merged: 0, errors: ["token is not anonymous"] };
  }

  if (!env.DB) {
    // No DB bound — nothing to migrate. Not an error, just a no-op.
    return { merged: 0, errors: [] };
  }

  // Defensive: only treat ids that look like our anon convention as safe to
  // delete. The /api/auth/anonymous endpoint writes ids of the form
  // `anon_<sanitized-device-id>`; the deletion query also bounds on this.
  if (!/^anon_/.test(anonUserId)) {
    return { merged: 0, errors: ["anonUserId does not match anon_* convention"] };
  }

  // --- 2. Move rows in a batched transaction ---
  // D1's `batch()` runs the statements as a single implicit transaction —
  // if any statement fails the whole batch rolls back. We use it so we
  // don't end up with the meals moved but the body_metrics still on the
  // anon id (a half-state that's confusing to debug).
  const errors: string[] = [];
  let merged = 0;
  try {
    const statements = [
      env.DB.prepare(`UPDATE meals SET user_id = ?1 WHERE user_id = ?2`).bind(newUserId, anonUserId),
      env.DB.prepare(`UPDATE body_metrics SET user_id = ?1 WHERE user_id = ?2`).bind(newUserId, anonUserId),
      env.DB.prepare(`UPDATE coach_messages SET user_id = ?1 WHERE user_id = ?2`).bind(newUserId, anonUserId),
      // Only delete if the row still looks anonymous (id prefix). Avoids the
      // pathological case where the anon id was somehow promoted to a real
      // account between sign-in attempts.
      env.DB.prepare(`DELETE FROM users WHERE id = ?1 AND id LIKE 'anon_%'`).bind(anonUserId)
    ];
    const results = await env.DB.batch(statements);
    // results[0..2] are UPDATEs; .meta.changes is the row count.
    for (let i = 0; i < results.length - 1; i++) {
      const changes = (results[i]?.meta as { changes?: number } | undefined)?.changes ?? 0;
      merged += changes;
    }
  } catch (err) {
    // Some D1 deployments don't have the body_metrics or coach_messages
    // tables yet (older schema). The whole batch rolls back, so try a
    // narrower fallback that only touches `meals` — better partial merge
    // than zero.
    errors.push(`batch failed: ${(err as Error).message}`);
    try {
      const mealsRes = await env.DB
        .prepare(`UPDATE meals SET user_id = ?1 WHERE user_id = ?2`)
        .bind(newUserId, anonUserId)
        .run();
      merged += (mealsRes.meta as { changes?: number } | undefined)?.changes ?? 0;
      // Try the delete separately — won't fail just because other tables
      // are missing.
      await env.DB
        .prepare(`DELETE FROM users WHERE id = ?1 AND id LIKE 'anon_%'`)
        .bind(anonUserId)
        .run()
        .catch(() => undefined);
    } catch (err2) {
      errors.push(`fallback meals update failed: ${(err2 as Error).message}`);
    }
  }

  return { merged, errors };
}
