class Folder {
  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int version;
  final String deviceId;

  const Folder({required this.id, required this.name, required this.createdAt, required this.updatedAt, this.deletedAt, required this.version, required this.deviceId});

  bool get isDeleted => deletedAt != null;

  factory Folder.fromJson(Map<String, dynamic> j) => Folder(
    id: j['id'] as String,
    name: (j['name'] as String?) ?? 'Untitled',
    createdAt: DateTime.parse(j['created_at'] as String),
    updatedAt: DateTime.parse(j['updated_at'] as String),
    deletedAt: j['deleted_at'] != null ? DateTime.parse(j['deleted_at'] as String) : null,
    version: (j['version'] as num?)?.toInt() ?? 1,
    deviceId: (j['device_id'] as String?) ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
    'version': version,
    'device_id': deviceId,
  };
}
