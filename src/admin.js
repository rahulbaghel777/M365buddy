const ADMIN_EMAIL = "rahulbaghel777@gmail.com";
const MAX_BODY = 20000;
let jwksCache = { expires: 0, keys: [] };

function response(data, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
    "x-content-type-options": "nosniff"
  }});
}
function decodePart(value) {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  return JSON.parse(atob(normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=")));
}
async function getKeys(teamDomain) {
  if (jwksCache.expires > Date.now() && jwksCache.keys.length) return jwksCache.keys;
  const host = teamDomain.replace(/^https?:\/\//, "").replace(/\/$/, "");
  const res = await fetch(`https://${host}/cdn-cgi/access/certs`, { cf: { cacheTtl: 300 } });
  if (!res.ok) throw new Error("Unable to load Access signing keys");
  const data = await res.json();
  jwksCache = { keys: data.keys || [], expires: Date.now() + 5 * 60 * 1000 };
  return jwksCache.keys;
}
async function verifyAccess(request, env) {
  const token = request.headers.get("cf-access-jwt-assertion");
  if (!token || !env.ACCESS_TEAM_DOMAIN || !env.ACCESS_AUD) return null;
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  try {
    const header = decodePart(parts[0]);
    const claims = decodePart(parts[1]);
    const now = Math.floor(Date.now() / 1000);
    const issuer = `https://${env.ACCESS_TEAM_DOMAIN.replace(/^https?:\/\//, "").replace(/\/$/, "")}`;
    if (header.alg !== "RS256" || claims.iss !== issuer || !claims.exp || claims.exp <= now ||
        (claims.nbf && claims.nbf > now) ||
        !(Array.isArray(claims.aud) ? claims.aud.includes(env.ACCESS_AUD) : claims.aud === env.ACCESS_AUD)) return null;
    const jwk = (await getKeys(env.ACCESS_TEAM_DOMAIN)).find(key => key.kid === header.kid);
    if (!jwk) return null;
    const publicKey = await crypto.subtle.importKey("jwk", jwk, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]);
    const data = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);
    const signature = Uint8Array.from(atob(parts[2].replace(/-/g, "+").replace(/_/g, "/")), c => c.charCodeAt(0));
    if (!await crypto.subtle.verify("RSASSA-PKCS1-v1_5", publicKey, signature, data)) return null;
    const email = String(claims.email || "").toLowerCase();
    if (email !== ADMIN_EMAIL) return null;
    return email;
  } catch (error) {
    console.error("Access JWT validation failed", error?.message || error);
    return null;
  }
}
async function readJson(request) {
  const len = Number(request.headers.get("content-length") || 0);
  if (len > MAX_BODY) throw new Error("Request too large");
  return request.json();
}
async function audit(db, actor, action, resourceId, details = {}) {
  await db.prepare("INSERT INTO audit_logs(actor_email,action,resource_id,details_json) VALUES(?,?,?,?)")
    .bind(actor, action, resourceId || null, JSON.stringify(details)).run();
}
async function enqueue(db, approvalId, title, status) {
  const sender = "rahulbaghel777@gmail.com";
  await db.prepare("INSERT INTO notification_outbox(approval_id,recipient,sender,subject,body,status) VALUES(?,?,?,?,?,'QUEUED')")
    .bind(approvalId, ADMIN_EMAIL, sender, `M365Buddy approval: ${title}`, `Approval item "${title}" is now ${status}. Review: https://m365buddy.com/admin/approvals/`).run();
}
export async function handleAdmin(request, env) {
  const url = new URL(request.url);
  const isAdminPath = url.pathname.startsWith("/admin/") || url.pathname.startsWith("/api/admin/");
  if (!isAdminPath) return null;
  const email = await verifyAccess(request, env);
  if (!email) return response({ error: "Authentication required." }, 401);
  if (url.pathname.startsWith("/admin/")) {
    const asset = await env.ASSETS.fetch(new Request(new URL("/admin/approvals/index.html", request.url), request));
    if (!asset.ok) return asset;
    const headers = new Headers(asset.headers);
    headers.set("cache-control", "no-store");
    headers.set("x-robots-tag", "noindex, nofollow");
    return new Response(asset.body, { status: asset.status, headers });
  }
  if (!env.APPROVAL_DB) return response({ error: "Approval database is not configured." }, 503);
  const db = env.APPROVAL_DB;
  if (url.pathname === "/api/admin/intake" && request.method === "POST") {
    let body;
    try { body = await readJson(request); } catch (e) { return response({ error: e.message || "Invalid JSON." }, 400); }
    const question = String(body.question || "").trim().slice(0, 5000);
    const title = String(body.title || "New M365Buddy content proposal").trim().slice(0, 180);
    const draft = String(body.draft || "").trim().slice(0, 12000);
    const channel = body.channel === "chatgpt" ? "chatgpt" : "website";
    const type = ["article","community_question","community_reply","solution_update"].includes(body.content_type) ? body.content_type : "article";
    if (!question || !draft) return response({ error: "Question and draft are required." }, 400);
    const id = crypto.randomUUID();
    const intakeId = crypto.randomUUID();
    const sources = Array.isArray(body.sources) ? body.sources.slice(0, 8) : [];
    await db.batch([
      db.prepare("INSERT INTO intake_requests(id,channel,requester_email,question) VALUES(?,?,?,?)").bind(intakeId, channel, email, question),
      db.prepare("INSERT INTO approval_items(id,intake_id,content_type,title,draft,sources_json) VALUES(?,?,?,?,?,?)").bind(id, intakeId, type, title, draft, JSON.stringify(sources)),
      db.prepare("INSERT INTO approval_events(approval_id,actor_email,action,details_json) VALUES(?,?,?,?)").bind(id, email, "SUBMITTED", JSON.stringify({ channel }))
    ]);
    await audit(db, email, "INTAKE_CREATED", id, { channel, content_type: type });
    await enqueue(db, id, title, "PENDING_APPROVAL");
    return response({ id, status: "PENDING_APPROVAL" }, 201);
  }
  if (url.pathname === "/api/admin/approvals" && request.method === "GET") {
    const status = url.searchParams.get("status");
    const result = status
      ? await db.prepare("SELECT a.*, i.channel, i.question, i.requester_email FROM approval_items a JOIN intake_requests i ON i.id=a.intake_id WHERE a.status=? ORDER BY a.created_at DESC LIMIT 100").bind(status).all()
      : await db.prepare("SELECT a.*, i.channel, i.question, i.requester_email FROM approval_items a JOIN intake_requests i ON i.id=a.intake_id ORDER BY a.created_at DESC LIMIT 100").all();
    return response({ items: (result.results || []).map(row => ({ ...row, sources: JSON.parse(row.sources_json || "[]") })) });
  }
  const match = url.pathname.match(/^\/api\/admin\/approvals\/([0-9a-f-]+)$/i);
  if (match && request.method === "PATCH") {
    let body;
    try { body = await readJson(request); } catch (e) { return response({ error: e.message || "Invalid JSON." }, 400); }
    const action = body.action;
    if (!["approve","reject","save"].includes(action)) return response({ error: "Action must be approve, reject or save." }, 400);
    const current = await db.prepare("SELECT id,status,title FROM approval_items WHERE id=?").bind(match[1]).first();
    if (!current) return response({ error: "Approval item not found." }, 404);
    if (current.status !== "PENDING_APPROVAL") return response({ error: "Only pending items can be reviewed." }, 409);
    const draft = typeof body.draft === "string" ? body.draft.trim().slice(0,12000) : null;
    if (action === "save") {
      if (!draft) return response({ error: "Draft cannot be empty." }, 400);
      await db.prepare("UPDATE approval_items SET draft=?,updated_at=datetime('now') WHERE id=? AND status='PENDING_APPROVAL'").bind(draft, match[1]).run();
    } else {
      const status = action === "approve" ? "APPROVED" : "REJECTED";
      await db.prepare("UPDATE approval_items SET status=?,draft=COALESCE(?,draft),reviewer_email=?,reviewed_at=datetime('now'),updated_at=datetime('now') WHERE id=? AND status='PENDING_APPROVAL'").bind(status, draft, email, match[1]).run();
      await db.prepare("INSERT INTO approval_events(approval_id,actor_email,action,details_json) VALUES(?,?,?,?)").bind(match[1], email, status, JSON.stringify({ title: current.title })).run();
      await audit(db, email, status, match[1], { title: current.title });
      await enqueue(db, match[1], current.title, status);
    }
    return response({ id: match[1], action, saved: true });
  }
  if (url.pathname === "/api/admin/audit" && request.method === "GET") {
    const rows = await db.prepare("SELECT * FROM audit_logs ORDER BY created_at DESC LIMIT 100").all();
    return response({ items: rows.results || [] });
  }
  return response({ error: "Not found." }, 404);
}
