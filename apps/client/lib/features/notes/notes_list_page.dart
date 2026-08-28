import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme.dart';
import '../../app/widgets/empty_state.dart';
import '../../app/widgets/note_card.dart';
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
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(11)),
            child: Icon(Icons.edit_note_rounded, color: scheme.onPrimaryContainer, size: 20),
          ),
          const SizedBox(width: 10),
          Text('CrossNote', style: text.titleLarge),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.sync_rounded), onPressed: () => ref.read(syncEngineProvider).forceSync(), tooltip: '立即同步'),
          const SizedBox(width: 4),
          FutureBuilder<String>(
            future: DeviceIdStore.getOrCreate(),
            builder: (_, s) => s.hasData
                ? Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.phone_android_rounded, size: 13, color: scheme.outline),
                        const SizedBox(width: 4),
                        Text(s.data!.length > 14 ? '${s.data!.substring(0, 14)}…' : s.data!,
                          style: text.labelSmall?.copyWith(fontSize: 11, color: scheme.onSurfaceVariant)),
                      ]),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(height: 1, thickness: 1, color: scheme.outlineVariant.withValues(alpha: 0.6))),
      ),
      body: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search_rounded, color: scheme.outline),
                hintText: '搜索标题或正文…',
                suffixIcon: searchQuery.isEmpty ? null : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => setState(() => searchQuery = ''),
                ),
              ),
              onChanged: (v) => setState(() => searchQuery = v),
            ),
          ),
          StreamBuilder(
            stream: foldersStream,
            builder: (_, snap) {
              final folders = snap.data ?? [];
              if (folders.isEmpty) return const SizedBox.shrink();
              return SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    ChoiceChip(
                      label: const Text('全部'),
                      selected: selectedFolderId == null,
                      onSelected: (_) => setState(() => selectedFolderId = null),
                    ),
                    const SizedBox(width: 8),
                    ...folders.map((f) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(f.name),
                            selected: selectedFolderId == f.id,
                            onSelected: (_) => setState(() => selectedFolderId = selectedFolderId == f.id ? null : f.id),
                          ),
                        )),
                  ],
                ),
              );
            },
          ),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Divider(height: 10, color: scheme.outlineVariant.withValues(alpha: 0.45))),
          Expanded(
            child: StreamBuilder<List<Note>>(
              stream: notesStream,
              builder: (_, snap) {
                if (snap.connectionState == ConnectionState.waiting) return const SkeletonList();
                if (snap.hasError) {
                  return EmptyState(icon: Icons.error_outline_rounded, title: '加载失败', subtitle: '${snap.error}', actionLabel: '重试', onAction: () => setState(() {}));
                }
                final notes = snap.data ?? [];
                if (notes.isEmpty) {
                  if (searchQuery.isNotEmpty) {
                    return EmptyState(icon: Icons.search_off_rounded, title: '无匹配结果', subtitle: '试试别的关键词');
                  }
                  return EmptyState(
                    icon: Icons.note_alt_rounded,
                    title: '还没有笔记',
                    subtitle: '点右下角创建第一篇，或先建个文件夹归类',
                    actionLabel: '新建笔记',
                    actionIcon: Icons.add_rounded,
                    onAction: () async {
                      final repo = ref.read(noteRepositoryProvider);
                      final note = await repo.create(folderId: selectedFolderId, title: '新笔记', content: '');
                      if (!mounted) return;
                      // ignore: use_build_context_synchronously
                      context.push('/note/${note.id}');
                    },
                  );
                }
                return StreamBuilder(
                  stream: foldersStream,
                  builder: (_, fsnap) {
                    final folderMap = {for (final f in (fsnap.data ?? [])) f.id: f.name};
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                      itemCount: notes.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final n = notes[i];
                        return NoteCard(
                          title: n.title,
                          content: n.content,
                          updatedAt: n.updatedAt,
                          folderName: n.folderId == null ? null : folderMap[n.folderId],
                          onTap: () => context.push('/note/${n.id}'),
                          onDelete: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text('删除笔记？'),
                                content: const Text('将移入墓碑，同步后其他设备也会删除。'),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                                  FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
                                ],
                              ),
                            );
                            if (ok == true && mounted) await ref.read(noteRepositoryProvider).softDelete(n);
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ]),
      )),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'notes_fab',
        onPressed: () async {
          final repo = ref.read(noteRepositoryProvider);
          final note = await repo.create(folderId: selectedFolderId, title: '新笔记', content: '');
          if (!mounted) return;
          // ignore: use_build_context_synchronously
          context.push('/note/${note.id}');
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('新笔记'),
      ),
    );
  }
}
