enum SyncOperation { create, update, delete }
enum EntityType { note, folder }
enum QueueStatus { pending, syncing, failed, done }

extension QueueStatusX on QueueStatus {
  String get wire => switch (this) { QueueStatus.pending => 'PENDING', QueueStatus.syncing => 'SYNCING', QueueStatus.failed => 'FAILED', QueueStatus.done => 'DONE' };
}

class SyncQueueItem {
  final String id;
  final EntityType entityType;
  final String entityId;
  final SyncOperation operation;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int retryCount;
  final QueueStatus status;

  const SyncQueueItem({required this.id, required this.entityType, required this.entityId, required this.operation, required this.payload, required this.createdAt, this.retryCount = 0, this.status = QueueStatus.pending});
}
