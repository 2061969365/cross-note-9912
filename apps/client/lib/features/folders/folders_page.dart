import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/folder_repository.dart';
import '../../models/folder.dart';

class FoldersPage extends ConsumerWidget {
  const FoldersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stream = ref.watch(folderRepositoryProvider).watchFolders();
    return Scaffold(
      appBar: AppBar(title: const Text('文件夹')),
      body: StreamBuilder<List<Folder>>(
        stream: stream,
        builder: (_, snap) {
          final folders = snap.data ?? [];
          if (folders.isEmpty) return const Center(child: Text('还没有文件夹'));
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: folders.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final f = folders[i];
              return Card(child: ListTile(title: Text(f.name), subtitle: Text('v${f.version} · ${f.updatedAt.toLocal().toString().substring(0, 19)}'), trailing: PopupMenuButton<String>(onSelected: (v) async {
                if (v == 'rename') {
                  final ctrl = TextEditingController(text: f.name);
                  final name = await showDialog<String>(context: context, builder: (_) => AlertDialog(title: const Text('重命名'), content: TextField(controller: ctrl, autofocus: true), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('确定'))]));
                  if (name != null && name.isNotEmpty) await ref.read(folderRepositoryProvider).rename(f, name);
                } else if (v == 'delete') {
                  await ref.read(folderRepositoryProvider).softDelete(f);
                }
              }, itemBuilder: (_) => const [PopupMenuItem(value: 'rename', child: Text('重命名')), PopupMenuItem(value: 'delete', child: Text('删除'))])));
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final ctrl = TextEditingController();
          final name = await showDialog<String>(context: context, builder: (_) => AlertDialog(title: const Text('新建文件夹'), content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: '文件夹名称')), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('创建'))]));
          if (name != null && name.isNotEmpty) await ref.read(folderRepositoryProvider).create(name);
        },
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('新建文件夹'),
      ),
    );
  }
}
