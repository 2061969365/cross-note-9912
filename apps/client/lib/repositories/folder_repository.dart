import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../core/storage/device_id.dart';
import '../database/database.dart';
import '../models/folder.dart';
import '../sync/sync_engine.dart';

final folderRepositoryProvider = Provider<FolderRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final engine = ref.watch(syncEngineProvider);
  return FolderRepository(db, engine);
});

class FolderRepository {
  final AppDatabase _db;
  final SyncEngine _engine;
  static const _uuid = Uuid();
  FolderRepository(this._db, this._engine);

  Stream<List<Folder>> watchFolders() => _db.watchFolders().map((rows) => rows.map((r) => Folder.fromJson(_map(r))).toList());

  Future<Folder> create(String name) async {
    final deviceId = await DeviceIdStore.getOrCreate();
    final now = DateTime.now().toIso8601String();
    final f = Folder(id: _uuid.v4(), name: name, createdAt: DateTime.parse(now), updatedAt: DateTime.parse(now), version: 1, deviceId: deviceId);
    final json = f.toJson();
    await _db.runTransaction(() async {
      await _db.upsertFolderRow(json);
      await _engine.enqueue('folder', f.id, 'CREATE', json);
    });
    return f;
  }

  String _clip(String s, int max) => s.length <= max ? s : s.substring(0, max);
  Future<void> rename(Folder folder, String name) async {
    final clipped = _clip(name, 200);
    final now = DateTime.now().toIso8601String();
    final updated = Folder(id: folder.id, name: clipped, createdAt: folder.createdAt, updatedAt: DateTime.parse(now), version: folder.version + 1, deviceId: folder.deviceId);
    await _db.runTransaction(() async {
      final json = updated.toJson();
      await _db.upsertFolderRow(json);
      await _engine.enqueue('folder', updated.id, 'UPDATE', json);
    });
  }

  Future<void> softDelete(Folder folder) async {
    final now = DateTime.now().toIso8601String();
    final deleted = Folder(id: folder.id, name: folder.name, createdAt: folder.createdAt, updatedAt: DateTime.parse(now), deletedAt: DateTime.parse(now), version: folder.version + 1, deviceId: folder.deviceId);
    final json = deleted.toJson();
    await _db.runTransaction(() async {
      await _db.upsertFolderRow(json);
      await _engine.enqueue('folder', deleted.id, 'DELETE', json);
    });
  }

  Map<String, dynamic> _map(Map<String, dynamic> r) => {
    'id': r['id'],
    'name': r['name'],
    'created_at': r['created_at'],
    'updated_at': r['updated_at'],
    'deleted_at': r['deleted_at'],
    'version': r['version'],
    'device_id': r['device_id'],
  };
}
