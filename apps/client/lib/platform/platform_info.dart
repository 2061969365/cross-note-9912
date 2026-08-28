import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;

enum AppPlatform { android, windows, web, other }

AppPlatform currentPlatform() {
  if (kIsWeb) return AppPlatform.web;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android: return AppPlatform.android;
    case TargetPlatform.windows: return AppPlatform.windows;
    default: return AppPlatform.other;
  }
}

String platformPrefix(AppPlatform p) => switch (p) {
  AppPlatform.android => 'android',
  AppPlatform.windows => 'windows',
  AppPlatform.web => 'web',
  AppPlatform.other => 'device',
};
