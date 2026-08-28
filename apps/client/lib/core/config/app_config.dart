import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;

/// Central app configuration.
///
/// Server URLs can be overridden at runtime via the Settings page (persisted
/// preference takes precedence over these defaults). See Settings > Server URL.
class AppConfig {
  static const String defaultServerUrl = 'http://localhost:8787';
  static const String defaultWsUrl = 'ws://localhost:8787/ws';
  static const String appVersion = '0.1.0';

  /// Platform-aware server URL. On an Android emulator `localhost` is not
  /// reachable from inside the VM — `10.0.2.2` is the host loopback alias.
  /// Callers that respect user overrides should prefer the persisted setting
  /// and only fall back to this getter for the built-in default.
  static String get effectiveServerUrl {
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        defaultServerUrl.contains('localhost')) {
      return defaultServerUrl.replaceFirst('localhost', '10.0.2.2');
    }
    return defaultServerUrl;
  }

  static String get effectiveWsUrl {
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        defaultWsUrl.contains('localhost')) {
      return defaultWsUrl.replaceFirst('localhost', '10.0.2.2');
    }
    return defaultWsUrl;
  }
}
