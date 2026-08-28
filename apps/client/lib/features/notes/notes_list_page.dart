import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../repositories/note_repository.dart';
import '../../repositories/folder_repository.dart';
import '../../sync/sync_engine.dart';
import '../../core/storage/device_id.dart';
import '../../models/note.dart';

class NotesListPage extends ConsumerStatefulWidget {
  const NotesListPage({super.key});
  @override
  ConsumerState<NotesListPage> createState() => _NotesListPageState();
}

class _NotesListPageState extends ConsumerState<NotesListPage> {
  String? selectedFolderId;
  String searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final notesStream = ref.watch(noteRepositoryProvider).watchNotes(folderId: selectedFolderId, query: searchQuery.isEmpty ? null : searchQuery);
    final foldersStream = ref.watch(folderRepositoryProvider).watchFolders();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('CrossNote'),
        actions: [
          IconButton(icon: const Icon(Icons.sync), onPressed: () => ref.read(syncEngineProvider).forceSync(), tooltip: '立即同步'),
          FutureBuilder<String>(
            future: DeviceIdStore.getOrCreate(),
            builder: (_, s) => s.hasData
                ? Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Chip(label: Text(s.data!, style: const TextStyle(fontSize: 11))),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '搜索标题或正文…', border: OutlineInputBorder(), isDense: true),
              onChanged: (v) => setState(() => searchQuery = v),
            ),
          ),
          StreamBuilder(
            stream: foldersStream,
            builder: (_, snap) {
              final folders = snap.data ?? [];
              if (folders.isEmpty) return const SizedBox.shrink();
              return SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    ChoiceChip(label: const Text('全部'), selected: selectedFolderId == null, onSelected: (_) => setState(() => selectedFolderId = null)),
                    const SizedBox(width: 8),
                    ...folders.map((f) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(label: Text(f.name), selected: selectedFolderId == f.id, onSelected: (_) => setState(() => selectedFolderId = selectedFolderId == f.id ? null : f.id)),
                        )),
                  ],
                ),
              );
            },
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<List<Note>>(
              stream: notesStream,
              builder: (_, snap) {
                if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                final notes = snap.data ?? [];
                if (notes.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.note_alt_outlined, size: 56, color: scheme.outline),
                        const SizedBox(height: 12),
                        const Text('还没有笔记'),
                        const SizedBox(height: 4),
                        Text('点右下角 + 创建', style: TextStyle(color: scheme.outline)),
                      ],
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: notes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final n = notes[i];
                    return Card(
                      child: ListTile(
                        title: Text(n.title.isEmpty ? '无标题' : n.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(n.content.isEmpty ? '空内容' : n.content, maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'delete') {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text('删除笔记？'),
                                  content: const Text('将移入墓碑，同步后其他设备也会删除。'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                                    FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
                                  ],
                                ),
                              );
                              if (ok == true && context.mounted) {
                                await ref.read(noteRepositoryProvider).softDelete(n);
                              }
                            }
                          },
                          itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('删除'))],
                        ),
                        onTap: () => context.push('/note/${n.id}'),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final repo = ref.read(noteRepositoryProvider);
          final note = await repo.create(folderId: selectedFolderId, title: '新笔记', content: '');
          if (mounted) context.push('/note/${note.id}');
        },
        icon: const Icon(Icons.add),
        label: const Text('新笔记'),
      ),
    );
  }
}
