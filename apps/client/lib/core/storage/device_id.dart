import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../platform/platform_info.dart';

class DeviceIdStore {
  static const _key = 'cross_note_device_id';
  static const _uuid = Uuid();

  static Future<String> getOrCreate() async {
    final prefs = await SharedPreferences.getInstance();
    // Fast path: already stored.
    var existing = prefs.getString(_key);
    if (existing != null && existing.isNotEmpty) return existing;

    // Use full v4 UUID — 8 hex chars is too short (only 32 bits, high
    // collision risk across devices). Full v4 gives 122 bits of entropy.
    final prefix = platformPrefix(currentPlatform());
    final id = '$prefix-${_uuid.v4()}';
    await prefs.setString(_key, id);
    // TOCTOU double-check: if two callers raced to create an ID
    // concurrently, return whatever actually persisted (one wins).
    return prefs.getString(_key) ?? id;
  }
}
