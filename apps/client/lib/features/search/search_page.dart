import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/widgets/empty_state.dart';
import '../../app/widgets/note_card.dart';
import '../../repositories/note_repository.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});
  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(noteRepositoryProvider);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('搜索'),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.6))),
      ),
      body: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search_rounded, color: scheme.outline),
                hintText: '输入关键词…',
                suffixIcon: query.isEmpty ? null : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => setState(() => query = ''),
                ),
              ),
              onChanged: (v) => setState(() => query = v),
            ),
          ),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Divider(height: 8, color: scheme.outlineVariant.withValues(alpha: 0.45))),
          Expanded(child: query.trim().isEmpty
            ? EmptyState(icon: Icons.search_rounded, title: '搜索笔记', subtitle: '输入关键词搜索标题与正文')
            : StreamBuilder(stream: repo.watchNotes(query: query), builder: (_, snap) {
                if (snap.connectionState == ConnectionState.waiting) return const SkeletonList(count: 4);
                final notes = snap.data ?? [];
                if (notes.isEmpty) return EmptyState(icon: Icons.search_off_rounded, title: '无结果', subtitle: '试试别的关键词');
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  itemCount: notes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final n = notes[i];
                    return NoteCard(
                      title: n.title, content: n.content, updatedAt: n.updatedAt,
                      onTap: () => context.push('/note/${n.id}'),
                    );
                  },
                );
              })),
        ]),
      )),
    );
  }
}
