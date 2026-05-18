// Group rocks — friends share one rock, grow it together.
//
// POST /api/groups            create a group {name} → {id, invite_code}
// GET  /api/groups?code=ABC23 look up a group + grain count by invite code

export interface Env {
  DB: D1Database;
}

interface CreateBody {
  sync_id: string;
  name: string;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Friendly alphabet — no 0/O/1/I/l ambiguity.
const ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

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
function randomCode(len = 6): string {
  const arr = new Uint8Array(len);
  crypto.getRandomValues(arr);
  let s = "";
  for (const b of arr) s += ALPHABET[b % ALPHABET.length];
  return s;
}

export const onRequestOptions: PagesFunction<Env> = () =>
  new Response(null, { status: 204, headers: corsHeaders() });

export const onRequestGet: PagesFunction<Env> = async (ctx) => {
  const url = new URL(ctx.request.url);
  const code = (url.searchParams.get("code") || "").toUpperCase().trim();
  if (!/^[A-Z2-9]{6}$/.test(code)) {
    return json(400, { error: "invalid code" });
  }
  const row = await ctx.env.DB
    .prepare("SELECT id, name, invite_code, created_at FROM groups WHERE invite_code = ? LIMIT 1")
    .bind(code)
    .first<{ id: string; name: string; invite_code: string; created_at: number }>();
  if (!row) return json(404, { error: "no group with that code" });
  const count = await ctx.env.DB
    .prepare("SELECT COUNT(*) AS c FROM group_grains WHERE group_id = ?")
    .bind(row.id)
    .first<{ c: number }>();
  return json(200, { group: { ...row, grain_count: count?.c ?? 0 } });
};

export const onRequestPost: PagesFunction<Env> = async (ctx) => {
  let body: CreateBody;
  try { body = await ctx.request.json<CreateBody>(); }
  catch { return json(400, { error: "invalid JSON" }); }

  const syncID = (body.sync_id || "").toLowerCase();
  if (!UUID_RE.test(syncID)) return json(400, { error: "invalid sync_id" });

  const name = (body.name || "").trim().slice(0, 60);
  if (!name) return json(400, { error: "name required" });

  const id = crypto.randomUUID();
  const creator = await sha256Hex(`boulder:contrib:${syncID}`);

  // Retry on rare invite-code collision (P=1/30^6 ≈ 1 in 730M, but
  // we'll be defensive anyway).
  for (let attempt = 0; attempt < 5; attempt++) {
    const code = randomCode(6);
    try {
      await ctx.env.DB
        .prepare(`
          INSERT INTO groups (id, invite_code, name, created_by, created_at)
          VALUES (?, ?, ?, ?, ?)
        `)
        .bind(id, code, name, creator, Math.floor(Date.now() / 1000))
        .run();
      return json(200, { id, invite_code: code, name });
    } catch (e) {
      // Likely UNIQUE conflict on invite_code; try again.
      if (attempt === 4) return json(500, { error: "couldn't generate unique code" });
    }
  }
  return json(500, { error: "couldn't generate unique code" });
};
