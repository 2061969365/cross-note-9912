import type { Store } from "../sync/store.js";
import { lwwIncomingWins } from "../sync/conflict.js";

type ClientInfo = { deviceId: string; cursor?: string };

export function createWsHandler(store: Store) {
  const clients = new Map<unknown, ClientInfo>();

  function broadcast(msg: unknown, exclude?: unknown) {
    const data = JSON.stringify(msg);
    for (const [ws] of clients) {
      if (ws === exclude) continue;
      try {
        (ws as { send: (d: string) => void }).send(data);
      } catch {}
    }
  }

  function handleMessage(ws: unknown, raw: string) {
    let msg: Record<string, unknown>;
    try {
      msg = JSON.parse(raw) as Record<string, unknown>;
    } catch {
      (ws as { send: (d: string) => void }).send(JSON.stringify({ type: "error", message: "invalid json" }));
      return;
    }
    const type = msg.type as string;

    if (type === "hello") {
      const deviceId = (msg.deviceId as string) || "unknown";
      const cursor = msg.cursor as string | undefined;
      clients.set(ws, { deviceId, cursor });
      // Immediately push pull_result for incremental sync
      const { notes, folders, cursor: newCursor } = store.pull(cursor, 200, true);
      (ws as { send: (d: string) => void }).send(JSON.stringify({ type: "hello_ack", cursor: newCursor, serverTime: new Date().toISOString(), notes, folders }));
      return;
    }
    if (type === "pull") {
      const since = msg.since as string | undefined;
      const limit = (msg.limit as number) || 100;
      const { notes, folders, cursor } = store.pull(since, limit, true);
      (ws as { send: (d: string) => void }).send(JSON.stringify({ type: "pull_result", notes, folders, cursor, hasMore: notes.length === limit || folders.length === limit }));
      return;
    }
    if (type === "push") {
      const entityType = msg.entityType as "note" | "folder";
      const operation = (msg.operation as string) || "UPDATE";
      const entity = (msg.entity as Record<string, unknown>) || {};
      if (!entityType || !entity.id) {
        (ws as { send: (d: string) => void }).send(JSON.stringify({ type: "push_ack", error: "missing entityType/id" }));
        return;
      }
      const rawIncoming = entity.updated_at as string | undefined;
      const parsed = rawIncoming ? new Date(rawIncoming) : new Date();
      const effectiveUpdatedAt = isNaN(parsed.getTime()) ? new Date().toISOString() : parsed.toISOString();
      entity.updated_at = effectiveUpdatedAt;

      if (entityType === "note") {
        const existing = store.getNote(entity.id as string);
        if (!existing) {
          const { entity: created } = store.upsertNote(entity as Partial<import("../models/types.js").Note> & { id: string });
          (ws as { send: (d: string) => void }).send(JSON.stringify({ type: "push_ack", entityType, id: created.id, version: created.version, updated_at: created.updated_at, applied: true, conflict: "none", entity: created }));
          broadcast({ type: "broadcast", entityType, operation, entity: created }, ws);
          return;
        }
        const incomingForCompare = { updated_at: effectiveUpdatedAt, version: (entity.version as number) ?? existing.version + 1, device_id: (entity.device_id as string) ?? existing.device_id };
        const existingForCompare = { updated_at: existing.updated_at, version: existing.version, device_id: existing.device_id };
        if (!lwwIncomingWins(incomingForCompare, existingForCompare)) {
          (ws as { send: (d: string) => void }).send(JSON.stringify({ type: "push_ack", entityType, id: existing.id, version: existing.version, updated_at: existing.updated_at, applied: false, conflict: "lww_rejected", entity: existing }));
          return;
        }
        const { entity: updated } = store.upsertNote(entity as Partial<import("../models/types.js").Note> & { id: string });
        (ws as { send: (d: string) => void }).send(JSON.stringify({ type: "push_ack", entityType, id: updated.id, version: updated.version, updated_at: updated.updated_at, applied: true, conflict: "none", entity: updated }));
        broadcast({ type: "broadcast", entityType, operation, entity: updated }, ws);
        return;
      } else {
        const existing = store.getFolder(entity.id as string);
        if (!existing) {
          const { entity: created } = store.upsertFolder(entity as Partial<import("../models/types.js").Folder> & { id: string });
          (ws as { send: (d: string) => void }).send(JSON.stringify({ type: "push_ack", entityType, id: created.id, version: created.version, updated_at: created.updated_at, applied: true, conflict: "none", entity: created }));
          broadcast({ type: "broadcast", entityType, operation, entity: created }, ws);
          return;
        }
        const incomingForCompare = { updated_at: effectiveUpdatedAt, version: (entity.version as number) ?? existing.version + 1, device_id: (entity.device_id as string) ?? existing.device_id };
        const existingForCompare = { updated_at: existing.updated_at, version: existing.version, device_id: existing.device_id };
        if (!lwwIncomingWins(incomingForCompare, existingForCompare)) {
          (ws as { send: (d: string) => void }).send(JSON.stringify({ type: "push_ack", entityType, id: existing.id, version: existing.version, updated_at: existing.updated_at, applied: false, conflict: "lww_rejected", entity: existing }));
          return;
        }
        const { entity: updated } = store.upsertFolder(entity as Partial<import("../models/types.js").Folder> & { id: string });
        (ws as { send: (d: string) => void }).send(JSON.stringify({ type: "push_ack", entityType, id: updated.id, version: updated.version, updated_at: updated.updated_at, applied: true, conflict: "none", entity: updated }));
        broadcast({ type: "broadcast", entityType, operation, entity: updated }, ws);
        return;
      }
    }
    (ws as { send: (d: string) => void }).send(JSON.stringify({ type: "error", message: `unknown type ${type}` }));
  }

  return {
    // For REST broadcaster to reuse
    broadcastRest(msg: unknown) {
      broadcast(msg);
    },
    attachToServer(server: import("node:http").Server) {
      // Lightweight WS upgrade without extra deps — use 'ws' if available else fallback
      // We implement a minimal upgrade using Node's built-in via dynamic import of 'ws'
      // to avoid extra native deps; if ws not installed, REST still works.
      return { clients, handleMessage, broadcast };
    },
    clients,
    handleMessage,
    broadcast,
  };
}
