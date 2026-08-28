import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../core/storage/device_id.dart';
import '../database/database.dart';
import '../models/note.dart';
import '../sync/sync_engine.dart';

final noteRepositoryProvider = Provider<NoteRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final engine = ref.watch(syncEngineProvider);
  return NoteRepository(db, engine);
});

class NoteRepository {
  final AppDatabase _db;
  final SyncEngine _engine;
  static const _uuid = Uuid();
  NoteRepository(this._db, this._engine);

  Stream<List<Note>> watchNotes({String? folderId, String? query}) =>
      _db.watchNotes(folderId: folderId, query: query).map((rows) => rows.map((r) => Note.fromJson(_rowToJson(r))).where((n) => !n.isDeleted).toList());

  Future<Note?> getById(String id) async {
    final r = await _db.getNoteById(id);
    return r == null ? null : Note.fromJson(_rowToJson(r));
  }

  // Offline-first: write local immediately, enqueue for sync.
  Future<Note> create({String? folderId, String title = '', String content = ''}) async {
    final safeTitle = _clip(title, 500);
    final safeContent = _clip(content, 100000);
    final deviceId = await DeviceIdStore.getOrCreate();
    final now = DateTime.now().toIso8601String();
    final note = Note(id: _uuid.v4(), folderId: folderId, title: safeTitle, content: safeContent, createdAt: DateTime.parse(now), updatedAt: DateTime.parse(now), version: 1, deviceId: deviceId);
    final json = note.toJson();
    await _db.runTransaction(() async {
      await _db.upsertNoteRow(json);
      await _engine.enqueue('note', note.id, 'CREATE', json);
    });
    return note;
  }

  String _clip(String s, int max) => s.length <= max ? s : s.substring(0, max);
  Future<void> update(Note note, {String? title, String? content, String? folderId, bool clearFolder = false}) async {
    final deviceId = await DeviceIdStore.getOrCreate();
    final now = DateTime.now().toIso8601String();
    final safeTitle = title == null ? null : _clip(title, 500);
    final safeContent = content == null ? null : _clip(content, 100000);
    final updated = note.copyWith(
      title: safeTitle,
      content: safeContent,
      folderId: clearFolder ? null : folderId,
      updatedAt: DateTime.parse(now),
      version: note.version + 1,
      deviceId: deviceId,
    );
    // manual folder clear handling for copyWith
    final json = updated.toJson();
    if (clearFolder) json['folder_id'] = null;
    await _db.runTransaction(() async {
      await _db.upsertNoteRow(json);
      await _engine.enqueue('note', updated.id, 'UPDATE', json);
    });
  }

  Future<void> softDelete(Note note) async {
    final now = DateTime.now().toIso8601String();
    final deleted = note.copyWith(deletedAt: DateTime.parse(now), updatedAt: DateTime.parse(now), version: note.version + 1);
    final json = deleted.toJson();
    await _db.runTransaction(() async {
      await _db.upsertNoteRow(json);
      await _engine.enqueue('note', deleted.id, 'DELETE', json);
    });
  }

  Future<void> restore(Note note) async {
    final now = DateTime.now().toIso8601String();
    final deviceId = await DeviceIdStore.getOrCreate();
    final restored = Note(id: note.id, folderId: note.folderId, title: note.title, content: note.content, createdAt: note.createdAt, updatedAt: DateTime.parse(now), deletedAt: null, version: note.version + 1, deviceId: deviceId);
    final json = restored.toJson();
    await _db.runTransaction(() async {
      await _db.upsertNoteRow(json);
      await _engine.enqueue('note', restored.id, 'UPDATE', json);
    });
  }

  Future<void> hardDelete(String id) async {
    await _db.customStatement("DELETE FROM notes WHERE id=?", [id]);
  }

  Future<List<Note>> search(String query) async {
    final rows = await _db.watchNotes(query: query).first;
    return rows.map((r) => Note.fromJson(_rowToJson(r))).toList();
  }

  Map<String, dynamic> _rowToJson(Map<String, dynamic> r) => {
    'id': r['id'],
    'folder_id': r['folder_id'],
    'title': r['title'],
    'content': r['content'],
    'created_at': r['created_at'],
    'updated_at': r['updated_at'],
    'deleted_at': r['deleted_at'],
    'version': r['version'],
    'device_id': r['device_id'],
  };
}
