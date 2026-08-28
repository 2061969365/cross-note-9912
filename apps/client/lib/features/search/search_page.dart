import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
    return Scaffold(
      appBar: AppBar(title: const Text('搜索')),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '输入关键词…', border: OutlineInputBorder()), onChanged: (v) => setState(() => query = v))),
        Expanded(child: query.trim().isEmpty ? const Center(child: Text('输入关键词搜索标题与正文')) : StreamBuilder(stream: repo.watchNotes(query: query), builder: (_, snap) {
          final notes = snap.data ?? [];
          if (notes.isEmpty) return const Center(child: Text('无结果'));
          return ListView.separated(padding: const EdgeInsets.all(12), itemCount: notes.length, separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (_, i) {
            final n = notes[i];
            return Card(child: ListTile(title: Text(n.title.isEmpty ? '无标题' : n.title), subtitle: Text(n.content, maxLines: 2, overflow: TextOverflow.ellipsis), onTap: () => context.push('/note/${n.id}')));
          });
        })),
      ]),
    );
  }
}
