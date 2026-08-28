import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme.dart';
import '../../app/widgets/empty_state.dart';
import '../../app/widgets/note_card.dart';
import '../../repositories/folder_repository.dart';
import '../../models/folder.dart';

class FoldersPage extends ConsumerWidget {
  const FoldersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stream = ref.watch(folderRepositoryProvider).watchFolders();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('文件夹'),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.6))),
      ),
      body: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: StreamBuilder<List<Folder>>(
          stream: stream,
          builder: (_, snap) {
            if (snap.connectionState == ConnectionState.waiting) return const SkeletonList();
            if (snap.hasError) return EmptyState(icon: Icons.error_outline_rounded, title: '加载失败', subtitle: '${snap.error}');
            final folders = snap.data ?? [];
            if (folders.isEmpty) {
              return EmptyState(
                icon: Icons.folder_open_rounded, title: '还没有文件夹', subtitle: '建个文件夹来归类笔记吧',
                actionLabel: '新建文件夹', actionIcon: Icons.create_new_folder_rounded,
                onAction: () => _createDialog(context, ref),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              itemCount: folders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final f = folders[i];
                return FolderCard(
                  name: f.name, updatedAt: f.updatedAt, version: f.version,
                  onRename: () => _renameDialog(context, ref, f),
                  onDelete: () => _deleteConfirm(context, ref, f),
                );
              },
            );
          },
        ),
      )),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'folders_fab',
        onPressed: () => _createDialog(context, ref),
        icon: const Icon(Icons.create_new_folder_rounded),
        label: const Text('新建文件夹'),
      ),
    );
  }

  static Future<void> _createDialog(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: '文件夹名称')),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('创建')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) await ref.read(folderRepositoryProvider).create(name);
  }

  static Future<void> _renameDialog(BuildContext context, WidgetRef ref, Folder f) async {
    final ctrl = TextEditingController(text: f.name);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(controller: ctrl, autofocus: true),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('确定')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) await ref.read(folderRepositoryProvider).rename(f, name);
  }

  static Future<void> _deleteConfirm(BuildContext context, WidgetRef ref, Folder f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除文件夹？'),
        content: Text('“${f.name}” 将被删除，名下笔记不受影响。'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) await ref.read(folderRepositoryProvider).softDelete(f);
  }
}
