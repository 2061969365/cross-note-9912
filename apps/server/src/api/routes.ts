import { Hono } from "hono";
import { cors } from "hono/cors";
import { z } from "zod";
import type { Store } from "../sync/store.js";
import { lwwIncomingWins } from "../sync/conflict.js";

// ---------- shared helpers ----------
function sanitizeDeviceId(d?: string): string {
  if (typeof d !== "string") return "unknown";
  const s = d.slice(0, 64).replace(/[^a-zA-Z0-9._-]/g, "");
  return s || "unknown";
}

function normalizeTime(s?: string, fallback?: string): string {
  const serverFallback = fallback ?? new Date().toISOString();
  if (!s) return serverFallback;
  const d = new Date(s);
  return isNaN(d.getTime()) ? serverFallback : d.toISOString();
}

// wrapper that normalizes both sides and uses nullish coalescing consistently
function lwwIncomingWinsNormalized(
  incoming: { updated_at?: string; version?: unknown; device_id?: unknown },
  existing: { updated_at: string; version: number; device_id: string },
  fallbackTime: string
): boolean {
  const inc = {
    updated_at: normalizeTime(incoming.updated_at as string | undefined, fallbackTime),
    version: typeof incoming.version === "number" ? (incoming.version as number) : 0,
    device_id: sanitizeDeviceId(incoming.device_id as string | undefined) ?? "unknown",
  };
  const ex = {
    updated_at: existing.updated_at ?? fallbackTime,
    version: existing.version ?? 0,
    device_id: existing.device_id ?? "unknown",
  };
  return lwwIncomingWins(inc, ex);
}

// ---------- validation schemas ----------
const uuid = z.string().uuid();
const pullQuerySchema = z.object({
  // since may be a plain ISO datetime (legacy) or composite cursor `time|id`
  since: z
    .string()
    .refine(
      (v) => {
        if (!v || v.length === 0) return true;
        const pipe = v.indexOf("|");
        const timePart = pipe === -1 ? v : v.slice(0, pipe);
        const d = new Date(timePart);
        return !isNaN(d.getTime());
      },
      { message: "Invalid cursor datetime" },
    )
    .optional()
    .or(z.string().length(0).optional()),
  limit: z.coerce.number().int().min(1).max(500).default(100),
  includeDeleted: z.enum(["0", "1"]).optional().default("0"),
});

const noteSchema = z.object({
  id: uuid,
  folder_id: z.string().uuid().nullable().optional().or(z.string().length(0).optional()),
  title: z.string().max(500).optional(),
  content: z.string().max(100000).optional(),
  created_at: z.string().datetime().optional(),
  updated_at: z.string().datetime().optional(),
  deleted_at: z.string().datetime().nullable().optional(),
  version: z.number().int().optional(),
  device_id: z.string().max(64).optional(),
});

const folderSchema = z.object({
  id: uuid,
  name: z.string().max(200).optional(),
  created_at: z.string().datetime().optional(),
  updated_at: z.string().datetime().optional(),
  deleted_at: z.string().datetime().nullable().optional(),
  version: z.number().int().optional(),
  device_id: z.string().max(64).optional(),
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

const pushBodySchema = z.object({
  entityType: z.enum(["note", "folder"]),
  operation: z.enum(["CREATE", "UPDATE", "DELETE"]),
  entity: entitySchema,
});

export function createApi(store: Store, opts?: { broadcaster?: (msg: unknown, exclude?: Set<unknown>) => void }) {
  const app = new Hono();
  // CORS: allow any origin by default; restrict in production via allowlist/env
  app.use(
    "/*",
    cors({
      origin: (origin) => origin ?? "*",
      allowMethods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
      allowHeaders: ["content-type", "authorization"],
      credentials: false,
    })
  );

  app.get("/api/health", (c) => c.json({ ok: true, time: new Date().toISOString() }));

  // Pull
  app.get("/api/sync/pull", (c) => {
    const parsed = pullQuerySchema.safeParse({
      since: c.req.query("since") || undefined,
      limit: c.req.query("limit"),
      includeDeleted: c.req.query("includeDeleted"),
    });
    if (!parsed.success) return c.json({ error: "invalid query", issues: parsed.error.issues }, 400);
    const { since, limit, includeDeleted } = parsed.data;
    const include = includeDeleted === "1";
    const normalizedSince = since && since.length > 0 ? since : undefined;
    const { notes, folders, cursor } = store.pull(normalizedSince, limit, include);
    // hasMore correctly derived from whether either collection hit the limit
    const hasMore = notes.length === limit || folders.length === limit;
    return c.json({ notes, folders, cursor, hasMore, serverTime: new Date().toISOString() });
  });

  // Push (REST fallback)
  app.post("/api/sync/push", async (c) => {
    const body = await c.req.json().catch(() => null);
    const parsed = pushBodySchema.safeParse(body);
    if (!parsed.success) return c.json({ error: "invalid body", details: parsed.error.flatten() }, 400);
    const { entityType, operation, entity } = parsed.data as {
      entityType: "note" | "folder";
      operation: "CREATE" | "UPDATE" | "DELETE";
      entity: Record<string, unknown>;
    };
    const result = applyPush(store, entityType, operation, entity);
    // server broadcast excludes sender via WS handler; REST has no sender socket to exclude
    if (result.broadcast) opts?.broadcaster?.(result.broadcast);
    return c.json(result.response);
  });

  // Convenience CRUD — all go through same LWW path
  app.get("/api/notes", (c) => {
    const parsed = pullQuerySchema.safeParse({
      since: c.req.query("since") || undefined,
      limit: c.req.query("limit"),
      includeDeleted: c.req.query("includeDeleted"),
    });
    if (!parsed.success) return c.json({ error: "invalid query", issues: parsed.error.issues }, 400);
    const { since, limit, includeDeleted } = parsed.data;
    const include = includeDeleted === "1";
    const normalizedSince = since && since.length > 0 ? since : undefined;
    return c.json({ notes: store.listNotes(normalizedSince, limit, include) });
  });
  app.get("/api/folders", (c) => {
    const parsed = pullQuerySchema.safeParse({
      since: c.req.query("since") || undefined,
      limit: c.req.query("limit"),
      includeDeleted: c.req.query("includeDeleted"),
    });
    if (!parsed.success) return c.json({ error: "invalid query", issues: parsed.error.issues }, 400);
    const { since, limit, includeDeleted } = parsed.data;
    const include = includeDeleted === "1";
    const normalizedSince = since && since.length > 0 ? since : undefined;
    return c.json({ folders: store.listFolders(normalizedSince, limit, include) });
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
    const parsedId = z.string().uuid().safeParse(c.req.param("id"));
    if (!parsedId.success) return c.json({ error: "invalid id" }, 400);
    const id = parsedId.data;
    const body = (await c.req.json().catch(() => ({}))) as Record<string, unknown>;
    body.id = id;
    const p = noteSchema.safeParse(body);
    if (!p.success) return c.json({ error: p.error.flatten() }, 400);
    const r = applyPush(store, "note", "UPDATE", p.data as Record<string, unknown>);
    if (r.broadcast) opts?.broadcaster?.(r.broadcast);
    return c.json(r.response.entity);
  });
  app.delete("/api/notes/:id", async (c) => {
    const parsedId = z.string().uuid().safeParse(c.req.param("id"));
    if (!parsedId.success) return c.json({ error: "invalid id" }, 400);
    const id = parsedId.data;
    const deviceId = sanitizeDeviceId(c.req.query("device_id") || undefined);
    const serverTime = new Date().toISOString();
    const entity = { id, deleted_at: serverTime, updated_at: serverTime, device_id: deviceId };
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
    const parsedId = z.string().uuid().safeParse(c.req.param("id"));
    if (!parsedId.success) return c.json({ error: "invalid id" }, 400);
    const id = parsedId.data;
    const body = (await c.req.json().catch(() => ({}))) as Record<string, unknown>;
    body.id = id;
    const p = folderSchema.safeParse(body);
    if (!p.success) return c.json({ error: p.error.flatten() }, 400);
    const r = applyPush(store, "folder", "UPDATE", p.data as Record<string, unknown>);
    if (r.broadcast) opts?.broadcaster?.(r.broadcast);
    return c.json(r.response.entity);
  });
  app.delete("/api/folders/:id", async (c) => {
    const parsedId = z.string().uuid().safeParse(c.req.param("id"));
    if (!parsedId.success) return c.json({ error: "invalid id" }, 400);
    const id = parsedId.data;
    const deviceId = sanitizeDeviceId(c.req.query("device_id") || undefined);
    const serverTime = new Date().toISOString();
    const entity = { id, deleted_at: serverTime, updated_at: serverTime, device_id: deviceId };
    const r = applyPush(store, "folder", "DELETE", entity);
    if (r.broadcast) opts?.broadcaster?.(r.broadcast);
    return c.json(r.response.entity);
  });

  return app;
}

function applyPush(store: Store, entityType: "note" | "folder", operation: string, entity: Record<string, unknown>) {
  const id = entity.id as string;
  const serverTime = new Date().toISOString();
  // incomingUpdatedAt is used for LWW comparison only; effectiveUpdatedAt (serverTime) is authoritative for storage
  const incomingUpdatedAt = normalizeTime(entity.updated_at as string | undefined, serverTime);
  const incomingVersion = typeof entity.version === "number" ? (entity.version as number) : 0;
  const incomingDeviceId = sanitizeDeviceId(entity.device_id as string | undefined);
  const effectiveUpdatedAt = serverTime; // server receive time is authoritative

  // sanitize device_id in entity before persisting
  const sanitizedEntity = { ...entity, device_id: incomingDeviceId, updated_at: effectiveUpdatedAt } as Record<string, unknown>;

  if (entityType === "note") {
    const existing = store.getNote(id);
    if (!existing) {
      const { entity: created } = store.upsertNote(sanitizedEntity as Partial<import("../models/types.js").Note> & { id: string });
      return {
        response: { entity: created, conflict: "none", applied: true },
        broadcast: { type: "broadcast", entityType: "note", operation, entity: created },
      };
    }
    // LWW decision uses incomingUpdatedAt (client time) vs existing, not serverTime, to avoid fast-clock wins via serverTime
    const incomingForCompare = { updated_at: incomingUpdatedAt, version: incomingVersion, device_id: incomingDeviceId };
    const existingForCompare = { updated_at: existing.updated_at ?? serverTime, version: existing.version ?? 0, device_id: existing.device_id ?? "unknown" };
    if (!lwwIncomingWins(incomingForCompare, existingForCompare)) {
      return { response: { entity: existing, conflict: "lww_rejected", applied: false }, broadcast: null };
    }
    const { entity: updated } = store.upsertNote(sanitizedEntity as Partial<import("../models/types.js").Note> & { id: string });
    return {
      response: { entity: updated, conflict: "none", applied: true },
      broadcast: { type: "broadcast", entityType: "note", operation, entity: updated },
    };
  } else {
    const existing = store.getFolder(id);
    if (!existing) {
      const { entity: created } = store.upsertFolder(sanitizedEntity as Partial<import("../models/types.js").Folder> & { id: string });
      return {
        response: { entity: created, conflict: "none", applied: true },
        broadcast: { type: "broadcast", entityType: "folder", operation, entity: created },
      };
    }
    const incomingForCompare = { updated_at: incomingUpdatedAt, version: incomingVersion, device_id: incomingDeviceId };
    const existingForCompare = { updated_at: existing.updated_at ?? serverTime, version: existing.version ?? 0, device_id: existing.device_id ?? "unknown" };
    if (!lwwIncomingWins(incomingForCompare, existingForCompare)) {
      return { response: { entity: existing, conflict: "lww_rejected", applied: false }, broadcast: null };
    }
    const { entity: updated } = store.upsertFolder(sanitizedEntity as Partial<import("../models/types.js").Folder> & { id: string });
    return {
      response: { entity: updated, conflict: "none", applied: true },
      broadcast: { type: "broadcast", entityType: "folder", operation, entity: updated },
    };
  }
}
