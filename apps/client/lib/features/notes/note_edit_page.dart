import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../repositories/note_repository.dart';
import '../../repositories/folder_repository.dart';
import '../../models/note.dart';

class NoteEditPage extends ConsumerStatefulWidget {
  final String noteId;
  const NoteEditPage({super.key, required this.noteId});
  @override
  ConsumerState<NoteEditPage> createState() => _NoteEditPageState();
}

class _NoteEditPageState extends ConsumerState<NoteEditPage> {
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  Note? _note;
  Timer? _debounce;
  bool _preview = false;
  String? _folderId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _titleCtrl.addListener(_onChanged);
    _contentCtrl.addListener(_onChanged);
  }

  Future<void> _load() async {
    final n = await ref.read(noteRepositoryProvider).getById(widget.noteId);
    if (!mounted) return;
    if (n == null) { setState(() => _loading = false); return; }
    _note = n;
    _titleCtrl.text = n.title;
    _contentCtrl.text = n.content;
    _folderId = n.folderId;
    setState(() => _loading = false);
  }

  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _save);
  }

  Future<void> _save() async {
    if (_note == null) return;
    final title = _titleCtrl.text;
    final content = _contentCtrl.text;
    if (title == _note!.title && content == _note!.content && _folderId == _note!.folderId) return;
    await ref.read(noteRepositoryProvider).update(_note!, title: title, content: content, folderId: _folderId, clearFolder: _folderId == null && _note!.folderId != null);
    // refresh local ref
    _note = await ref.read(noteRepositoryProvider).getById(widget.noteId);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    // flush pending save
    if (_note != null && (_titleCtrl.text != _note!.title || _contentCtrl.text != _note!.content)) {
      // best-effort sync fire-and-forget
      ref.read(noteRepositoryProvider).update(_note!, title: _titleCtrl.text, content: _contentCtrl.text, folderId: _folderId, clearFolder: _folderId == null);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_note == null) return Scaffold(appBar: AppBar(title: const Text('未找到')), body: const Center(child: Text('笔记不存在或已被删除')));

    final foldersAsync = ref.watch(folderRepositoryProvider).watchFolders();

    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑'),
        actions: [
          IconButton(icon: Icon(_preview ? Icons.edit_outlined : Icons.visibility_outlined), onPressed: () => setState(() => _preview = !_preview), tooltip: _preview ? '编辑' : '预览'),
          IconButton(icon: const Icon(Icons.save_outlined), onPressed: _save, tooltip: '保存'),
        ],
      ),
      body: _preview
          ? Markdown(data: _contentCtrl.text.isEmpty ? '_空内容_' : _contentCtrl.text, padding: const EdgeInsets.all(16))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: '标题', border: OutlineInputBorder()), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                StreamBuilder(
                  stream: foldersAsync,
                  builder: (_, snap) {
                    final folders = snap.data ?? [];
                    return DropdownButtonFormField<String?>(
                      initialValue: _folderId,
                      decoration: const InputDecoration(labelText: '文件夹', border: OutlineInputBorder()),
                      items: [const DropdownMenuItem<String?>(value: null, child: Text('无文件夹')), ...folders.map((f) => DropdownMenuItem<String?>(value: f.id, child: Text(f.name)))],
                      onChanged: (v) { setState(() => _folderId = v); _onChanged(); },
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextField(controller: _contentCtrl, decoration: const InputDecoration(labelText: '正文 (Markdown)', border: OutlineInputBorder(), alignLabelWithHint: true), maxLines: 18, minLines: 8),
                const SizedBox(height: 8),
                Text('离线优先：输入自动保存到本地并入同步队列', style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12)),
              ],
            ),
    );
  }
}
