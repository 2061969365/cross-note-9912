import 'dart:io';
import 'package:path_provider/path_provider.dart';

abstract class FileSystemService {
  Future<Directory> getAppDir();
  Future<File> writeText(String relativePath, String content);
  Future<String?> readText(String relativePath);
}

class DefaultFileSystemService implements FileSystemService {
  @override
  Future<Directory> getAppDir() => getApplicationDocumentsDirectory();

  @override
  Future<File> writeText(String relativePath, String content) async {
    final dir = await getAppDir();
    final file = File('${dir.path}/$relativePath');
    await file.parent.create(recursive: true);
    return file.writeAsString(content);
  }

  @override
  Future<String?> readText(String relativePath) async {
    final dir = await getAppDir();
    final file = File('${dir.path}/$relativePath');
    if (!await file.exists()) return null;
    return file.readAsString();
  }
}
