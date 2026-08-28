import type { DatabaseSync } from "node:sqlite";
import type { Folder, Note } from "../models/types.js";

// TODO Stage2: make async for Durable Objects
export type Store = {
  upsertNote(note: Partial<Note> & { id: string }): { entity: Note; isNew: boolean };
  upsertFolder(folder: Partial<Folder> & { id: string }): { entity: Folder; isNew: boolean };
  getNote(id: string): Note | null;
  getFolder(id: string): Folder | null;
  listNotes(since?: string, limit?: number, includeDeleted?: boolean): Note[];
  listFolders(since?: string, limit?: number, includeDeleted?: boolean): Folder[];
  pull(since?: string, limit?: number, includeDeleted?: boolean): { notes: Note[]; folders: Folder[]; cursor: string; hasMore?: boolean };
};

function rowToNote(r: Record<string, unknown>): Note {
  return r as unknown as Note;
}
function rowToFolder(r: Record<string, unknown>): Folder {
  return r as unknown as Folder;
}

function parseCursor(cursor?: string | null): { time: string; id: string } {
  if (!cursor) return { time: "1970-01-01T00:00:00.000Z", id: "" };
  const idx = cursor.indexOf("|");
  if (idx === -1) return { time: cursor, id: "" };
  return { time: cursor.slice(0, idx), id: cursor.slice(idx + 1) };
}

export function createSqliteStore(db: DatabaseSync): Store {
  const getNoteStmt = db.prepare("SELECT * FROM notes WHERE id=?");
  const getFolderStmt = db.prepare("SELECT * FROM folders WHERE id=?");

  const insertNoteStmt = db.prepare(
    `INSERT INTO notes (id, folder_id, title, content, created_at, updated_at, deleted_at, version, device_id) VALUES (?,?,?,?,?,?,?,?,?)`,
  );
  const updateNoteStmt = db.prepare(
    `UPDATE notes SET folder_id=?, title=?, content=?, updated_at=?, deleted_at=?, version=?, device_id=? WHERE id=?`,
  );
  const insertFolderStmt = db.prepare(
    `INSERT INTO folders (id, name, created_at, updated_at, deleted_at, version, device_id) VALUES (?,?,?,?,?,?,?)`,
  );
  const updateFolderStmt = db.prepare(
    `UPDATE folders SET name=?, updated_at=?, deleted_at=?, version=?, device_id=? WHERE id=?`,
  );

  // Pagination: composite cursor (updated_at, id) with tie-breaker
  const listNotesStmt = db.prepare(
    `SELECT * FROM notes WHERE (updated_at > ? OR (updated_at = ? AND id > ?)) ORDER BY updated_at ASC, id ASC LIMIT ?`,
  );
  const listNotesExcludeDeletedStmt = db.prepare(
    `SELECT * FROM notes WHERE (updated_at > ? OR (updated_at = ? AND id > ?)) AND deleted_at IS NULL ORDER BY updated_at ASC, id ASC LIMIT ?`,
  );
  const listFoldersStmt = db.prepare(
    `SELECT * FROM folders WHERE (updated_at > ? OR (updated_at = ? AND id > ?)) ORDER BY updated_at ASC, id ASC LIMIT ?`,
  );
  const listFoldersExcludeDeletedStmt = db.prepare(
    `SELECT * FROM folders WHERE (updated_at > ? OR (updated_at = ? AND id > ?)) AND deleted_at IS NULL ORDER BY updated_at ASC, id ASC LIMIT ?`,
  );

  // Node 24 node:sqlite no longer exposes db.transaction() — use manual BEGIN/COMMIT
  // to keep version CAS atomic. Single writer in Stage1 so BEGIN IMMEDIATE is sufficient.
  function upsertNoteTx(partial: Partial<Note> & { id: string }): { entity: Note; isNew: boolean } {
    db.exec("BEGIN IMMEDIATE");
    try {
      const existing = getNoteStmt.get(partial.id) as Record<string, unknown> | undefined as unknown as Note | undefined;
      const now = new Date().toISOString();
      let result: { entity: Note; isNew: boolean };
      if (!existing) {
        const note: Note = {
          id: partial.id,
          folder_id: partial.folder_id ?? null,
          title: partial.title ?? "",
          content: partial.content ?? "",
          created_at: partial.created_at ?? now,
          updated_at: partial.updated_at ?? now,
          deleted_at: partial.deleted_at ?? null,
          version: 1,
          device_id: (partial.device_id as string) ?? "",
        };
        insertNoteStmt.run(note.id, note.folder_id, note.title, note.content, note.created_at, note.updated_at, note.deleted_at, note.version, note.device_id);
        result = { entity: note, isNew: true as const };
      } else {
        const next: Note = {
          id: existing.id,
          folder_id: (partial.folder_id !== undefined ? partial.folder_id : existing.folder_id) as string | null,
          title: partial.title ?? (existing.title as string),
          content: partial.content ?? (existing.content as string),
          created_at: existing.created_at as string,
          updated_at: partial.updated_at ?? now,
          deleted_at: partial.deleted_at !== undefined ? (partial.deleted_at as string | null) : (existing.deleted_at as string | null),
          version: ((existing.version as number) ?? 1) + 1,
          device_id: (partial.device_id as string) ?? (existing.device_id as string),
        };
        updateNoteStmt.run(next.folder_id, next.title, next.content, next.updated_at, next.deleted_at, next.version, next.device_id, next.id);
        result = { entity: next, isNew: false as const };
      }
      db.exec("COMMIT");
      return result;
    } catch (e) {
      try {
        db.exec("ROLLBACK");
      } catch {}
      throw e;
    }
  }

  function upsertFolderTx(partial: Partial<Folder> & { id: string }): { entity: Folder; isNew: boolean } {
    db.exec("BEGIN IMMEDIATE");
    try {
      const existing = getFolderStmt.get(partial.id) as Record<string, unknown> | undefined as unknown as Folder | undefined;
      const now = new Date().toISOString();
      let result: { entity: Folder; isNew: boolean };
      if (!existing) {
        const f: Folder = {
          id: partial.id,
          name: partial.name ?? "Untitled",
          created_at: partial.created_at ?? now,
          updated_at: partial.updated_at ?? now,
          deleted_at: partial.deleted_at ?? null,
          version: 1,
          device_id: (partial.device_id as string) ?? "",
        };
        insertFolderStmt.run(f.id, f.name, f.created_at, f.updated_at, f.deleted_at, f.version, f.device_id);
        result = { entity: f, isNew: true as const };
      } else {
        const next: Folder = {
          id: existing.id,
          name: partial.name ?? (existing.name as string),
          created_at: existing.created_at as string,
          updated_at: partial.updated_at ?? now,
          deleted_at: partial.deleted_at !== undefined ? (partial.deleted_at as string | null) : (existing.deleted_at as string | null),
          version: ((existing.version as number) ?? 1) + 1,
          device_id: (partial.device_id as string) ?? (existing.device_id as string),
        };
        updateFolderStmt.run(next.name, next.updated_at, next.deleted_at, next.version, next.device_id, next.id);
        result = { entity: next, isNew: false as const };
      }
      db.exec("COMMIT");
      return result;
    } catch (e) {
      try {
        db.exec("ROLLBACK");
      } catch {}
      throw e;
    }
  }

  return {
    getNote(id) {
      const r = getNoteStmt.get(id) as Record<string, unknown> | undefined;
      return r ? rowToNote(r) : null;
    },
    getFolder(id) {
      const r = getFolderStmt.get(id) as Record<string, unknown> | undefined;
      return r ? rowToFolder(r) : null;
    },
    upsertNote(partial) {
      return upsertNoteTx(partial);
    },
    upsertFolder(partial) {
      return upsertFolderTx(partial);
    },
    listNotes(since, limit = 100, includeDeleted = true) {
      const lim = Math.min(Math.max(limit, 1), 500);
      const { time: sinceTime, id: sinceId } = parseCursor(since);
      const rows = (
        includeDeleted
          ? listNotesStmt.all(sinceTime, sinceTime, sinceId, lim)
          : listNotesExcludeDeletedStmt.all(sinceTime, sinceTime, sinceId, lim)
      ) as Record<string, unknown>[];
      return rows.map(rowToNote);
    },
    listFolders(since, limit = 100, includeDeleted = true) {
      const lim = Math.min(Math.max(limit, 1), 500);
      const { time: sinceTime, id: sinceId } = parseCursor(since);
      const rows = (
        includeDeleted
          ? listFoldersStmt.all(sinceTime, sinceTime, sinceId, lim)
          : listFoldersExcludeDeletedStmt.all(sinceTime, sinceTime, sinceId, lim)
      ) as Record<string, unknown>[];
      return rows.map(rowToFolder);
    },
    pull(since, limit = 100, includeDeleted = true) {
      const lim = Math.min(Math.max(limit, 1), 500);
      const notes = this.listNotes(since, lim, includeDeleted);
      const folders = this.listFolders(since, lim, includeDeleted);
      const hasMore = notes.length === lim || folders.length === lim;
      // compute cursor as max (updated_at, id) tuple
      let latest: { updated_at: string; id: string } | null = null;
      for (const r of [...(notes as unknown as { updated_at: string; id: string }[]), ...(folders as unknown as { updated_at: string; id: string }[])]) {
        if (!latest || r.updated_at > latest.updated_at || (r.updated_at === latest.updated_at && r.id > latest.id)) {
          latest = r;
        }
      }
      let cursor: string;
      if (latest) {
        cursor = `${latest.updated_at}|${latest.id}`;
      } else {
        // do not regress cursor when no rows returned
        cursor = since ?? "1970-01-01T00:00:00.000Z";
      }
      return { notes, folders, cursor, hasMore };
    },
  };
}
