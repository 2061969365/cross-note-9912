class Note {
  final String id;
  final String? folderId;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int version;
  final String deviceId;

  const Note({
    required this.id,
    this.folderId,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.version,
    required this.deviceId,
  });

  bool get isDeleted => deletedAt != null;

  Note copyWith({String? title, String? content, String? folderId, bool clearFolder = false, DateTime? updatedAt, DateTime? deletedAt, bool clearDeleted = false, int? version, String? deviceId}) => Note(
    id: id,
    folderId: clearFolder ? null : (folderId ?? this.folderId),
    title: title ?? this.title,
    content: content ?? this.content,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: clearDeleted ? null : (deletedAt ?? this.deletedAt),
    version: version ?? this.version,
    deviceId: deviceId ?? this.deviceId,
  );

  factory Note.fromJson(Map<String, dynamic> j) => Note(
    id: j['id'] as String,
    folderId: j['folder_id'] as String?,
    title: (j['title'] as String?) ?? '',
    content: (j['content'] as String?) ?? '',
    createdAt: DateTime.parse(j['created_at'] as String),
    updatedAt: DateTime.parse(j['updated_at'] as String),
    deletedAt: j['deleted_at'] != null ? DateTime.parse(j['deleted_at'] as String) : null,
    version: (j['version'] as num?)?.toInt() ?? 1,
    deviceId: (j['device_id'] as String?) ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'folder_id': folderId,
    'title': title,
    'content': content,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
    'version': version,
    'device_id': deviceId,
  };
}
