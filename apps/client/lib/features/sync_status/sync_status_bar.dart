import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme.dart';
import '../../sync/sync_engine.dart';

class SyncStatusBar extends ConsumerWidget {
  const SyncStatusBar({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: ref.read(appDatabaseProvider).pendingQueue(limit: 100),
      builder: (_, snap) {
        final n = (snap.data as List?)?.length ?? 0;
        final scheme = Theme.of(context).colorScheme;
        final isOk = n == 0;
        final color = isOk ? scheme.primary : scheme.error;
        final bg = isOk ? scheme.primaryContainer.withValues(alpha: 0.45) : scheme.errorContainer.withValues(alpha: 0.55);
        final label = n == 0 ? '已同步' : '待同步 $n 条';
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: color.withValues(alpha: 0.22)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(isOk ? Icons.cloud_done_rounded : Icons.cloud_sync_rounded, size: 14, color: color),
            const SizedBox(width: 6),
            Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 12, color: color, fontWeight: FontWeight.w700)),
          ]),
        );
      },
    );
  }
}
