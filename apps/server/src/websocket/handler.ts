import { z } from "zod";
import type { Store } from "../sync/store.js";
import { lwwIncomingWins } from "../sync/conflict.js";

type ClientInfo = { deviceId: string; cursor?: string; connectedAt: number; isAlive: boolean };

// ---------- helpers ----------
function sanitizeDeviceId(d?: string): string {
  if (typeof d !== "string") return "unknown";
  const s = d.slice(0, 64).replace(/[^a-zA-Z0-9._-]/g, "");
  return s || "unknown";
}

function getDeviceId(ws: any, clients: Map<any, ClientInfo>): string {
  return clients.get(ws)?.deviceId ?? "unknown";
}

function normalizeTime(s?: string, fallback?: string): string {
  const fb = fallback ?? new Date().toISOString();
  if (!s) return fb;
  const d = new Date(s);
  return isNaN(d.getTime()) ? fb : d.toISOString();
}

function isBusyError(e: unknown): boolean {
  const msg = e instanceof Error ? e.message : String(e);
  return /SQLITE_BUSY|database is locked|busy/i.test(msg);
}

// ---------- zod schemas for WS messages ----------
const helloSchema = z.object({
  type: z.literal("hello"),
  deviceId: z.string().max(64).optional(),
  device_id: z.string().max(64).optional(),
  cursor: z.string().optional(),
  since: z.string().optional(),
});

const pullSchema = z.object({
  type: z.literal("pull"),
  since: z.string().optional(),
  cursor: z.string().optional(),
  limit: z.coerce.number().int().min(1).max(500).optional(),
  includeDeleted: z.union([z.boolean(), z.enum(["0", "1"])]).optional(),
});

const entitySchema = z
  .object({
    id: z.string().uuid(),
    title: z.string().max(500).optional(),
    name: z.string().max(200).optional(),
    content: z.string().max(100000).optional(),
    folder_id: z.string().uuid().nullable().optional(),
    created_at: z.string().datetime().optional(),
    updated_at: z.string().datetime().optional(),
    deleted_at: z.string().datetime().nullable().optional(),
    version: z.number().int().optional(),
    device_id: z.string().max(64).optional(),
  })
  .passthrough();

const pushSchema = z.object({
  type: z.literal("push"),
  entityType: z.enum(["note", "folder"]),
  operation: z.enum(["CREATE", "UPDATE", "DELETE"]).optional().default("UPDATE"),
  entity: entitySchema,
});

const wsMessageSchema = z.discriminatedUnion("type", [helloSchema, pullSchema, pushSchema]);

export function createWsHandler(store: Store) {
  const clients = new Map<any, ClientInfo>();

  function broadcast(msg: unknown, exclude?: unknown) {
    const data = JSON.stringify(msg);
    for (const [ws] of clients) {
      if (exclude !== undefined && ws === exclude) continue;
      // readyState check: 1 === OPEN
      const ready = (ws as any).readyState;
      if (ready !== 1) {
        // zombie / closing socket — clean up
        clients.delete(ws);
        try {
          (ws as any).close();
        } catch {}
        continue;
      }
      try {
        (ws as { send: (d: string) => void }).send(data);
      } catch {
        clients.delete(ws);
        try {
          (ws as any).close();
        } catch {}
      }
    }
  }

  // periodic ping/pong to terminate dead sockets (zombie cleanup)
  const pingInterval = setInterval(() => {
    for (const [ws, info] of clients) {
      if (info.isAlive === false) {
        clients.delete(ws);
        try {
          (ws as any).terminate?.();
        } catch {}
        try {
          (ws as any).close();
        } catch {}
        continue;
      }
      info.isAlive = false;
      try {
        // ws.ping() is available on 'ws' library sockets
        if (typeof (ws as any).ping === "function") (ws as any).ping();
        else if (typeof (ws as any).send === "function") (ws as any).send(JSON.stringify({ type: "ping" }));
      } catch {}
    }
  }, 30_000);
  // allow process to exit even if interval is still active
  if ((pingInterval as any).unref) (pingInterval as any).unref();

  function handleMessage(ws: any, raw: string) {
    let json: unknown;
    try {
      json = JSON.parse(raw);
    } catch {
      try {
        ws.send(JSON.stringify({ type: "error", message: "invalid message" }));
      } catch {}
      return;
    }

    const parsed = wsMessageSchema.safeParse(json);
    if (!parsed.success) {
      // For raw JSON that parsed but failed validation, send generic invalid message
      // Keep compat: if it was valid JSON but unknown type, the discriminated union will fail — treat as invalid message
      try {
        ws.send(JSON.stringify({ type: "error", message: "invalid message" }));
      } catch {}
      return;
    }

    const msg: any = parsed.data;

    // common pong handler: any message acts as liveness if client replied to ping
    const clientInfo = clients.get(ws);
    if (clientInfo) clientInfo.isAlive = true;

    if (msg.type === "hello") {
      const rawDeviceId = (msg.deviceId ?? msg.device_id) as string | undefined;
      const deviceId = sanitizeDeviceId(rawDeviceId);
      const cursor = (msg.cursor ?? msg.since) as string | undefined;
      const now = Date.now();
      clients.set(ws, { deviceId, cursor, connectedAt: now, isAlive: true });
      // attach pong listener once per socket if available
      if (typeof ws.on === "function" && !(ws as any).__pongAttached) {
        try {
          ws.on("pong", () => {
            const ci = clients.get(ws);
            if (ci) ci.isAlive = true;
          });
          (ws as any).__pongAttached = true;
        } catch {}
      }
      try {
        const { notes, folders, cursor: newCursor } = store.pull(cursor, 200, true);
        ws.send(JSON.stringify({ type: "hello_ack", cursor: newCursor, serverTime: new Date().toISOString(), notes, folders }));
      } catch (e) {
        if (isBusyError(e)) {
          try {
            ws.send(JSON.stringify({ type: "error", message: "busy, retry" }));
          } catch {}
        } else {
          try {
            ws.send(JSON.stringify({ type: "error", message: "internal error" }));
          } catch {}
        }
      }
      return;
    }

    if (msg.type === "pull") {
      const since = (msg.since ?? msg.cursor) as string | undefined;
      const limit = (msg.limit as number) ?? 100;
      const includeDeleted = msg.includeDeleted === true || msg.includeDeleted === "1" ? true : msg.includeDeleted === false || msg.includeDeleted === "0" ? false : true;
      try {
        const { notes, folders, cursor } = store.pull(since, limit, includeDeleted);
        const hasMore = notes.length === limit || folders.length === limit;
        ws.send(JSON.stringify({ type: "pull_result", notes, folders, cursor, hasMore, serverTime: new Date().toISOString() }));
      } catch (e) {
        if (isBusyError(e)) {
          try {
            ws.send(JSON.stringify({ type: "error", message: "busy, retry" }));
          } catch {}
        } else {
          try {
            ws.send(JSON.stringify({ type: "error", message: "internal error" }));
          } catch {}
        }
      }
      return;
    }

    if (msg.type === "push") {
      const entityType = msg.entityType as "note" | "folder";
      const operation = (msg.operation as string) || "UPDATE";
      const entity = (msg.entity as Record<string, unknown>) || {};
      if (!entityType || !entity.id) {
        try {
          ws.send(JSON.stringify({ type: "push_ack", error: "missing entityType/id" }));
        } catch {}
        return;
      }

      const serverTime = new Date().toISOString();
      const incomingUpdatedAt = normalizeTime(entity.updated_at as string | undefined, serverTime);
      // sanitize device_id and use serverTime as authoritative stored updated_at
      const sanitizedDeviceId = sanitizeDeviceId(entity.device_id as string | undefined);
      const incomingVersion = typeof entity.version === "number" ? (entity.version as number) : 0;

      // stored entity uses serverTime (prevents fast-clock wins); LWW comparison uses incomingUpdatedAt
      const toStore: Record<string, unknown> = { ...entity, device_id: sanitizedDeviceId, updated_at: serverTime };

      try {
        if (entityType === "note") {
          const existing = store.getNote(entity.id as string);
          if (!existing) {
            const { entity: created } = store.upsertNote(toStore as Partial<import("../models/types.js").Note> & { id: string });
            ws.send(JSON.stringify({ type: "push_ack", entityType, id: created.id, version: created.version, updated_at: created.updated_at, applied: true, conflict: "none", entity: created }));
            broadcast({ type: "broadcast", entityType, operation, entity: created }, ws);
            return;
          }
          const incomingForCompare = { updated_at: incomingUpdatedAt, version: incomingVersion, device_id: sanitizedDeviceId };
          const existingForCompare = { updated_at: existing.updated_at ?? serverTime, version: existing.version ?? 0, device_id: existing.device_id ?? "unknown" };
          if (!lwwIncomingWins(incomingForCompare, existingForCompare)) {
            ws.send(JSON.stringify({ type: "push_ack", entityType, id: existing.id, version: existing.version, updated_at: existing.updated_at, applied: false, conflict: "lww_rejected", entity: existing }));
            return;
          }
          const { entity: updated } = store.upsertNote(toStore as Partial<import("../models/types.js").Note> & { id: string });
          ws.send(JSON.stringify({ type: "push_ack", entityType, id: updated.id, version: updated.version, updated_at: updated.updated_at, applied: true, conflict: "none", entity: updated }));
          broadcast({ type: "broadcast", entityType, operation, entity: updated }, ws);
          return;
        } else {
          const existing = store.getFolder(entity.id as string);
          if (!existing) {
            const { entity: created } = store.upsertFolder(toStore as Partial<import("../models/types.js").Folder> & { id: string });
            ws.send(JSON.stringify({ type: "push_ack", entityType, id: created.id, version: created.version, updated_at: created.updated_at, applied: true, conflict: "none", entity: created }));
            broadcast({ type: "broadcast", entityType, operation, entity: created }, ws);
            return;
          }
          const incomingForCompare = { updated_at: incomingUpdatedAt, version: incomingVersion, device_id: sanitizedDeviceId };
          const existingForCompare = { updated_at: existing.updated_at ?? serverTime, version: existing.version ?? 0, device_id: existing.device_id ?? "unknown" };
          if (!lwwIncomingWins(incomingForCompare, existingForCompare)) {
            ws.send(JSON.stringify({ type: "push_ack", entityType, id: existing.id, version: existing.version, updated_at: existing.updated_at, applied: false, conflict: "lww_rejected", entity: existing }));
            return;
          }
          const { entity: updated } = store.upsertFolder(toStore as Partial<import("../models/types.js").Folder> & { id: string });
          ws.send(JSON.stringify({ type: "push_ack", entityType, id: updated.id, version: updated.version, updated_at: updated.updated_at, applied: true, conflict: "none", entity: updated }));
          broadcast({ type: "broadcast", entityType, operation, entity: updated }, ws);
          return;
        }
      } catch (e) {
        if (isBusyError(e)) {
          try {
            ws.send(JSON.stringify({ type: "error", message: "busy, retry" }));
          } catch {}
        } else {
          try {
            ws.send(JSON.stringify({ type: "error", message: "internal error" }));
          } catch {}
        }
        return;
      }
    }

    try {
      ws.send(JSON.stringify({ type: "error", message: `unknown type ${(msg as any).type}` }));
    } catch {}
  }

  return {
    // For REST broadcaster to reuse — already excludes sender when called from WS push
    broadcastRest(msg: unknown) {
      broadcast(msg);
    },
    attachToServer(_server: import("node:http").Server) {
      return { clients, handleMessage, broadcast };
    },
    clients: clients as Map<any, ClientInfo>,
    handleMessage,
    broadcast,
    // expose for graceful shutdown / cleanup
    _pingInterval: pingInterval,
    getDeviceId: (ws: any) => getDeviceId(ws, clients),
  };
}
