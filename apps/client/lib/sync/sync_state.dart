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
