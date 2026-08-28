// Stage1 stub — not wired; Stage2 will integrate with platform notifications.
import 'package:flutter/foundation.dart';

/// 阶段一为桩实现：仅打日志，阶段二再接入系统通知。
/// 抽象为接口，便于后续按平台替换。
abstract class NotificationService {
  Future<void> show(String title, String body);
}

class NoopNotificationService implements NotificationService {
  @override
  Future<void> show(String title, String body) async {
    debugPrint('[notification] $title — $body');
  }
}
