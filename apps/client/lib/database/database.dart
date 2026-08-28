import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:uuid/uuid.dart';

/// Manual DDL database — no codegen.
///
/// We intentionally keep [allTables] empty and create tables via raw SQL
/// in [migration.onCreate]. This avoids needing `database.g.dart` and keeps
/// the schema portable. Drift table classes in `tables/notes.dart` are dead
/// code (deprecated) and will be removed; do not wire them here.
/// Stream invalidation is handled manually via [notifyUpdates] + broadcast
/// controllers because [customSelect] with `readsFrom: const {}` never
/// auto-invalidates.
class AppDatabase extends GeneratedDatabase {
  AppDatabase() : super(driftDatabase(name: 'cross_note'));

  @override
  int get schemaVersion => 1;

  @override
  List<TableInfo> get allTables => const [];

  // Broadcast controllers to drive watch streams manually.
  // Drift's watch invalidation requires readsFrom to contain TableInfo
  // objects, but we use manual DDL (allTables == []). Instead we re-query
  // on every explicit notification.
  final StreamController<void> _notesChangeController =
      StreamController<void>.broadcast();
  final StreamController<void> _foldersChangeController =
      StreamController<void>.broadcast();

  void _notifyNotes() {
    // Notify drift's update stream (for any future readsFrom wiring) and
    // our manual broadcast so watchNotes re-emits.
    try {
      notifyUpdates({TableUpdate('notes', kind: UpdateKind.insert)});
    } catch (_) {}
    if (!_notesChangeController.isClosed) {
      _notesChangeController.add(null);
    }
  }

  void _notifyFolders() {
    try {
      notifyUpdates({TableUpdate('folders', kind: UpdateKind.insert)});
    } catch (_) {}
    if (!_foldersChangeController.isClosed) {
      _foldersChangeController.add(null);
    }
  }

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
      // Additional indexes for query performance
      await customStatement('CREATE INDEX IF NOT EXISTS idx_notes_updated_id ON notes(updated_at, id)');
      await customStatement('CREATE INDEX IF NOT EXISTS idx_folders_updated_id ON folders(updated_at, id)');
      await customStatement('CREATE INDEX IF NOT EXISTS idx_notes_deleted ON notes(deleted_at)');
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA journal_mode=WAL');
      await customStatement('PRAGMA foreign_keys=ON');
      // ensure meta exists for older installs
      await customStatement('CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT)');
      // Ensure new indexes exist on existing installs (idempotent)
      await customStatement('CREATE INDEX IF NOT EXISTS idx_notes_updated_id ON notes(updated_at, id)');
      await customStatement('CREATE INDEX IF NOT EXISTS idx_folders_updated_id ON folders(updated_at, id)');
      await customStatement('CREATE INDEX IF NOT EXISTS idx_notes_deleted ON notes(deleted_at)');
      // Reset orphaned SYNCING entries left after a crash/restart so they
      // are retried instead of stuck forever.
      try {
        await customStatement("UPDATE sync_queue SET status='PENDING' WHERE status='SYNCING'");
      } catch (_) {}
    },
  );

  /// Transaction helper via raw SQL BEGIN/COMMIT/ROLLBACK.
  /// Named [runTransaction] to avoid shadowing [GeneratedDatabase.transaction].
  Future<void> runTransaction(Future<void> Function() fn) async {
    await customStatement('BEGIN');
    try {
      await fn();
      await customStatement('COMMIT');
    } catch (e) {
      try {
        await customStatement('ROLLBACK');
      } catch (_) {}
      rethrow;
    }
  }

  @override
  Future<T> transaction<T>(Future<T> Function() action, {bool requireNew = false}) async {
    await customStatement('BEGIN');
    try {
      final result = await action();
      await customStatement('COMMIT');
      return result;
    } catch (e) {
      try {
        await customStatement('ROLLBACK');
      } catch (_) {}
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    await _notesChangeController.close();
    await _foldersChangeController.close();
    await super.close();
  }

  // Notes
  Stream<List<Map<String, dynamic>>> watchNotes({String? folderId, String? query}) async* {
    Future<List<Map<String, dynamic>>> fetch() async {
      var sql = "SELECT * FROM notes WHERE deleted_at IS NULL";
      final vars = <Variable>[];
      if (folderId != null) {
        sql += " AND folder_id = ?";
        vars.add(Variable.withString(folderId));
      }
      if (query != null && query.trim().isNotEmpty) {
        // Escape LIKE wildcards so user input is treated literally.
        final esc = query.trim().replaceAll('%', r'\%').replaceAll('_', r'\_');
        final q = '%$esc%';
        sql += " AND (title LIKE ? ESCAPE '\\' OR content LIKE ? ESCAPE '\\')";
        vars.add(Variable.withString(q));
        vars.add(Variable.withString(q));
      }
      sql += " ORDER BY updated_at DESC";
      // readsFrom empty would never auto-invalidate; we drive invalidation
      // manually via _notesChangeController, so a one-shot get() per emission
      // is correct. Keep readsFrom empty to avoid drift asserting on missing tables.
      final rows = await customSelect(sql, variables: vars, readsFrom: const {}).get();
      return rows.map((r) => r.data).toList();
    }

    yield await fetch();
    await for (final _ in _notesChangeController.stream) {
      yield await fetch();
    }
  }

  Future<Map<String, dynamic>?> getNoteById(String id) async {
    final rows = await customSelect("SELECT * FROM notes WHERE id = ?", variables: [Variable.withString(id)]).get();
    return rows.isEmpty ? null : rows.first.data;
  }

  Future<List<Map<String, dynamic>>> getAllFolders() async {
    final rows = await customSelect("SELECT * FROM folders WHERE deleted_at IS NULL ORDER BY updated_at DESC").get();
    return rows.map((r) => r.data).toList();
  }

  Stream<List<Map<String, dynamic>>> watchFolders() async* {
    Future<List<Map<String, dynamic>>> fetch() async {
      final rows = await customSelect(
        "SELECT * FROM folders WHERE deleted_at IS NULL ORDER BY updated_at DESC",
        readsFrom: const {},
      ).get();
      return rows.map((r) => r.data).toList();
    }

    yield await fetch();
    await for (final _ in _foldersChangeController.stream) {
      yield await fetch();
    }
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
    _notifyNotes();
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
    _notifyFolders();
  }

  Future<void> enqueue(String entityType, String entityId, String operation, Map<String, dynamic> payload) async {
    await customStatement(
      "INSERT INTO sync_queue(id,entity_type,entity_id,operation,payload,created_at,status) VALUES(?,?,?,?,?,?,?)",
      [const Uuid().v4(), entityType, entityId, operation, jsonEncode(payload), DateTime.now().toIso8601String(), 'PENDING'],
    );
  }

  Future<List<Map<String, dynamic>>> pendingQueue({int limit = 50}) async {
    // Include SYNCING so orphaned in-flight items are retried after the
    // startup reset in beforeOpen. Without this, items stuck in SYNCING
    // would never be picked up again.
    final rows = await customSelect(
      "SELECT * FROM sync_queue WHERE status IN ('PENDING','FAILED','SYNCING') ORDER BY created_at ASC LIMIT ?",
      variables: [Variable.withInt(limit)],
    ).get();
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
