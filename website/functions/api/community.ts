// Boulder Community Rock — shared global rock that grows with every
// focused minute from every opted-in user.
//
// GET  /api/community?limit=N&offset=M  → list grains, newest first
// POST /api/community                   → add up to 256 grains in one go
//
// Each grain stores the contributor's first name, what they were
// focused on (tag + blurb), and when. Clicking a grain on the web
// shows that info — like a global feed of focused effort.
//
// Privacy: contributor_id is a SHA-256 hash of the sync_id, so we
// can rate-limit per contributor without exposing the sync_id (which
// is also the device's edit secret for their personal rock).

export interface Env {
  DB: D1Database;
}

interface ContributeBody {
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
async function sha256Hex(s: string): Promise<string> {
  const data = new TextEncoder().encode(s);
  const buf = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

export const onRequestOptions: PagesFunction<Env> = () =>
  new Response(null, { status: 204, headers: corsHeaders() });

export const onRequestGet: PagesFunction<Env> = async (ctx) => {
  const url = new URL(ctx.request.url);
  const limit = Math.min(5000, Math.max(1, parseInt(url.searchParams.get("limit") || "1000", 10)));
  const offset = Math.max(0, parseInt(url.searchParams.get("offset") || "0", 10));

  const rows = await ctx.env.DB
    .prepare(`
      SELECT id, contributor_name, tag_name, tag_emoji, hue, shade, blurb, earned_at
      FROM community_grains
      ORDER BY id ASC
      LIMIT ? OFFSET ?
    `)
    .bind(limit, offset)
    .all<{
      id: number;
      contributor_name: string;
      tag_name: string;
      tag_emoji: string;
      hue: number;
      shade: number;
      blurb: string | null;
      earned_at: number;
    }>();

  const totalRes = await ctx.env.DB
    .prepare("SELECT COUNT(*) AS c FROM community_grains")
    .first<{ c: number }>();

  return json(200, {
    total: totalRes?.c ?? 0,
    grains: rows.results ?? [],
  });
};

export const onRequestPost: PagesFunction<Env> = async (ctx) => {
  let body: ContributeBody;
  try {
    body = await ctx.request.json<ContributeBody>();
  } catch {
    return json(400, { error: "invalid JSON" });
  }
  const syncID = (body.sync_id || "").toLowerCase();
  if (!UUID_RE.test(syncID)) return json(400, { error: "invalid sync_id" });

  const name = (body.contributor_name || "").trim().slice(0, 40);
  if (!name) return json(400, { error: "contributor_name required" });

  const grains = Array.isArray(body.grains) ? body.grains.slice(0, 256) : [];
  if (grains.length === 0) return json(400, { error: "grains array required" });

  const contributorID = await sha256Hex(`boulder:contrib:${syncID}`);

  // Rate-limit: cap a single contributor at 20,000 lifetime grains so
  // a single device can't dominate the community rock.
  const existing = await ctx.env.DB
    .prepare("SELECT COUNT(*) AS c FROM community_grains WHERE contributor_id = ?")
    .bind(contributorID)
    .first<{ c: number }>();
  const usedSlots = existing?.c ?? 0;
  const remaining = Math.max(0, 20_000 - usedSlots);
  const toInsert = grains.slice(0, remaining);
  if (toInsert.length === 0) {
    return json(429, { error: "contributor cap reached", inserted: 0 });
  }

  // Batch insert. D1 has a 100KB statement limit so we chunk.
  const CHUNK = 64;
  let inserted = 0;
  for (let i = 0; i < toInsert.length; i += CHUNK) {
    const slice = toInsert.slice(i, i + CHUNK);
    const placeholders = slice.map(() => "(?, ?, ?, ?, ?, ?, ?, ?)").join(", ");
    const values: (string | number | null)[] = [];
    for (const g of slice) {
      values.push(
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
        INSERT INTO community_grains
          (contributor_id, contributor_name, tag_name, tag_emoji, hue, shade, blurb, earned_at)
        VALUES ${placeholders}
      `)
      .bind(...values)
      .run();
    inserted += slice.length;
  }
  return json(200, { ok: true, inserted, cap_remaining: remaining - inserted });
};
