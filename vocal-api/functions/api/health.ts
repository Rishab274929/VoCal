// Simple liveness check. Lets us verify the API is up.

export const onRequest: PagesFunction = async ({ env }) => {
  const bindings = env as unknown as { DB?: D1Database; CACHE?: KVNamespace };
  const hasDB = !!bindings.DB;
  const hasKV = !!bindings.CACHE;

  return new Response(
    JSON.stringify({
      ok: true,
      service: "vocal-api",
      ts: Date.now(),
      bindings: { d1: hasDB, kv: hasKV },
    }),
    {
      status: 200,
      headers: {
        "content-type": "application/json; charset=utf-8",
        "access-control-allow-origin": "*",
        "cache-control": "no-store",
      },
    },
  );
};
