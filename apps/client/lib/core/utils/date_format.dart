import 'package:intl/intl.dart';

final _fmtFull = DateFormat('yyyy-MM-dd HH:mm');
final _fmtDate = DateFormat('yyyy-MM-dd');

String formatDateTime(DateTime dt) => _fmtFull.format(dt.toLocal());
String formatDate(DateTime dt) => _fmtDate.format(dt.toLocal());

String relativeTime(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  if (diff.inDays < 7) return '${diff.inDays} 天前';
  return formatDate(dt);
}
