import { Hono } from "hono";
import { cors } from "hono/cors";
import { z } from "zod";
import type { Store } from "../sync/store.js";
import { lwwIncomingWins } from "../sync/conflict.js";

const uuid = z.string().uuid();
const noteSchema = z.object({
  id: uuid,
  folder_id: z.string().nullable().optional(),
  title: z.string().optional(),
  content: z.string().optional(),
  created_at: z.string().optional(),
  updated_at: z.string().optional(),
  deleted_at: z.string().nullable().optional(),
  version: z.number().int().optional(),
  device_id: z.string().optional(),
});
const folderSchema = z.object({
  id: uuid,
  name: z.string().optional(),
  created_at: z.string().optional(),
  updated_at: z.string().optional(),
  deleted_at: z.string().nullable().optional(),
  version: z.number().int().optional(),
  device_id: z.string().optional(),
});

export function createApi(store: Store, opts?: { broadcaster?: (msg: unknown, exclude?: Set<unknown>) => void }) {
  const app = new Hono();
  app.use("/*", cors());

  app.get("/api/health", (c) => c.json({ ok: true, time: new Date().toISOString() }));

  // Pull
  app.get("/api/sync/pull", (c) => {
    const since = c.req.query("since") || undefined;
    const limit = Number(c.req.query("limit") || 100);
    const includeDeleted = c.req.query("includeDeleted") !== "0";
    const { notes, folders, cursor } = store.pull(since, limit, includeDeleted);
    const hasMore = notes.length === limit || folders.length === limit;
    return c.json({ notes, folders, cursor, hasMore, serverTime: new Date().toISOString() });
  });

  // Push (REST fallback)
  app.post("/api/sync/push", async (c) => {
    const body = await c.req.json().catch(() => null);
    const parsed = z.object({ entityType: z.enum(["note", "folder"]), operation: z.enum(["CREATE", "UPDATE", "DELETE"]), entity: z.record(z.unknown()) }).safeParse(body);
    if (!parsed.success) return c.json({ error: "invalid body", details: parsed.error.flatten() }, 400);
    const { entityType, operation, entity } = parsed.data as { entityType: "note" | "folder"; operation: "CREATE" | "UPDATE" | "DELETE"; entity: Record<string, unknown> };
    const result = applyPush(store, entityType, operation, entity);
    if (result.broadcast) opts?.broadcaster?.(result.broadcast);
    return c.json(result.response);
  });

  // Convenience CRUD — all go through same LWW path
  app.get("/api/notes", (c) => {
    const since = c.req.query("since") || undefined;
    const limit = Number(c.req.query("limit") || 100);
    const includeDeleted = c.req.query("includeDeleted") !== "0";
    return c.json({ notes: store.listNotes(since, limit, includeDeleted) });
  });
  app.get("/api/folders", (c) => {
    const since = c.req.query("since") || undefined;
    const limit = Number(c.req.query("limit") || 100);
    const includeDeleted = c.req.query("includeDeleted") !== "0";
    return c.json({ folders: store.listFolders(since, limit, includeDeleted) });
  });
  app.post("/api/notes", async (c) => {
    const body = await c.req.json().catch(() => ({}));
    const p = noteSchema.safeParse(body);
    if (!p.success) return c.json({ error: p.error.flatten() }, 400);
    const r = applyPush(store, "note", "CREATE", p.data as Record<string, unknown>);
    if (r.broadcast) opts?.broadcaster?.(r.broadcast);
    return c.json(r.response.entity, 201);
  });
  app.put("/api/notes/:id", async (c) => {
    const id = c.req.param("id");
    const body = (await c.req.json().catch(() => ({}))) as Record<string, unknown>;
    body.id = id;
    const p = noteSchema.safeParse(body);
    if (!p.success) return c.json({ error: p.error.flatten() }, 400);
    const r = applyPush(store, "note", "UPDATE", p.data as Record<string, unknown>);
    if (r.broadcast) opts?.broadcaster?.(r.broadcast);
    return c.json(r.response.entity);
  });
  app.delete("/api/notes/:id", async (c) => {
    const id = c.req.param("id");
    const deviceId = c.req.query("device_id") || "";
    const entity = { id, deleted_at: new Date().toISOString(), updated_at: new Date().toISOString(), device_id: deviceId };
    const r = applyPush(store, "note", "DELETE", entity);
    if (r.broadcast) opts?.broadcaster?.(r.broadcast);
    return c.json(r.response.entity);
  });
  // folders CRUD
  app.post("/api/folders", async (c) => {
    const body = await c.req.json().catch(() => ({}));
    const p = folderSchema.safeParse(body);
    if (!p.success) return c.json({ error: p.error.flatten() }, 400);
    const r = applyPush(store, "folder", "CREATE", p.data as Record<string, unknown>);
    if (r.broadcast) opts?.broadcaster?.(r.broadcast);
    return c.json(r.response.entity, 201);
  });
  app.put("/api/folders/:id", async (c) => {
    const id = c.req.param("id");
    const body = (await c.req.json().catch(() => ({}))) as Record<string, unknown>;
    body.id = id;
    const p = folderSchema.safeParse(body);
    if (!p.success) return c.json({ error: p.error.flatten() }, 400);
    const r = applyPush(store, "folder", "UPDATE", p.data as Record<string, unknown>);
    if (r.broadcast) opts?.broadcaster?.(r.broadcast);
    return c.json(r.response.entity);
  });
  app.delete("/api/folders/:id", async (c) => {
    const id = c.req.param("id");
    const deviceId = c.req.query("device_id") || "";
    const entity = { id, deleted_at: new Date().toISOString(), updated_at: new Date().toISOString(), device_id: deviceId };
    const r = applyPush(store, "folder", "DELETE", entity);
    if (r.broadcast) opts?.broadcaster?.(r.broadcast);
    return c.json(r.response.entity);
  });

  return app;
}

function normalizeTime(s: string | undefined): string {
  if (!s) return new Date().toISOString();
  const d = new Date(s);
  return isNaN(d.getTime()) ? new Date().toISOString() : d.toISOString();
}

function applyPush(store: Store, entityType: "note" | "folder", operation: string, entity: Record<string, unknown>) {
  const id = entity.id as string;
  const incomingUpdatedAt = normalizeTime(entity.updated_at as string | undefined);
  const incomingVersion = (entity.version as number) ?? 0;
  const incomingDeviceId = (entity.device_id as string) ?? "";
  // effective is the normalized incoming time; server does NOT bump old timestamps to now,
  // otherwise every old write would incorrectly win LWW. New writes carry a newer timestamp
  // from the client (or server-generated time when missing) and will naturally win.
  const effectiveUpdatedAt = incomingUpdatedAt;

  if (entityType === "note") {
    const existing = store.getNote(id);
    if (!existing) {
      const { entity: created } = store.upsertNote({ ...(entity as Record<string, unknown>), updated_at: effectiveUpdatedAt } as Partial<import("../models/types.js").Note> & { id: string });
      return {
        response: { entity: created, conflict: "none", applied: true },
        broadcast: { type: "broadcast", entityType: "note", operation, entity: created },
      };
    }
    const incomingForCompare = { updated_at: effectiveUpdatedAt, version: incomingVersion || (existing.version + 1), device_id: incomingDeviceId || existing.device_id };
    const existingForCompare = { updated_at: existing.updated_at, version: existing.version, device_id: existing.device_id };
    if (!lwwIncomingWins(incomingForCompare, existingForCompare)) {
      return { response: { entity: existing, conflict: "lww_rejected", applied: false }, broadcast: null };
    }
    const { entity: updated } = store.upsertNote({ ...(entity as Record<string, unknown>), updated_at: effectiveUpdatedAt } as Partial<import("../models/types.js").Note> & { id: string });
    return {
      response: { entity: updated, conflict: "none", applied: true },
      broadcast: { type: "broadcast", entityType: "note", operation, entity: updated },
    };
  } else {
    const existing = store.getFolder(id);
    if (!existing) {
      const { entity: created } = store.upsertFolder({ ...(entity as Record<string, unknown>), updated_at: effectiveUpdatedAt } as Partial<import("../models/types.js").Folder> & { id: string });
      return {
        response: { entity: created, conflict: "none", applied: true },
        broadcast: { type: "broadcast", entityType: "folder", operation, entity: created },
      };
    }
    const incomingForCompare = { updated_at: effectiveUpdatedAt, version: incomingVersion || (existing.version + 1), device_id: incomingDeviceId || existing.device_id };
    const existingForCompare = { updated_at: existing.updated_at, version: existing.version, device_id: existing.device_id };
    if (!lwwIncomingWins(incomingForCompare, existingForCompare)) {
      return { response: { entity: existing, conflict: "lww_rejected", applied: false }, broadcast: null };
    }
    const { entity: updated } = store.upsertFolder({ ...(entity as Record<string, unknown>), updated_at: effectiveUpdatedAt } as Partial<import("../models/types.js").Folder> & { id: string });
    return {
      response: { entity: updated, conflict: "none", applied: true },
      broadcast: { type: "broadcast", entityType: "folder", operation, entity: updated },
    };
  }
}
