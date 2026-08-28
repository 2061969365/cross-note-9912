/// 语义别名：物理存储为 AppDatabase.sync_queue，
/// 本文件暴露队列相关的常量与辅助，便于按文档结构检索。
class SyncQueueMeta {
  static const table = 'sync_queue';
  static const statusPending = 'PENDING';
  static const statusSyncing = 'SYNCING';
  static const statusFailed = 'FAILED';
  static const statusDone = 'DONE';

  static const opCreate = 'CREATE';
  static const opUpdate = 'UPDATE';
  static const opDelete = 'DELETE';
}
