import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SyncStatus { idle, syncing, offline, error }

class SyncState {
  final SyncStatus status;
  final String? lastSyncAt;
  final String? error;
  final int pendingCount;
  const SyncState({this.status = SyncStatus.idle, this.lastSyncAt, this.error, this.pendingCount = 0});
  SyncState copyWith({SyncStatus? status, String? lastSyncAt, String? error, int? pendingCount}) =>
      SyncState(status: status ?? this.status, lastSyncAt: lastSyncAt ?? this.lastSyncAt, error: error, pendingCount: pendingCount ?? this.pendingCount);
}

/// Notifier for [syncStateProvider]. SyncEngine should drive this on
/// status transitions: connecting -> syncing -> idle (and offline/error).
class SyncStateNotifier extends StateNotifier<SyncState> {
  SyncStateNotifier() : super(const SyncState());
  void setStatus(SyncStatus s, {String? error}) => state = state.copyWith(status: s, error: error);
  void setPendingCount(int n) => state = state.copyWith(pendingCount: n);
  void setLastSyncAt(String iso) => state = state.copyWith(lastSyncAt: iso);
}

final syncStateProvider = StateNotifierProvider<SyncStateNotifier, SyncState>((ref) => SyncStateNotifier());

// TODO wired by sync_engine repair agent — SyncEngine must call
// ref.read(syncStateProvider.notifier).setStatus(...) on every
// connecting/syncing/idle/offline transition and update pendingCount
// after enqueue/drain. Kept minimal here so the engine agent owns the wiring.
