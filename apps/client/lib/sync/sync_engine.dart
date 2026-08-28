import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/config/app_config.dart';
import '../core/network/api_client.dart';
import '../core/storage/device_id.dart';
import '../database/database.dart';
import 'conflict_resolver.dart';
import 'websocket_client.dart';

final appDatabaseProvider = Provider<AppDatabase>((_) => AppDatabase());
final apiClientProvider = Provider<ApiClient>((_) => ApiClient());
final deviceIdProvider = FutureProvider<String>((_) => DeviceIdStore.getOrCreate());

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final api = ref.watch(apiClientProvider);
  final engine = SyncEngine(db: db, api: api);
  ref.onDispose(() {
    engine.dispose();
  });
  Future.microtask(() async {
    try {
      await engine.start();
    } catch (e, st) {
      // Startup microtask: wrapped in try/catch and log
      // ignore: avoid_print
      print('[SyncEngine] start failed: $e\n$st');
    }
  });
  return engine;
});

class SyncEngine {
  final AppDatabase db;
  final ApiClient api;
  SyncWsClient? _ws;
  Timer? _pollTimer;
  StreamSubscription<Map<String, dynamic>>? _wsSub;
  String? _deviceId;
  String? _cursor;
  bool _syncing = false;
  bool _needsDrain = false;
  // ignore: unused_field
  String _wsStatus = 'offline';

  // CRITICAL: pending acks for WS optimistic-delete fix
  final Map<String, String> _pendingAcks = {}; // entityId -> queueId
  final Map<String, Timer> _ackTimers = {}; // entityId -> timeout timer

  SyncEngine({required this.db, required this.api});

  Future<void> start() async {
    _deviceId = await DeviceIdStore.getOrCreate();
    _cursor = await db.getMeta('sync_cursor');
    // SYNCING orphan: one-time reset so killed app resumes
    try {
      await db.customStatement("UPDATE sync_queue SET status='PENDING' WHERE status='SYNCING'");
    } catch (_) {}
    _connectWs();
    _pollTimer?.cancel();
    // Redundant poll: skip REST pull when WS is connected
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_ws != null && _ws!.isConnected) return;
      _pull();
    });
    await _drainQueue();
    await _pull();
  }

  void _connectWs() {
    SharedPreferences.getInstance().then((p) {
      final base = p.getString('server_url') ?? AppConfig.defaultServerUrl;
      final wsUrl = '${base.replaceFirst(RegExp(r'^http'), 'ws')}/ws';
      try {
        _wsSub?.cancel();
      } catch (_) {}
      _ws?.dispose();
      _ws = SyncWsClient(wsUrl);
      _ws!.onOpen = () {
        _wsStatus = 'online';
        // Only send hello after onOpen confirmed
        final ok = _ws!.send({'type': 'hello', 'deviceId': _deviceId, 'cursor': _cursor});
        if (!ok) {
          _wsStatus = 'offline';
        }
      };
      _ws!.onError = (e) {
        _wsStatus = 'offline';
        _scheduleReconnect();
      };
      // _connectWs error swallowing: handle listen onError — don't swallow
      _wsSub = _ws!.messages.listen(_onWsMessage, onError: (e) {
        _wsStatus = 'offline';
        _scheduleReconnect();
      }, onDone: () {
        _wsStatus = 'offline';
      });
      _ws!.connect();
    }).catchError((e) {
      _wsStatus = 'offline';
      _scheduleReconnect();
    });
  }

  void _scheduleReconnect() {
    _wsStatus = 'offline';
    // WsClient has its own backoff with jitter; engine just marks offline. No tight-loop retry.
  }

  // LWW helpers — extracted to avoid triplication, reused in _applyPullResult, _applyBroadcast, push_ack
  Future<bool> _shouldApplyAndUpsertNote(Map<String, dynamic> note) async {
    final id = note['id'] as String?;
    if (id == null) return false;
    final existing = await db.getNoteById(id);
    if (existing == null) {
      await db.upsertNoteRow(note);
      return true;
    }
    final ex = {
      'updated_at': existing['updated_at'] as String? ?? '',
      'version': (existing['version'] as num?)?.toInt() ?? 0,
      'device_id': existing['device_id'] as String? ?? '',
    };
    if (shouldApplyIncoming(note, ex)) {
      await db.upsertNoteRow(note);
      return true;
    }
    return false;
  }

  Future<bool> _shouldApplyAndUpsertFolder(Map<String, dynamic> folder) async {
    final id = folder['id'] as String?;
    if (id == null) return false;
    Map<String, dynamic>? existing;
    try {
      final rows = await db.customSelect("SELECT * FROM folders WHERE id = ?", variables: [Variable.withString(id)]).get();
      existing = rows.isEmpty ? null : rows.first.data;
    } catch (_) {
      existing = null;
    }
    if (existing == null) {
      await db.upsertFolderRow(folder);
      return true;
    }
    final ex = {
      'updated_at': existing['updated_at'] as String? ?? '',
      'version': (existing['version'] as num?)?.toInt() ?? 0,
      'device_id': existing['device_id'] as String? ?? '',
    };
    if (shouldApplyIncoming(folder, ex)) {
      await db.upsertFolderRow(folder);
      return true;
    }
    return false;
  }

  Future<void> _advanceCursor(String? updatedAt) async {
    if (updatedAt == null) return;
    // pull()'s dual cursor is stored via _pull loop; broadcast's single entity cursor
    // is just for incremental advancement — compare lexicographically
    if (_cursor == null || updatedAt.compareTo(_cursor!) > 0) {
      _cursor = updatedAt;
      try { await db.setMeta('sync_cursor', _cursor!); } catch (_) {}
    }
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
      // CRITICAL: wait for push_ack to mark DONE — pendingAcks map + timeout
      final entity = msg['entity'] as Map<String, dynamic>?;
      final entityType = msg['entityType'] as String?;
      final ackId = (msg['id'] as String?) ?? (entity?['id'] as String?) ?? '';
      final queueId = _pendingAcks.remove(ackId);
      final t = _ackTimers.remove(ackId);
      t?.cancel();

      final applied = msg['applied'] as bool? ?? true;
      final conflict = msg['conflict'] as String? ?? 'none';

      if (queueId != null) {
        if (applied) {
          if (entity != null) {
            if (entityType == 'note') {
              await _shouldApplyAndUpsertNote(entity);
            } else if (entityType == 'folder') {
              await _shouldApplyAndUpsertFolder(entity);
            }
            await _advanceCursor(entity['updated_at'] as String?);
          }
          await db.markQueueStatus(queueId, 'DONE');
          await db.deleteQueue(queueId);
        } else {
          if (conflict == 'lww_rejected' && entity != null) {
            if (entityType == 'note') await db.upsertNoteRow(entity);
            if (entityType == 'folder') await db.upsertFolderRow(entity);
            await _advanceCursor(entity['updated_at'] as String?);
          }
          try {
            final rows = await db.customSelect("SELECT retry_count FROM sync_queue WHERE id=?", variables: [Variable.withString(queueId)]).get();
            final rc = rows.isEmpty ? 0 : (rows.first.data['retry_count'] as num?)?.toInt() ?? 0;
            final next = rc + 1;
            await db.markQueueStatus(queueId, next >= 5 ? 'FAILED' : 'PENDING', retryCount: next);
          } catch (_) {
            await db.markQueueStatus(queueId, 'FAILED');
          }
        }
      } else {
        // No pending ack (e.g. after restart or HTTP path) — still apply entity if any
        if (entity != null) {
          if (!applied && conflict == 'lww_rejected') {
            if (entityType == 'note') await db.upsertNoteRow(entity);
            if (entityType == 'folder') await db.upsertFolderRow(entity);
          } else if (applied) {
            if (entityType == 'note') await _shouldApplyAndUpsertNote(entity);
            if (entityType == 'folder') await _shouldApplyAndUpsertFolder(entity);
            await _advanceCursor(entity['updated_at'] as String?);
          }
        }
      }
      await _drainQueue();
    }
  }

  Future<void> _applyPullResult(Map<String, dynamic> msg) async {
    final notes = (msg['notes'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final folders = (msg['folders'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    // N+1: Keep sequential for now but add comment; if easy, batch getNoteById with single query (not required).
    for (final n in notes) {
      await _shouldApplyAndUpsertNote(n);
    }
    // Folder LWW gate: same LWW as notes (was unconditional upsert)
    for (final f in folders) {
      await _shouldApplyAndUpsertFolder(f);
    }
    final cursor = msg['cursor'] as String?;
    await _advanceCursor(cursor);
  }

  Future<void> _applyBroadcast(Map<String, dynamic> msg) async {
    final entityType = msg['entityType'] as String?;
    final entity = msg['entity'] as Map<String, dynamic>?;
    if (entity == null || entityType == null) return;
    // Folder dedup: avoid echo applying own broadcast
    final incomingId = entity['id'] as String?;
    if (incomingId != null && _pendingAcks.containsKey(incomingId)) {
      await _advanceCursor(entity['updated_at'] as String?);
      return;
    }
    if (entityType == 'note') {
      await _shouldApplyAndUpsertNote(entity);
    } else if (entityType == 'folder') {
      await _shouldApplyAndUpsertFolder(entity);
    }
    await _advanceCursor(entity['updated_at'] as String?);
  }

  Future<void> enqueue(String entityType, String entityId, String operation, Map<String, dynamic> payload) async {
    await db.enqueue(entityType, entityId, operation, payload);
    // Concurrent enqueue+drain race: unawaited drain; _drainQueue is re-entrant safe via _needsDrain
    unawaited(_drainQueue());
  }

  Future<void> _drainQueue() async {
    // Re-entrant safe: if already syncing, set _needsDrain and re-run after current batch
    if (_syncing) {
      _needsDrain = true;
      return;
    }
    _syncing = true;
    try {
      // Drain cap + loop: exhaust queue with cap 100 total per invocation (was 20 single pass)
      int total = 0;
      const cap = 100;
      const batchSize = 20;
      while (total < cap) {
        final remaining = cap - total;
        final limit = remaining < batchSize ? remaining : batchSize;
        final pendings = await db.pendingQueue(limit: limit);
        if (pendings.isEmpty) break;
        for (final item in pendings) {
          if (total >= cap) break;
          total++;
          final payload = jsonDecode(item['payload'] as String) as Map<String, dynamic>;
          final itemId = item['id'] as String;
          final entityType = item['entity_type'] as String;
          final operation = item['operation'] as String;
          final retryCount = (item['retry_count'] as num?)?.toInt() ?? 0;
          await db.markQueueStatus(itemId, 'SYNCING');
          var ok = false;
          if (_ws != null && _ws!.isConnected) {
            // CRITICAL: do NOT delete before push_ack. Keep SYNCING, wait for ack.
            final queueId = itemId;
            final entityId = (payload['id'] as String?) ?? '';
            if (entityId.isNotEmpty) {
              _pendingAcks[entityId] = queueId;
              _ackTimers[entityId]?.cancel();
              _ackTimers[entityId] = Timer(const Duration(seconds: 30), () async {
                if (_pendingAcks[entityId] == queueId) {
                  _pendingAcks.remove(entityId);
                  _ackTimers.remove(entityId);
                  try {
                    await db.markQueueStatus(queueId, 'PENDING');
                  } catch (_) {}
                  unawaited(_drainQueue());
                }
              });
            }
            final sent = _ws!.send({'type': 'push', 'entityType': entityType, 'operation': operation, 'entity': payload});
            if (sent) {
              ok = true;
              // do NOT mark DONE yet — wait for push_ack
            } else {
              if (entityId.isNotEmpty) {
                _pendingAcks.remove(entityId);
                _ackTimers.remove(entityId)?.cancel();
              }
              try {
                await db.markQueueStatus(itemId, 'PENDING');
              } catch (_) {}
              ok = false;
            }
          }
          if (!ok) {
            // HTTP branch: retry backoff — mark FAILED/PENDING, rely on next schedule (15s), no tight loop
            try {
              final res = await api.push(entityType: entityType, operation: operation, entity: payload);
              final entity = res['entity'] as Map<String, dynamic>?;
              if (entity != null) {
                if (entityType == 'note') await _shouldApplyAndUpsertNote(entity);
                if (entityType == 'folder') await _shouldApplyAndUpsertFolder(entity);
                await _advanceCursor(entity['updated_at'] as String?);
              }
              await db.deleteQueue(itemId);
            } catch (_) {
              final nextRetry = retryCount + 1;
              await db.markQueueStatus(itemId, nextRetry >= 5 ? 'FAILED' : 'PENDING', retryCount: nextRetry);
            }
          }
        }
        if (pendings.length < limit) break;
      }
    } finally {
      _syncing = false;
      if (_needsDrain) {
        _needsDrain = false;
        unawaited(_drainQueue());
      }
    }
  }

  Future<void> _pull() async {
    try {
      // hasMore loop — use sweep limit 100; pull() dual cursor handles per-table pagination
      String? cursor = _cursor;
      while (true) {
        final res = await api.pull(since: cursor, limit: 100);
        await _applyPullResult(res);
        final nextCursor = (res['cursor'] as String?) ?? (res['nextCursor'] as String?) ?? (res['next_cursor'] as String?);
        final hasMore = (res['hasMore'] as bool?) ?? (res['has_more'] as bool?) ?? false;
        if (nextCursor != null) {
          cursor = nextCursor;
          if (_cursor == null || nextCursor.compareTo(_cursor!) > 0) {
            _cursor = nextCursor;
          }
          try { await db.setMeta('sync_cursor', _cursor!); } catch (_) {}
        }
        if (!hasMore) break;
        if (nextCursor == null) break;
      }
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
    _pollTimer = null;
    try {
      _wsSub?.cancel();
    } catch (_) {}
    _wsSub = null;
    _ws?.dispose();
    _ws = null;
    for (final t in _ackTimers.values) {
      try {
        t.cancel();
      } catch (_) {}
    }
    _ackTimers.clear();
    _pendingAcks.clear();
  }
}
