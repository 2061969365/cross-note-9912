// DEPRECATED: tables defined here are not wired; AppDatabase uses raw SQL. Will be removed.
// These Drift Table definitions are dead code — AppDatabase in database.dart creates
// tables via manual DDL (allTables is intentionally empty). Kept for reference until
// the quality-group cleanup removes this file.
import 'package:drift/drift.dart';

class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get folderId => text().nullable().named('folder_id')();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get content => text().withDefault(const Constant(''))();
  TextColumn get createdAt => text().named('created_at')();
  TextColumn get updatedAt => text().named('updated_at')();
  TextColumn get deletedAt => text().nullable().named('deleted_at')();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text().named('device_id').withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class Folders extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get createdAt => text().named('created_at')();
  TextColumn get updatedAt => text().named('updated_at')();
  TextColumn get deletedAt => text().nullable().named('deleted_at')();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text().named('device_id').withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class SyncQueue extends Table {
  TextColumn get id => text()();
  TextColumn get entityType => text().named('entity_type')();
  TextColumn get entityId => text().named('entity_id')();
  TextColumn get operation => text()();
  TextColumn get payload => text()();
  TextColumn get createdAt => text().named('created_at')();
  IntColumn get retryCount => integer().named('retry_count').withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('PENDING'))();

  @override
  Set<Column> get primaryKey => {id};
}
