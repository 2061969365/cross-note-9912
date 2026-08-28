// Deprecated — Device is currently unused outside models; retained for Stage2
// multi-device awareness. Other agent may delete if confirmed unused.
// ignore: unused_element — suppress while retained as planned model.
class Device {
  final String id;
  final String platform;
  final DateTime firstSeenAt;
  const Device({required this.id, required this.platform, required this.firstSeenAt});

  Map<String, dynamic> toJson() => {
        'id': id,
        'platform': platform,
        'first_seen_at': firstSeenAt.toIso8601String(),
      };

  factory Device.fromJson(Map<String, dynamic> j) => Device(
        id: j['id'] as String,
        platform: j['platform'] as String? ?? 'unknown',
        firstSeenAt: DateTime.parse(j['first_seen_at'] as String),
      );
}
