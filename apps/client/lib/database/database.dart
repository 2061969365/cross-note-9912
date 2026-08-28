import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:uuid/uuid.dart';

class AppDatabase extends GeneratedDatabase {
  AppDatabase() : super(driftDatabase(name: 'cross_note'));

  @override
  int get schemaVersion => 1;

  @override
  List<TableInfo> get allTables => const [];

  // Create tables manually — no codegen
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await customStatement('''
        CREATE TABLE notes (
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
      ''');
      await customStatement('''
        CREATE TABLE folders (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          deleted_at TEXT,
          version INTEGER NOT NULL DEFAULT 1,
          device_id TEXT NOT NULL DEFAULT ''
        );
      ''');
      await customStatement('''
        CREATE TABLE sync_queue (
          id TEXT PRIMARY KEY,
          entity_type TEXT NOT NULL,
          entity_id TEXT NOT NULL,
          operation TEXT NOT NULL,
          payload TEXT NOT NULL,
          created_at TEXT NOT NULL,
          retry_count INTEGER NOT NULL DEFAULT 0,
          status TEXT NOT NULL DEFAULT 'PENDING'
        );
      ''');
      await customStatement('CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT)');
      await customStatement('CREATE INDEX IF NOT EXISTS idx_notes_updated_at ON notes(updated_at)');
      await customStatement('CREATE INDEX IF NOT EXISTS idx_notes_folder_id ON notes(folder_id)');
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA journal_mode=WAL');
      await customStatement('PRAGMA foreign_keys=ON');
      // ensure meta exists for older installs
      await customStatement('CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT)');
    },
  );

  // Notes
  Stream<List<Map<String, dynamic>>> watchNotes({String? folderId, String? query}) {
    var sql = "SELECT * FROM notes WHERE deleted_at IS NULL";
    final vars = <Variable>[];
    if (folderId != null) {
      sql += " AND folder_id = ?";
      vars.add(Variable.withString(folderId));
    }
    if (query != null && query.trim().isNotEmpty) {
      sql += " AND (title LIKE ? OR content LIKE ?)";
      final q = '%${query.trim()}%';
      vars.add(Variable.withString(q));
      vars.add(Variable.withString(q));
    }
    sql += " ORDER BY updated_at DESC";
    return customSelect(sql, variables: vars, readsFrom: const {}).watch().map((rows) => rows.map((r) => r.data).toList());
  }

  Future<Map<String, dynamic>?> getNoteById(String id) async {
    final rows = await customSelect("SELECT * FROM notes WHERE id = ?", variables: [Variable.withString(id)]).get();
    return rows.isEmpty ? null : rows.first.data;
  }

  Future<List<Map<String, dynamic>>> getAllFolders() async {
    final rows = await customSelect("SELECT * FROM folders WHERE deleted_at IS NULL ORDER BY updated_at DESC").get();
    return rows.map((r) => r.data).toList();
  }

  Stream<List<Map<String, dynamic>>> watchFolders() {
    return customSelect("SELECT * FROM folders WHERE deleted_at IS NULL ORDER BY updated_at DESC", readsFrom: const {}).watch().map((rows) => rows.map((r) => r.data).toList());
  }

  Future<void> upsertNoteRow(Map<String, dynamic> j) async {
    await customStatement(
      "INSERT INTO notes(id,folder_id,title,content,created_at,updated_at,deleted_at,version,device_id) VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET folder_id=excluded.folder_id, title=excluded.title, content=excluded.content, updated_at=excluded.updated_at, deleted_at=excluded.deleted_at, version=excluded.version, device_id=excluded.device_id",
      [
        j['id'] as String,
        j['folder_id'] as String?,
        (j['title'] as String?) ?? '',
        (j['content'] as String?) ?? '',
        j['created_at'] as String,
        j['updated_at'] as String,
        j['deleted_at'] as String?,
        (j['version'] as num?)?.toInt() ?? 1,
        (j['device_id'] as String?) ?? '',
      ],
    );
  }

  Future<void> upsertFolderRow(Map<String, dynamic> j) async {
    await customStatement(
      "INSERT INTO folders(id,name,created_at,updated_at,deleted_at,version,device_id) VALUES(?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name, updated_at=excluded.updated_at, deleted_at=excluded.deleted_at, version=excluded.version, device_id=excluded.device_id",
      [
        j['id'] as String,
        (j['name'] as String?) ?? 'Untitled',
        j['created_at'] as String,
        j['updated_at'] as String,
        j['deleted_at'] as String?,
        (j['version'] as num?)?.toInt() ?? 1,
        (j['device_id'] as String?) ?? '',
      ],
    );
  }

  Future<void> enqueue(String entityType, String entityId, String operation, Map<String, dynamic> payload) async {
    await customStatement(
      "INSERT INTO sync_queue(id,entity_type,entity_id,operation,payload,created_at,status) VALUES(?,?,?,?,?,?,?)",
      [const Uuid().v4(), entityType, entityId, operation, jsonEncode(payload), DateTime.now().toIso8601String(), 'PENDING'],
    );
  }

  Future<List<Map<String, dynamic>>> pendingQueue({int limit = 50}) async {
    final rows = await customSelect("SELECT * FROM sync_queue WHERE status IN ('PENDING','FAILED') ORDER BY created_at ASC LIMIT ?", variables: [Variable.withInt(limit)]).get();
    return rows.map((r) => r.data).toList();
  }

  Future<void> markQueueStatus(String id, String status, {int? retryCount}) async {
    if (retryCount != null) {
      await customStatement("UPDATE sync_queue SET status=?, retry_count=? WHERE id=?", [status, retryCount, id]);
    } else {
      await customStatement("UPDATE sync_queue SET status=? WHERE id=?", [status, id]);
    }
  }

  Future<void> deleteQueue(String id) async {
    await customStatement("DELETE FROM sync_queue WHERE id=?", [id]);
  }

  Future<String?> getMeta(String key) async {
    final rows = await customSelect("SELECT value FROM meta WHERE key=?", variables: [Variable.withString(key)]).get();
    return rows.isEmpty ? null : rows.first.data['value'] as String?;
  }

  Future<void> setMeta(String key, String value) async {
    await customStatement("INSERT INTO meta(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", [key, value]);
  }
}
