// Group rock grains.
//
// GET  /api/groups/<id>/grains    list grains in order
// POST /api/groups/<id>/grains    contribute up to 256 grains in one call

export interface Env {
  DB: D1Database;
}

interface PostBody {
  sync_id: string;
  contributor_name: string;
  grains: Array<{
    tag_name: string;
    tag_emoji: string;
    hue: number;
    shade: number;
    blurb?: string | null;
    earned_at: number;
  }>;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function corsHeaders(extra: Record<string, string> = {}): HeadersInit {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
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
async function sha256Hex(s: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

export const onRequestOptions: PagesFunction<Env> = () =>
  new Response(null, { status: 204, headers: corsHeaders() });

export const onRequestGet: PagesFunction<Env, "id"> = async (ctx) => {
  const groupID = String(ctx.params.id);
  if (!UUID_RE.test(groupID)) return json(400, { error: "invalid group id" });
  const url = new URL(ctx.request.url);
  const limit = Math.min(50_000, Math.max(1, parseInt(url.searchParams.get("limit") || "10000", 10)));
  const offset = Math.max(0, parseInt(url.searchParams.get("offset") || "0", 10));

  const rows = await ctx.env.DB
    .prepare(`
      SELECT id, contributor_name, tag_name, tag_emoji, hue, shade, blurb, earned_at
      FROM group_grains
      WHERE group_id = ?
      ORDER BY id ASC
      LIMIT ? OFFSET ?
    `)
    .bind(groupID, limit, offset)
    .all<{
      id: number; contributor_name: string; tag_name: string; tag_emoji: string;
      hue: number; shade: number; blurb: string | null; earned_at: number;
    }>();

  const total = await ctx.env.DB
    .prepare("SELECT COUNT(*) AS c FROM group_grains WHERE group_id = ?")
    .bind(groupID)
    .first<{ c: number }>();

  const group = await ctx.env.DB
    .prepare("SELECT id, name, invite_code FROM groups WHERE id = ? LIMIT 1")
    .bind(groupID)
    .first<{ id: string; name: string; invite_code: string }>();

  if (!group) return json(404, { error: "group not found" });

  return json(200, {
    group,
    total: total?.c ?? 0,
    grains: rows.results ?? [],
  });
};

export const onRequestPost: PagesFunction<Env, "id"> = async (ctx) => {
  const groupID = String(ctx.params.id);
  if (!UUID_RE.test(groupID)) return json(400, { error: "invalid group id" });

  // Ensure group exists.
  const group = await ctx.env.DB
    .prepare("SELECT id FROM groups WHERE id = ? LIMIT 1")
    .bind(groupID)
    .first<{ id: string }>();
  if (!group) return json(404, { error: "group not found" });

  let body: PostBody;
  try { body = await ctx.request.json<PostBody>(); }
  catch { return json(400, { error: "invalid JSON" }); }
  const syncID = (body.sync_id || "").toLowerCase();
  if (!UUID_RE.test(syncID)) return json(400, { error: "invalid sync_id" });
  const name = (body.contributor_name || "").trim().slice(0, 40);
  if (!name) return json(400, { error: "contributor_name required" });
  const grains = Array.isArray(body.grains) ? body.grains.slice(0, 256) : [];
  if (grains.length === 0) return json(400, { error: "grains required" });

  const contributorID = await sha256Hex(`boulder:contrib:${syncID}`);

  const CHUNK = 64;
  let inserted = 0;
  for (let i = 0; i < grains.length; i += CHUNK) {
    const slice = grains.slice(i, i + CHUNK);
    const placeholders = slice.map(() => "(?, ?, ?, ?, ?, ?, ?, ?, ?)").join(", ");
    const values: (string | number | null)[] = [];
    for (const g of slice) {
      values.push(
        groupID,
        contributorID,
        name,
        (g.tag_name || "Focus").slice(0, 40),
        (g.tag_emoji || "🪨").slice(0, 8),
        typeof g.hue === "number" ? Math.max(0, Math.min(1, g.hue)) : 0.5,
        typeof g.shade === "number" ? (g.shade | 0) : 10,
        g.blurb ? String(g.blurb).slice(0, 200) : null,
        typeof g.earned_at === "number" ? (g.earned_at | 0) : Math.floor(Date.now() / 1000)
      );
    }
    await ctx.env.DB
      .prepare(`
        INSERT INTO group_grains
          (group_id, contributor_id, contributor_name, tag_name, tag_emoji, hue, shade, blurb, earned_at)
        VALUES ${placeholders}
      `)
      .bind(...values)
      .run();
    inserted += slice.length;
  }

  return json(200, { ok: true, inserted });
};
