import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../app/theme.dart';
import '../../app/widgets/empty_state.dart';
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
  bool _saving = false;

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
    String title = _titleCtrl.text;
    String content = _contentCtrl.text;
    if (title.length > 500) title = title.substring(0, 500);
    if (content.length > 100000) content = content.substring(0, 100000);
    if (title == _note!.title && content == _note!.content && _folderId == _note!.folderId) return;
    setState(() => _saving = true);
    await ref.read(noteRepositoryProvider).update(_note!, title: title, content: content, folderId: _folderId, clearFolder: _folderId == null && _note!.folderId != null);
    _note = await ref.read(noteRepositoryProvider).getById(widget.noteId);
    if (mounted) setState(() => _saving = false);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    if (_note != null && (_titleCtrl.text != _note!.title || _contentCtrl.text != _note!.content)) {
      ref.read(noteRepositoryProvider).update(_note!, title: _titleCtrl.text, content: _contentCtrl.text, folderId: _folderId, clearFolder: _folderId == null);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    if (_loading) return Scaffold(body: Center(child: CircularProgressIndicator(color: scheme.primary)));
    if (_note == null) return Scaffold(appBar: AppBar(title: const Text('未找到')), body: EmptyState(icon: Icons.search_off_rounded, title: '笔记不存在', subtitle: '可能已被删除或尚未同步'));

    final foldersAsync = ref.watch(folderRepositoryProvider).watchFolders();

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Text('编辑'),
          const SizedBox(width: 8),
          if (_saving) SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary))
          else Icon(Icons.cloud_done_rounded, size: 14, color: scheme.outline),
          const SizedBox(width: 4),
          Text(_saving ? '保存中…' : '已自动保存', style: text.labelSmall?.copyWith(color: scheme.outline, fontSize: 11)),
        ]),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.6))),
        actions: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, icon: Icon(Icons.edit_rounded, size: 16), label: Text('编辑')),
              ButtonSegment(value: true, icon: Icon(Icons.visibility_rounded, size: 16), label: Text('预览')),
            ],
            selected: {_preview},
            onSelectionChanged: (s) => setState(() => _preview = s.first),
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill))),
            ),
            showSelectedIcon: false,
          ),
          const SizedBox(width: 8),
          IconButton(icon: const Icon(Icons.save_rounded), onPressed: _save, tooltip: '保存'),
          const SizedBox(width: 4),
        ],
      ),
      body: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: _preview
          ? Markdown(
              data: _contentCtrl.text.isEmpty ? '_空内容_' : _contentCtrl.text,
              padding: const EdgeInsets.all(20),
              styleSheet: MarkdownStyleSheet(
                h1: text.headlineMedium, h2: text.titleLarge, h3: text.titleMedium,
                p: text.bodyMedium?.copyWith(height: 1.6),
                code: text.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()], backgroundColor: scheme.surfaceContainerHigh),
                blockquoteDecoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(8)),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                TextField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(labelText: '标题', hintText: '给笔记起个标题'),
                  style: text.titleLarge?.copyWith(letterSpacing: -0.2),
                ),
                const SizedBox(height: 14),
                StreamBuilder(
                  stream: foldersAsync,
                  builder: (_, snap) {
                    final folders = snap.data ?? [];
                    return DropdownButtonFormField<String?>(
                      initialValue: _folderId,
                      decoration: const InputDecoration(labelText: '文件夹'),
                      items: [const DropdownMenuItem<String?>(value: null, child: Text('无文件夹')), ...folders.map((f) => DropdownMenuItem<String?>(value: f.id, child: Text(f.name)))],
                      onChanged: (v) { setState(() => _folderId = v); _onChanged(); },
                    );
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _contentCtrl,
                  decoration: const InputDecoration(labelText: '正文 (Markdown)', hintText: '支持 **粗体** / *斜体* / 列表 / 代码块', alignLabelWithHint: true),
                  maxLines: 18, minLines: 10,
                  style: text.bodyMedium,
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: scheme.surfaceContainerHigh.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(AppRadius.md)),
                  child: Row(children: [
                    Icon(Icons.cloud_sync_rounded, size: 14, color: scheme.outline),
                    const SizedBox(width: 6),
                    Expanded(child: Text('离线优先：输入自动保存到本地并入同步队列', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontSize: 11))),
                  ]),
                ),
              ],
            ),
      )),
    );
  }
}
