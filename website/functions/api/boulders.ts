// Boulder backend — Cloudflare Pages Function over D1.
//
// Replaces the old Supabase row store. Same shape: one row per
// sync_id, payload is the full BoulderModel JSON, last write wins.
//
// Routes (this file = /api/boulders):
//   GET  /api/boulders?sync_id=<uuid>   → 200 with {payload, updated_at} or 404
//   POST /api/boulders                  → upsert. Body: {sync_id, payload, ...}
//   OPTIONS                              → CORS preflight
//
// Auth model: your sync_id is the secret. Same as before — keep it
// private. Real auth lands when there's budget for a paid dev cert
// to do Apple/Google sign-in properly.

export interface Env {
  DB: D1Database;
}

interface UpsertBody {
  sync_id: string;
  payload: unknown;
  user_first_name?: string | null;
  rock_name?: string | null;
  grain_count?: number;
  schema_version?: number;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function corsHeaders(extra: Record<string, string> = {}): HeadersInit {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Max-Age": "86400",
    "Cache-Control": "no-store",
    ...extra,
  };
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: corsHeaders({ "Content-Type": "application/json" }),
  });
}

export const onRequestOptions: PagesFunction<Env> = () =>
  new Response(null, { status: 204, headers: corsHeaders() });

export const onRequestGet: PagesFunction<Env> = async (ctx) => {
  const url = new URL(ctx.request.url);
  const syncID = (url.searchParams.get("sync_id") || "").toLowerCase();
  if (!UUID_RE.test(syncID)) {
    return json(400, { error: "invalid sync_id" });
  }

  const row = await ctx.env.DB
    .prepare("SELECT payload, updated_at FROM boulders WHERE sync_id = ? LIMIT 1")
    .bind(syncID)
    .first<{ payload: string; updated_at: number }>();

  if (!row) return json(404, { error: "not found" });

  let payload: unknown = null;
  try { payload = JSON.parse(row.payload); } catch { /* corrupt row */ }
  return json(200, { payload, updated_at: row.updated_at });
};

export const onRequestPost: PagesFunction<Env> = async (ctx) => {
  let body: UpsertBody;
  try {
    body = await ctx.request.json<UpsertBody>();
  } catch {
    return json(400, { error: "invalid JSON body" });
  }

  const syncID = (body.sync_id || "").toLowerCase();
  if (!UUID_RE.test(syncID)) {
    return json(400, { error: "invalid sync_id" });
  }
  if (!body.payload || typeof body.payload !== "object") {
    return json(400, { error: "payload required (object)" });
  }

  // Reject absurd payloads to keep storage bounded — a Mountain-tier
  // rock with sessions log + tags caps somewhere around 1MB. 5MB is
  // generous.
  const payloadStr = JSON.stringify(body.payload);
  if (payloadStr.length > 5_000_000) {
    return json(413, { error: "payload too large" });
  }

  const grainCount = Number.isFinite(body.grain_count) ? Math.max(0, body.grain_count | 0) : 0;
  const schemaVersion = Number.isFinite(body.schema_version) ? (body.schema_version | 0) : 3;
  const nowSec = Math.floor(Date.now() / 1000);

  await ctx.env.DB
    .prepare(`
      INSERT INTO boulders (sync_id, payload, user_first_name, rock_name, grain_count, schema_version, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT (sync_id) DO UPDATE SET
        payload = excluded.payload,
        user_first_name = excluded.user_first_name,
        rock_name = excluded.rock_name,
        grain_count = excluded.grain_count,
        schema_version = excluded.schema_version,
        updated_at = excluded.updated_at
    `)
    .bind(
      syncID,
      payloadStr,
      body.user_first_name ?? null,
      body.rock_name ?? null,
      grainCount,
      schemaVersion,
      nowSec
    )
    .run();

  return json(200, { ok: true, updated_at: nowSec });
};
