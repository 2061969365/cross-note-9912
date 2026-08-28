// Stage1 file-system abstraction — thin wrapper over path_provider; Stage2 may replace per-platform. (quality pass: deprecation note only; primary owned by platform agent)
// ignore: avoid_web_libraries_in_flutter
import 'dart:io' as io show File, Directory;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

abstract class FileSystemService {
  Future<io.Directory> getAppDir();
  Future<io.File> writeText(String relativePath, String content);
  Future<String?> readText(String relativePath);
}

class DefaultFileSystemService implements FileSystemService {
  @override
  Future<io.Directory> getAppDir() {
    if (kIsWeb) throw UnsupportedError('FileSystem is not supported on web');
    return getApplicationDocumentsDirectory();
  }

  @override
  Future<io.File> writeText(String relativePath, String content) async {
    if (kIsWeb) throw UnsupportedError('FileSystem writeText not supported on web');
    final dir = await getAppDir();
    final file = io.File('${dir.path}/$relativePath');
    await file.parent.create(recursive: true);
    return file.writeAsString(content);
  }

  @override
  Future<String?> readText(String relativePath) async {
    if (kIsWeb) throw UnsupportedError('FileSystem readText not supported on web');
    final dir = await getAppDir();
    final file = io.File('${dir.path}/$relativePath');
    if (!await file.exists()) return null;
    return file.readAsString();
  }
}
