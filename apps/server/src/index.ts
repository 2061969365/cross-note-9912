import { createServer } from "node:http";
import { WebSocketServer } from "ws";
import { openDb, migrate } from "./database/db.js";
import { createSqliteStore } from "./sync/store.js";
import { createApi } from "./api/routes.js";
import { createWsHandler } from "./websocket/handler.js";

const PORT = Number(process.env.PORT || 8787);
const db = openDb();
migrate(db);
const store = createSqliteStore(db);
const wsHandler = createWsHandler(store);

// Hono app
const api = createApi(store, { broadcaster: (msg) => wsHandler.broadcast(msg) });

// Node http server that delegates to Hono fetch and handles WS upgrade
const server = createServer(async (req, res) => {
  // Let Hono handle via fetch
  const url = `http://${req.headers.host}${req.url}`;
  const headers = new Headers();
  for (const [k, v] of Object.entries(req.headers)) if (v) headers.set(k, Array.isArray(v) ? v.join(",") : v);
  const body = req.method !== "GET" && req.method !== "HEAD" ? await readBody(req) : undefined;
  const request = new Request(url, { method: req.method, headers, body });
  const response = await api.fetch(request);
  res.writeHead(response.status, Object.fromEntries(response.headers.entries()));
  if (response.body) {
    const buf = Buffer.from(await response.arrayBuffer());
    res.end(buf);
  } else res.end();
});

function readBody(req: import("node:http").IncomingMessage): Promise<string | undefined> {
  return new Promise((resolve) => {
    const chunks: Buffer[] = [];
    req.on("data", (c) => chunks.push(c));
    req.on("end", () => resolve(Buffer.concat(chunks).toString() || undefined));
    req.on("error", () => resolve(undefined));
  });
}

const wss = new WebSocketServer({ noServer: true });
wss.on("connection", (ws) => {
  wsHandler.clients.set(ws as unknown, { deviceId: "unknown" });
  ws.on("message", (data) => wsHandler.handleMessage(ws as unknown, data.toString()));
  ws.on("close", () => wsHandler.clients.delete(ws as unknown));
  ws.on("error", () => wsHandler.clients.delete(ws as unknown));
});

server.on("upgrade", (req, socket, head) => {
  const url = new URL(req.url || "/", `http://${req.headers.host}`);
  if (url.pathname !== "/ws") {
    socket.destroy();
    return;
  }
  wss.handleUpgrade(req, socket, head, (ws) => wss.emit("connection", ws, req));
});

server.listen(PORT, () => {
  console.log(`[cross-note] http://localhost:${PORT}  ws://localhost:${PORT}/ws  db=${process.env.DB_PATH || "data/cross_note.db"}`);
});
