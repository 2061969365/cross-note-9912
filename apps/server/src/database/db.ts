import { DatabaseSync } from "node:sqlite";
import { mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const _here = dirname(fileURLToPath(import.meta.url));
// src/database -> ../../data  , dist/database -> ../../data  均指向 apps/server/data
export const DB_PATH = process.env.DB_PATH || join(_here, "..", "..", "data", "cross_note.db");

// log helper: reuse resolved DB_PATH so callers (e.g. index.ts) can log without creating a second DB instance
export function getDbPath(): string {
  return DB_PATH;
}
export function logDbPath(): void {
  console.log(`[db] path=${DB_PATH}`);
}

export function openDb(path = DB_PATH): DatabaseSync {
  mkdirSync(dirname(path), { recursive: true });
  const db = new DatabaseSync(path);
  const jm = db.prepare("PRAGMA journal_mode=WAL").get() as any;
  if ((jm as any)?.journal_mode !== "wal") console.warn("WAL not enabled", jm);
  db.exec("PRAGMA foreign_keys=ON; PRAGMA busy_timeout=5000; PRAGMA synchronous=NORMAL; PRAGMA cache_size=-64000;");
  return db;
}

export function migrate(db: DatabaseSync) {
  try {
    const v = (db.prepare("PRAGMA user_version").get() as any)?.user_version ?? 0;
    if (v < 1) {
      db.exec(`
    CREATE TABLE IF NOT EXISTS notes (
      id TEXT PRIMARY KEY,
      folder_id TEXT,
      title TEXT NOT NULL DEFAULT '',
      content TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT,
      version INTEGER NOT NULL DEFAULT 1,
      device_id TEXT NOT NULL DEFAULT ''
    );
  `);
      db.exec(`
    CREATE TABLE IF NOT EXISTS folders (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT,
      version INTEGER NOT NULL DEFAULT 1,
      device_id TEXT NOT NULL DEFAULT ''
    );
  `);
      db.prepare("PRAGMA user_version=1").run();
    }
    db.exec(`
    CREATE INDEX IF NOT EXISTS idx_notes_updated_at ON notes(updated_at);
    CREATE INDEX IF NOT EXISTS idx_notes_folder_id ON notes(folder_id);
    CREATE INDEX IF NOT EXISTS idx_folders_updated_at ON folders(updated_at);
    CREATE INDEX IF NOT EXISTS idx_notes_deleted ON notes(deleted_at);
    CREATE INDEX IF NOT EXISTS idx_folders_deleted ON folders(deleted_at);
    CREATE INDEX IF NOT EXISTS idx_notes_updated_id ON notes(updated_at, id);
    CREATE INDEX IF NOT EXISTS idx_folders_updated_id ON folders(updated_at, id);
  `);
  } catch (e) {
    console.warn("migrate failed", e);
    throw e;
  }
}
