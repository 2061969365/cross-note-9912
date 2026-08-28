import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/config/app_config.dart';
import '../core/network/api_client.dart';
import '../core/storage/device_id.dart';
import '../database/database.dart';
import 'conflict_resolver.dart';
import 'sync_state.dart';
import 'websocket_client.dart';

final appDatabaseProvider = Provider<AppDatabase>((_) => AppDatabase());
final apiClientProvider = Provider<ApiClient>((_) => ApiClient());
final deviceIdProvider = FutureProvider<String>((_) => DeviceIdStore.getOrCreate());

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final api = ref.watch(apiClientProvider);
  final engine = SyncEngine(db: db, api: api);
  ref.onDispose(engine.dispose);
  Future.microtask(engine.start);
  return engine;
});

final syncStateProvider = StateProvider<SyncState>((_) => const SyncState());

class SyncEngine {
  final AppDatabase db;
  final ApiClient api;
  SyncWsClient? _ws;
  Timer? _pollTimer;
  String? _deviceId;
  String? _cursor;
  bool _syncing = false;

  SyncEngine({required this.db, required this.api});

  Future<void> start() async {
    _deviceId = await DeviceIdStore.getOrCreate();
    _cursor = await db.getMeta('sync_cursor');
    _connectWs();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => _pull());
    await _drainQueue();
    await _pull();
  }

  void _connectWs() {
    SharedPreferences.getInstance().then((p) {
      final base = p.getString('server_url') ?? AppConfig.defaultServerUrl;
      final wsUrl = base.replaceFirst(RegExp(r'^http'), 'ws') + '/ws';
      _ws?.dispose();
      _ws = SyncWsClient(wsUrl);
      _ws!.onOpen = () {
        _ws!.send({'type': 'hello', 'deviceId': _deviceId, 'cursor': _cursor});
      };
      _ws!.onError = (_) {};
      _ws!.messages.listen(_onWsMessage);
      _ws!.connect();
    });
  }

  Future<void> _onWsMessage(Map<String, dynamic> msg) async {
    final type = msg['type'] as String?;
    if (type == 'hello_ack') {
      _cursor = msg['cursor'] as String? ?? _cursor;
      if (_cursor != null) await db.setMeta('sync_cursor', _cursor!);
      await _applyPullResult(msg);
      await _drainQueue();
    } else if (type == 'pull_result') {
      await _applyPullResult(msg);
    } else if (type == 'broadcast') {
      await _applyBroadcast(msg);
    } else if (type == 'push_ack') {
      final applied = msg['applied'] as bool? ?? true;
      final conflict = msg['conflict'] as String? ?? 'none';
      if (!applied && conflict == 'lww_rejected' && msg['entity'] != null) {
        final entity = msg['entity'] as Map<String, dynamic>;
        final entityType = msg['entityType'] as String?;
        if (entityType == 'note') await db.upsertNoteRow(entity);
        if (entityType == 'folder') await db.upsertFolderRow(entity);
      } else if (applied && msg['entity'] != null) {
        final entity = msg['entity'] as Map<String, dynamic>;
        final entityType = msg['entityType'] as String?;
        if (entityType == 'note') await db.upsertNoteRow(entity);
        if (entityType == 'folder') await db.upsertFolderRow(entity);
        final updatedAt = entity['updated_at'] as String?;
        if (updatedAt != null && (_cursor == null || updatedAt.compareTo(_cursor!) > 0)) {
          _cursor = updatedAt;
          await db.setMeta('sync_cursor', _cursor!);
        }
      }
      await _drainQueue();
    }
  }

  Future<void> _applyPullResult(Map<String, dynamic> msg) async {
    final notes = (msg['notes'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final folders = (msg['folders'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    for (final n in notes) {
      final existing = await db.getNoteById(n['id'] as String);
      if (existing == null) {
        await db.upsertNoteRow(n);
      } else {
        final ex = {
          'updated_at': existing['updated_at'] as String? ?? '',
          'version': (existing['version'] as num?)?.toInt() ?? 0,
          'device_id': existing['device_id'] as String? ?? '',
        };
        if (shouldApplyIncoming(n, ex)) await db.upsertNoteRow(n);
      }
    }
    for (final f in folders) {
      await db.upsertFolderRow(f);
    }
    final cursor = msg['cursor'] as String?;
    if (cursor != null && (_cursor == null || cursor.compareTo(_cursor!) > 0)) {
      _cursor = cursor;
      await db.setMeta('sync_cursor', cursor);
    }
  }

  Future<void> _applyBroadcast(Map<String, dynamic> msg) async {
    final entityType = msg['entityType'] as String?;
    final entity = msg['entity'] as Map<String, dynamic>?;
    if (entity == null || entityType == null) return;
    if (entityType == 'note') {
      final existing = await db.getNoteById(entity['id'] as String);
      if (existing == null) {
        await db.upsertNoteRow(entity);
      } else {
        final ex = {
          'updated_at': existing['updated_at'] as String? ?? '',
          'version': (existing['version'] as num?)?.toInt() ?? 0,
          'device_id': existing['device_id'] as String? ?? '',
        };
        if (shouldApplyIncoming(entity, ex)) await db.upsertNoteRow(entity);
      }
    } else if (entityType == 'folder') {
      await db.upsertFolderRow(entity);
    }
    final updatedAt = entity['updated_at'] as String?;
    if (updatedAt != null && (_cursor == null || updatedAt.compareTo(_cursor!) > 0)) {
      _cursor = updatedAt;
      await db.setMeta('sync_cursor', _cursor!);
    }
  }

  Future<void> enqueue(String entityType, String entityId, String operation, Map<String, dynamic> payload) async {
    await db.enqueue(entityType, entityId, operation, payload);
    await _drainQueue();
  }

  Future<void> _drainQueue() async {
    if (_syncing) return;
    _syncing = true;
    try {
      final pendings = await db.pendingQueue(limit: 20);
      for (final item in pendings) {
        final payload = jsonDecode(item['payload'] as String) as Map<String, dynamic>;
        final itemId = item['id'] as String;
        final entityType = item['entity_type'] as String;
        final operation = item['operation'] as String;
        final retryCount = (item['retry_count'] as num?)?.toInt() ?? 0;
        await db.markQueueStatus(itemId, 'SYNCING');
        var ok = false;
        if (_ws != null) {
          try {
            _ws!.send({'type': 'push', 'entityType': entityType, 'operation': operation, 'entity': payload});
            await db.markQueueStatus(itemId, 'DONE');
            await db.deleteQueue(itemId);
            ok = true;
          } catch (_) {
            ok = false;
          }
        }
        if (!ok) {
          try {
            final res = await api.push(entityType: entityType, operation: operation, entity: payload);
            final entity = res['entity'] as Map<String, dynamic>?;
            if (entity != null) {
              if (entityType == 'note') await db.upsertNoteRow(entity);
              if (entityType == 'folder') await db.upsertFolderRow(entity);
              final updatedAt = entity['updated_at'] as String?;
              if (updatedAt != null && (_cursor == null || updatedAt.compareTo(_cursor!) > 0)) {
                _cursor = updatedAt;
                await db.setMeta('sync_cursor', _cursor!);
              }
            }
            await db.deleteQueue(itemId);
          } catch (_) {
            final nextRetry = retryCount + 1;
            await db.markQueueStatus(itemId, nextRetry >= 5 ? 'FAILED' : 'PENDING', retryCount: nextRetry);
          }
        }
      }
    } finally {
      _syncing = false;
    }
  }

  Future<void> _pull() async {
    try {
      final res = await api.pull(since: _cursor, limit: 200);
      await _applyPullResult(res);
    } catch (_) {
      // offline — will retry via timer / reconnect
    }
  }

  Future<void> forceSync() async {
    await _drainQueue();
    await _pull();
  }

  void dispose() {
    _pollTimer?.cancel();
    _ws?.dispose();
  }
}
