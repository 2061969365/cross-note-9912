import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../platform/platform_info.dart';

class DeviceIdStore {
  static const _key = 'cross_note_device_id';
  static const _uuid = Uuid();

  static Future<String> getOrCreate() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_key);
    if (id != null && id.isNotEmpty) return id;
    final prefix = platformPrefix(currentPlatform());
    id = '$prefix-${_uuid.v4().substring(0, 8)}';
    await prefs.setString(_key, id);
    return id;
  }
}
