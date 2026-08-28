import type { DatabaseSync } from "node:sqlite";
import type { Folder, Note } from "../models/types.js";

export type Store = {
  upsertNote(note: Partial<Note> & { id: string }): { entity: Note; isNew: boolean };
  upsertFolder(folder: Partial<Folder> & { id: string }): { entity: Folder; isNew: boolean };
  getNote(id: string): Note | null;
  getFolder(id: string): Folder | null;
  listNotes(since?: string, limit?: number, includeDeleted?: boolean): Note[];
  listFolders(since?: string, limit?: number, includeDeleted?: boolean): Folder[];
  pull(since?: string, limit?: number, includeDeleted?: boolean): { notes: Note[]; folders: Folder[]; cursor: string };
};

function rowToNote(r: Record<string, unknown>): Note {
  return r as unknown as Note;
}
function rowToFolder(r: Record<string, unknown>): Folder {
  return r as unknown as Folder;
}

export function createSqliteStore(db: DatabaseSync): Store {
  const getNoteStmt = db.prepare("SELECT * FROM notes WHERE id=?");
  const getFolderStmt = db.prepare("SELECT * FROM folders WHERE id=?");

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
      const existing = (getNoteStmt.get(partial.id) as Record<string, unknown> | undefined) as Note | undefined;
      const now = new Date().toISOString();
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
        db.prepare(
          "INSERT INTO notes(id,folder_id,title,content,created_at,updated_at,deleted_at,version,device_id) VALUES(?,?,?,?,?,?,?,?,?)"
        ).run(note.id, note.folder_id, note.title, note.content, note.created_at, note.updated_at, note.deleted_at, note.version, note.device_id);
        return { entity: note, isNew: true };
      }
      // LWW will be decided by caller; this just applies the write with version bump
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
      db.prepare(
        "UPDATE notes SET folder_id=?,title=?,content=?,updated_at=?,deleted_at=?,version=?,device_id=? WHERE id=?"
      ).run(next.folder_id, next.title, next.content, next.updated_at, next.deleted_at, next.version, next.device_id, next.id);
      return { entity: next, isNew: false };
    },
    upsertFolder(partial) {
      const existing = (getFolderStmt.get(partial.id) as Record<string, unknown> | undefined) as Folder | undefined;
      const now = new Date().toISOString();
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
        db.prepare(
          "INSERT INTO folders(id,name,created_at,updated_at,deleted_at,version,device_id) VALUES(?,?,?,?,?,?,?)"
        ).run(f.id, f.name, f.created_at, f.updated_at, f.deleted_at, f.version, f.device_id);
        return { entity: f, isNew: true };
      }
      const next: Folder = {
        id: existing.id,
        name: partial.name ?? (existing.name as string),
        created_at: existing.created_at as string,
        updated_at: partial.updated_at ?? now,
        deleted_at: partial.deleted_at !== undefined ? (partial.deleted_at as string | null) : (existing.deleted_at as string | null),
        version: ((existing.version as number) ?? 1) + 1,
        device_id: (partial.device_id as string) ?? (existing.device_id as string),
      };
      db.prepare("UPDATE folders SET name=?,updated_at=?,deleted_at=?,version=?,device_id=? WHERE id=?").run(
        next.name, next.updated_at, next.deleted_at, next.version, next.device_id, next.id
      );
      return { entity: next, isNew: false };
    },
    listNotes(since, limit = 100, includeDeleted = true) {
      const lim = Math.min(Math.max(limit, 1), 500);
      if (since) {
        const rows = db.prepare(
          includeDeleted
            ? "SELECT * FROM notes WHERE updated_at > ? ORDER BY updated_at ASC, id ASC LIMIT ?"
            : "SELECT * FROM notes WHERE updated_at > ? AND deleted_at IS NULL ORDER BY updated_at ASC, id ASC LIMIT ?"
        ).all(since, lim) as Record<string, unknown>[];
        return rows.map(rowToNote);
      }
      const rows = db.prepare(
        includeDeleted
          ? "SELECT * FROM notes ORDER BY updated_at DESC, id ASC LIMIT ?"
          : "SELECT * FROM notes WHERE deleted_at IS NULL ORDER BY updated_at DESC, id ASC LIMIT ?"
      ).all(lim) as Record<string, unknown>[];
      return rows.map(rowToNote);
    },
    listFolders(since, limit = 100, includeDeleted = true) {
      const lim = Math.min(Math.max(limit, 1), 500);
      if (since) {
        const rows = db.prepare(
          includeDeleted
            ? "SELECT * FROM folders WHERE updated_at > ? ORDER BY updated_at ASC, id ASC LIMIT ?"
            : "SELECT * FROM folders WHERE updated_at > ? AND deleted_at IS NULL ORDER BY updated_at ASC, id ASC LIMIT ?"
        ).all(since, lim) as Record<string, unknown>[];
        return rows.map(rowToFolder);
      }
      const rows = db.prepare(
        includeDeleted
          ? "SELECT * FROM folders ORDER BY updated_at DESC, id ASC LIMIT ?"
          : "SELECT * FROM folders WHERE deleted_at IS NULL ORDER BY updated_at DESC, id ASC LIMIT ?"
      ).all(lim) as Record<string, unknown>[];
      return rows.map(rowToFolder);
    },
    pull(since, limit = 100, includeDeleted = true) {
      const lim = Math.min(Math.max(limit, 1), 500);
      const notes = this.listNotes(since, lim, includeDeleted);
      const folders = this.listFolders(since, lim, includeDeleted);
      const allTimes = [...notes.map((n) => n.updated_at), ...folders.map((f) => f.updated_at)].sort();
      const cursor = allTimes.at(-1) ?? since ?? new Date(0).toISOString();
      return { notes, folders, cursor };
    },
  };
}
