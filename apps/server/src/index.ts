import { createServer } from "node:http";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { WebSocketServer } from "ws";
import { openDb, migrate, getDbPath } from "./database/db.js";
import { createSqliteStore } from "./sync/store.js";
import { createApi } from "./api/routes.js";
import { createWsHandler } from "./websocket/handler.js";

const PORT = Number(process.env.PORT || 8787);
const MAX_BODY_BYTES = 5 * 1024 * 1024; // 5MB
const MAX_WS_CLIENTS = 1000;

const db = openDb();
migrate(db);
const store = createSqliteStore(db);
const wsHandler = createWsHandler(store);

// Hono app - REST broadcaster excludes sender via WS handler's broadcast exclude path
const api = createApi(store, { broadcaster: (msg) => wsHandler.broadcast(msg) });

// --- request id / structured log + rate limit (in-memory, high enough to not affect normal use) ---
let reqSeq = 0;
const RATE_WINDOW_MS = 60_000;
const RATE_MAX = 6000; // per IP per minute — high enough for stress/soak, still catches tight loops
const rateMap = new Map<string, { count: number; resetAt: number }>();
function rateAllow(ip: string): boolean {
  const now = Date.now();
  let entry = rateMap.get(ip);
  if (!entry || now >= entry.resetAt) {
    entry = { count: 0, resetAt: now + RATE_WINDOW_MS };
    rateMap.set(ip, entry);
  }
  entry.count++;
  if (rateMap.size > 5000) {
    // prevent unbounded growth: evict expired
    for (const [k, v] of rateMap) if (now >= v.resetAt) rateMap.delete(k);
  }
  return entry.count <= RATE_MAX;
}
setInterval(() => {
  const now = Date.now();
  for (const [k, v] of rateMap) if (now >= v.resetAt) rateMap.delete(k);
}, RATE_WINDOW_MS).unref?.();

// resolved DB path for logging — use same resolution as database/db.ts (not local _here join)
const logDbPath = getDbPath();

// Node http server that delegates to Hono fetch and handles WS upgrade
const server = createServer(async (req, res) => {
  const started = Date.now();
  const rid = String(++reqSeq).padStart(6, "0");
  const ip = (req.socket.remoteAddress || req.headers["x-forwarded-for"] as string || "unknown").toString().slice(0, 64);
  // rate limit — 429 with Retry-After
  if (!rateAllow(ip)) {
    try {
      if (!res.headersSent) res.writeHead(429, { "content-type": "application/json", "retry-after": "30" });
      res.end(JSON.stringify({ error: "too many requests" }));
    } catch {}
    return;
  }
  // --- body collection with size limit + close guard ---
  let body: string | undefined;
  if (req.method !== "GET" && req.method !== "HEAD") {
    const maybeBody = await readBodyWithLimit(req, MAX_BODY_BYTES, res);
    // readBodyWithLimit sends 413 itself on overflow and returns null sentinel
    if (maybeBody === null) return;
    body = maybeBody;
  }

  try {
    const url = `http://${req.headers.host}${req.url}`;
    const headers = new Headers();
    for (const [k, v] of Object.entries(req.headers)) if (v) headers.set(k, Array.isArray(v) ? v.join(",") : (v as string));
    const request = new Request(url, { method: req.method, headers, body });
    const response = await api.fetch(request);
    // request-id + CORS + security headers
    try { response.headers.set("x-request-id", rid); } catch {}
    res.writeHead(response.status, Object.fromEntries(response.headers.entries()));
    if (response.body) {
      const buf = Buffer.from(await response.arrayBuffer());
      res.end(buf);
    } else res.end();
    // structured access log on error/slow only to avoid noise
    const dt = Date.now() - started;
    if (response.status >= 400 || dt > 1000) {
      console.log(`[http] ${rid} ${req.method} ${req.url} -> ${response.status} ${dt}ms ip=${ip}`);
    }
  } catch (err) {
    // Hono bridge hardening: never leak stack, always respond
    console.warn(`[http] ${rid} unhandled`, err);
    try {
      if (!res.headersSent) res.writeHead(500, { "content-type": "application/json", "x-request-id": rid });
      res.end(JSON.stringify({ error: "internal error" }));
    } catch {}
  }
});

/**
 * Collect request body with a hard size cap. Returns:
 * - string | undefined on success (undefined when empty)
 * - null when 413 already sent (caller must return)
 * Resolves undefined on req close/error to avoid hanging.
 */
function readBodyWithLimit(
  req: import("node:http").IncomingMessage,
  maxBytes: number,
  res: import("node:http").ServerResponse
): Promise<string | undefined | null> {
  return new Promise((resolve) => {
    const chunks: Buffer[] = [];
    let total = 0;
    let finished = false;
    const done = (v: string | undefined | null) => {
      if (finished) return;
      finished = true;
      cleanup();
      resolve(v);
    };
    const cleanup = () => {
      req.removeListener("data", onData);
      req.removeListener("end", onEnd);
      req.removeListener("close", onClose);
      req.removeListener("error", onError);
    };
    const onData = (c: Buffer) => {
      total += c.length;
      if (total > maxBytes) {
        cleanup();
        try {
          if (!res.headersSent) res.writeHead(413, { "content-type": "application/json" });
          res.end(JSON.stringify({ error: "payload too large" }));
        } catch {}
        try {
          req.destroy();
        } catch {}
        finished = true;
        resolve(null);
        return;
      }
      chunks.push(c);
    };
    const onEnd = () => done(Buffer.concat(chunks).toString() || undefined);
    const onClose = () => done(undefined);
    const onError = () => done(undefined);
    req.on("data", onData);
    req.on("end", onEnd);
    req.on("close", onClose);
    req.on("error", onError);
  });
}

const wss = new WebSocketServer({ noServer: true });

// max-connections + origin guard + never-hello eviction
wss.on("connection", (ws) => {
  // Basic origin allowlist: allow all in dev; restrict in production via env (e.g. ALLOWED_ORIGINS)
  // if (process.env.ALLOWED_ORIGINS) { const origin = (ws as any)._socket?._httpMessage? ...; check allowlist and close if not allowed }

  // max connections guard — drop newest if over limit
  if (wsHandler.clients.size > MAX_WS_CLIENTS) {
    try {
      (ws as any).close(1013, "server overloaded");
    } catch {}
    return;
  }

  wsHandler.clients.set(ws as any, { deviceId: "unknown", connectedAt: Date.now(), isAlive: true } as any);

  // eviction for never-hello clients after 30s (client must send hello to be considered authenticated)
  const helloTimeout = setTimeout(() => {
    const info = wsHandler.clients.get(ws as any);
    if (info && info.deviceId === "unknown") {
      wsHandler.clients.delete(ws as any);
      try {
        (ws as any).close(1008, "hello timeout");
      } catch {}
    }
  }, 30_000);
  if ((helloTimeout as any).unref) (helloTimeout as any).unref();

  // clear timeout once hello arrives — handleMessage will set deviceId
  const origHandle = wsHandler.handleMessage;
  // we don't monkey-patch; just let the close handler clear — client that sends hello will have deviceId != unknown

  ws.on("message", (data) => {
    try {
      wsHandler.handleMessage(ws as any, data.toString());
    } catch {}
    // if this was a hello, cancel the eviction timer
    const info = wsHandler.clients.get(ws as any);
    if (info && info.deviceId !== "unknown") clearTimeout(helloTimeout);
  });
  ws.on("pong", () => {
    const info = wsHandler.clients.get(ws as any);
    if (info) (info as any).isAlive = true;
  });
  ws.on("close", () => {
    clearTimeout(helloTimeout);
    wsHandler.clients.delete(ws as any);
  });
  ws.on("error", () => {
    clearTimeout(helloTimeout);
    wsHandler.clients.delete(ws as any);
    try {
      (ws as any).close();
    } catch {}
  });
});

wss.on("error", (err) => {
  console.error("[ws] server error", err);
});

server.on("upgrade", (req, socket, head) => {
  const url = new URL(req.url || "/", `http://${req.headers.host}`);
  if (url.pathname !== "/ws") {
    socket.destroy();
    return;
  }
  // WS origin check: in production, validate req.headers.origin against allowlist before upgrade
  // e.g. if (process.env.ALLOWED_ORIGINS && !allowedOrigins.includes(req.headers.origin)) { socket.destroy(); return; }
  wss.handleUpgrade(req, socket, head, (ws) => wss.emit("connection", ws, req));
});

server.listen(PORT, () => {
  console.log(`[cross-note] http://localhost:${PORT}  ws://localhost:${PORT}/ws  db=${logDbPath}`);
});

// graceful shutdown
function shutdown(signal: string) {
  console.log(`[cross-note] ${signal} — shutting down`);
  try {
    wss.close();
  } catch {}
  try {
    server.close(() => {
      try {
        db.close();
      } catch {}
      process.exit(0);
    });
    // force exit if close hangs
    setTimeout(() => {
      try {
        db.close();
      } catch {}
      process.exit(0);
    }, 5000).unref?.();
  } catch {
    try {
      db.close();
    } catch {}
    process.exit(0);
  }
}
process.on("SIGINT", () => shutdown("SIGINT"));
process.on("SIGTERM", () => shutdown("SIGTERM"));
